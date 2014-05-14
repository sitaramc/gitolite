package Gitolite::Cache;

# cache stuff using an external database (redis)
# ----------------------------------------------------------------------

@EXPORT = qw(
  cache_control
  cache_wrap
);

use Exporter 'import';

use Gitolite::Common;
use Gitolite::Rc;
use Storable qw(freeze thaw);
use Redis;

my $redis;

my $redis_sock = "$ENV{HOME}/.redis-gitolite.sock";
if ( -S $redis_sock ) {
    _connect_redis();
} else {
    _start_redis();
    _connect_redis();

    # this redis db is a transient, caching only, db, so let's not
    # accidentally use any stale data when if we're just starting up
    cache_control('stop');
    cache_control('start');
}

# ----------------------------------------------------------------------

my %wrapped;
my $ttl = ( $rc{CACHE_TTL} || ( $rc{GROUPLIST_PGM} ? 900 : 90000 ) );

sub cache_control {
    my $op = shift;
    if ( $op eq 'stop' ) {
        $redis->flushall();
    } elsif ( $op eq 'start' ) {
        $redis->set( 'cache-up', 1 );
    } elsif ( $op eq 'flush' ) {
        flush_repo(@_);
    }
}

sub cache_wrap {
    my $sub   = shift;
    my $tname = $sub;    # this is what will show up in the trace output
    trace( 3, "wrapping '$sub'" );
    $sub = ( caller 1 )[0] . "::" . $sub if $sub !~ /::/;
    return if $wrapped{$sub}++;    # in case somehow it gets called twice for the same sub!

    # collect names of wrapped subs into a redis 'set'
    $redis->sadd( "SUBWAY", $sub );    # subway?  yeah well they wrap subs don't they?

    my $cref = eval '\&' . $sub;
    my %opt  = @_;
        # rest of the options come in as a hash.  'list' says this functions
        # returns a list.  'ttl' is a number to override the default ttl for
        # the cached value.

    no strict 'refs';
    no warnings 'redefine';
    *{$sub} = sub {                    # the wrapper function
        my $key = join( ", ", @_ );
        trace( 2, "$tname.args", @_ );

        if ( cache_up() and defined( my $val = $redis->get("$sub: $key") ) ) {
            # cache is up and we got a hit, return value from cache
            if ( $opt{list} ) {
                trace( 2, "$tname.getl", @{ thaw($val) } );
                return @{ thaw($val) };
            } else {
                trace( 2, "$tname.get", $val );
                return $val;
            }
        } else {
            # cache is down or we got a miss, compute
            my ( $r, @r );
            if ( $opt{list} ) {
                @r = $cref->(@_);    # provide list context
                trace( 2, "$tname.setl", @r );
            } else {
                $r = $cref->(@_);    # provide scalar context
                trace( 2, "$tname.set", $r );
            }

            # store computed value in cache if cache is up
            if ( cache_up() ) {
                $redis->set( "$sub: $key", ( $opt{list} ? freeze( \@r ) : $r ) );
                $redis->expire( "$sub: $key", $opt{ttl} || $ttl );
                trace( 2, "$tname.ttl", ( $opt{ttl} || $ttl ) );
            }

            return @r if $opt{list};
            return $r;
        }
    };
    trace( 3, "wrapped '$sub'" );
}

sub cache_up {
    return $redis->exists('cache-up');
}

sub flush_repo {
    my $repo = shift;

    my @wrapped = $redis->smembers("SUBWAY");
    for my $func (@wrapped) {
        # if we wrap any more functions, make sure they're functions where the
        # first argument is 'repo'
        my @keys = $redis->keys("$func: $repo, *");
        $redis->del( @keys ) if @keys;
    }
}

# ----------------------------------------------------------------------

sub _start_redis {
    my $conf = join( "", <DATA> );
    $conf =~ s/%HOME/$ENV{HOME}/g;

    open( REDIS, "|-", "/usr/sbin/redis-server", "-" ) or die "start redis server failed: $!";
    print REDIS $conf;
    close REDIS;

    # give it a little time to come up
    select( undef, undef, undef, 0.2 );
}

sub _connect_redis {
    $redis = Redis->new( sock => $redis_sock, encoding => undef ) or die "redis new failed: $!";
    $redis->ping or die "redis ping failed: $!";
}

1;

__DATA__
# resources
maxmemory 50MB
port 0
unixsocket %HOME/.redis-gitolite.sock
unixsocketperm 700
timeout 0
databases 1

# daemon
daemonize yes
pidfile %HOME/.redis-gitolite.pid
dbfilename %HOME/.redis-gitolite.rdb
dir %HOME

# feedback
loglevel notice
logfile %HOME/.redis-gitolite.log

# we don't save
