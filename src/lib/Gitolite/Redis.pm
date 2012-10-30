package Gitolite::Redis;

# redis interface
# ----------------------------------------------------------------------

@EXPORT = qw(
  db_add_group_member               db_get_memberships
                                    db_get_members
                                    db_get_groups
  db_add_repo                       db_get_repolist
  db_add_rule
  db_add_ruleset                    db_get_userlist
  db_add_config
  db_add_configset
  db_init
  db_done
  db_configs
  db_rules
);

use Exporter 'import';

use Gitolite::Common;
use Gitolite::Rc;
use Redis;

our $redis;

my $redis_sock = "$ENV{HOME}/.gitolite-redis.sock";
-S $redis_sock or _start_redis_server();
$redis = Redis->new(sock => $redis_sock, encoding => undef) or die "redis new failed: $!";
$redis->ping or die "redis ping failed: $!";

# ----------------------------------------------------------------------

sub db_add_group_member {
    my ($group, $member, $subconf) = @_;
    # yes we do it in reverse, member is a hash containing a bunch of group => subconf
    $redis->hsetnx("g:$member", $group, $subconf);

    # collect patterns hiding inside groups; best to do this right here
    $redis->sadd('patterns', $member) if $member =~ $REPONAME_PATT;
}

sub db_get_memberships {
    my $member = shift;
    return $redis->hkeys("g:$member");
}

sub db_get_members {
    my $group = shift;
    my @ret;

    for my $m ( $redis->keys('g:*') ) {
        push @ret, substr($m, 2) if $redis->hexists($m, $group);
    }

    return @ret;
}

sub db_get_groups {
    my %ret;
    for my $m ( $redis->keys('g:*') ) {
        map { $ret{$_} = 1 } $redis->hkeys($m);
    }

    return keys %ret;
}

sub db_add_repo {
    my $repo = shift;
    my $type = 'repopatterns';
    $type = 'reponames' if $repo =~ $REPONAME_PATT;
    $type = 'repogroups' if $repo =~ /^@/;
    $redis->sadd($type, $repo);
}

sub db_get_repolist {
    return (
      ( $redis->smembers('reponames') ),
      ( $redis->smembers('repogroups') ),
      ( $redis->smembers('repopatterns') ),
    );
}

sub db_add_rule {
    my($nextseq, $perm, $ref) = @_;
    $redis->set("r:$nextseq", "$perm\t$ref");
}

sub db_add_ruleset {
    my ($repo, $user, $nextseq) = @_;
    $redis->sadd("rs:$repo:$user", $nextseq);
}

sub db_get_userlist {
    my %u = map { s/.*://; $_ => 1 } $redis->keys('rs:*');
    return keys %u;
}

sub db_add_config {
    my($nextseq, $key, $value) = @_;
    $redis->set("c:$nextseq", "$key\t$value");
}

sub db_add_configset {
    my ($repo, $nextseq) = @_;
    $redis->sadd("cs:$repo", $nextseq);
}

sub db_init {
    $redis->flushall();
}
sub db_done {
    $redis->save();
}

# ----------------------------------------------------------------------

# ----------------------------------------------------------------------

sub _start_redis_server {
    my $conf = join("", <DATA>);
    $conf =~ s/%HOME/$ENV{HOME}/g;

    open( REDIS, "|-", "/usr/sbin/redis-server", "-" ) or die "start redis server failed: $!";
    print REDIS $conf;
    close REDIS;

    # give it a little time to come up
    select(undef,undef,undef,0.1);
}

sub db_configs {
    my ($repo, $g_repo) = @_;
    my $vk_configs = "vk_configs:$repo:$g_repo";
    my @configs;

    my $ttl = $redis->ttl($vk_configs);
    if ($ttl >= 1) {
        @configs = $redis->lrange($vk_configs, 0, -1);
    } else {
        my @rl = _expand_repo($repo, $g_repo);
        my @keys;
        for my $r (@rl) {
            push @keys, "cs:$r";
        }
        my $t = "$vk_configs-temp-$$";
        $redis->sunionstore($t, @keys);
        if ( $redis->exists($t) ) {
            # if there were any configs
            $redis->sort(( $t, "get", "c:*", "store", $vk_configs));
            @configs = $redis->lrange($vk_configs, 0, -1);
            $redis->expire($vk_configs, 5);
            $redis->del($t);
        }
    }
    # XXX test XXX make sure a key with an empty value comes back ok from this
    return map { [ split /\t/, $_ ] } @configs;
}

sub db_rules {
    my ($repo, $g_repo, $user) = @_;
    my $vk_rules = "vk_rules:$repo:$g_repo:$user";
    my @rules;

    my $ttl = $redis->ttl($vk_rules);
    if ($ttl >= 1) {
        @rules = $redis->lrange($vk_rules, 0, -1);
    } else {
        my @rl = _expand_repo($repo, $g_repo);
        my @ul = _expand_user($user, $repo);
        my @keys;
        for my $r (@rl) {
            for my $u (@ul) {
                push @keys, "rs:$r:$u";
            }
        }
        my $t = "$vk_rules-temp-$$";
        $redis->sunionstore($t, @keys);
        if ( $redis->exists($t) ) {
            # if there were any rules
            $redis->sort(( $t, "get", "r:*", "store", $vk_rules));
            @rules = $redis->lrange($vk_rules, 0, -1);
            $redis->expire($vk_rules, 5);
            $redis->del($t);
        }
    }
    return map { [ split /\t/, $_ ] } @rules;
}

sub _expand_repo {
    my ($repo, $g_repo) = @_;

    my @ret = ($repo, '@all');
    push @ret, $g_repo if $g_repo;

    # get all repopatterns, as well as patterns hiding in group names (which
    # may or may not have been used), and add if they match $repo or $g_repo
    for my $rp ( ( $redis->smembers('repopatterns') ), ( $redis->smembers('patterns') ) ) {
        push @ret, $rp if $repo =~ /^$rp$/ or $g_repo =~ /^$rp$/;
    }

    # add all the group names they (i.e., $repo, $g_repo, plus all the
    # patterns added so far) belong to
    my @t = @ret;
    for my $t (@t) {
        push @ret, $redis->hkeys("g:$t");
    }

    @ret = @{ sort_u( \@ret ) };
    return @ret;
}

sub _expand_user {
    my ($user, $repo) = @_;

    my @ret = ($user, '@all');

    # add all the group names that $user and @all belong to
    my @t = @ret;
    for my $t (@t) {
        push @ret, $redis->hkeys("g:$t");
    }

    # get any additional group names for the user from GROUPLIST_PGM
    push @ret, ( ext_grouplist($user) ) if $rc{GROUPLIST_PGM};

    if ( $repo ) {
        # find each role this user has when accessing this repo and add it as
        # a groupnames if one of the existing user/group names are listed as
        # having that role
        push @ret, user_roles( $repo, @ret );
    }

    @ret = @{ sort_u( \@ret ) };
    return @ret;
}

=for example

conf/gitolite.conf:
    @g1 = u1
    @g2 = u1
    # now user is a member of both g1 and g2

gl-perms for repo being accessed:
    READERS @g1

This should result in @READERS being added to the memberships that u1 has
(when accessing this repo).  So we send the current list (@g1, @g2) to
user_roles(), otherwise it has to redo that logic.

=cut

sub user_roles {
    # if it's not a wild repo, we don't care
    return () unless -f "$rc{GL_REPO_BASE}/$repo.git/gl-creator";

    my ( $repo, @eg ) = @_;

    # eg == existing groups (that user is already known to be a member of)
    my %eg = map { $_ => 1 } @eg;

    my %ret   = ();
    my $f     = "$rc{GL_REPO_BASE}/$repo.git/gl-perms";
    my @roles = ();
    if ( -f $f ) {
        my $fh = _open( "<", $f );
        chomp( @roles = <$fh> );
    }
    push @roles, "CREATOR = " . creator($repo);
    for (@roles) {
        # READERS u3 u4 @g1
        s/^\s+//; s/ +$//; s/=/ /; s/\s+/ /g; s/^\@//;
        my ( $role, @members ) = split;
        # role = READERS, members = u3, u4, @g1
        if ( $role ne 'CREATOR' and not $rc{ROLES}{$role} ) {
            _warn "role '$role' not allowed, ignoring";
            next;
        }
        for my $m (@members) {
            if ( $m !~ $USERNAME_PATT ) {
                _warn "ignoring '$m' in perms line";
                next;
            }
            # if any of u3, u4, or @g1 exists in %eg, he has role READERS
            $ret{ '@' . $role } = 1 if $eg{$m};
        }
    }

    return keys %ret;
}

sub ext_grouplist {
    my $user = shift;
    my $pgm  = $rc{GROUPLIST_PGM};

    my $vk_egl = "vk_egl:$user";

    my $ttl = $redis->ttl($vk_egl);
    return $redis->lrange($vk_egl, 0, -1) if $ttl >= 1;

    my @extgroups = map { s/^@?/@/; $_; } split ' ', `$rc{GROUPLIST_PGM} $user`;
    $redis->lpush($vk_egl, @extgroups);
    $redis->expire($vk_egl, 5);

    return @extgroups;
}

sub dd {
    use Data::Dumper;
    for my $i (@_) {
        print STDERR "DBG: " . Dumper($i);
    }
}

1;

__DATA__
# resources
maxmemory 50MB
port 0
unixsocket %HOME/.gitolite-redis.sock
unixsocketperm 700
timeout 0
databases 1

# daemon
daemonize yes
pidfile %HOME/.gitolite-redis.pid
dbfilename %HOME/.gitolite-redis.rdb
dir %HOME

# feedback
loglevel notice
logfile %HOME/.gitolite-redis.log

# safety
save 60 1
