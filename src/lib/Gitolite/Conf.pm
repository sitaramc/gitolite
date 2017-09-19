package Gitolite::Conf;

# explode/parse a conf file
# ----------------------------------------------------------------------

@EXPORT = qw(
  compile
  explode
  parse
);

use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Sugar;
use Gitolite::Conf::Store;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub compile {
    _die "'gitolite compile' does not take any arguments" if @_;

    _chdir( $rc{GL_ADMIN_BASE} );
    _chdir("conf");

    parse( sugar('gitolite.conf') );

    # the order matters; new repos should be created first, to give store a
    # place to put the individual gl-conf files
    new_repos();

    # cache control
    if ($rc{CACHE}) {
        require Gitolite::Cache;
        Gitolite::Cache->import(qw(cache_control));

        cache_control('stop');
    }

    store();

    if ($rc{CACHE}) {
        cache_control('start');
    }

    # remove entries from POST_CREATE which also exist in POST_COMPILE.  This
    # not only saves us having to implement an optimisation in *those*
    # scripts, but more importantly, moves the optimisation one step up -- we
    # don't even *call* those scripts now.
    my %pco = map { $_ => 1 } @{ $rc{POST_COMPILE} };
    @{ $rc{POST_CREATE} } = grep { ! exists $pco{$_} } @{ $rc{POST_CREATE} };

    for my $repo ( @{ $rc{NEW_REPOS_CREATED} } ) {
        trigger( 'POST_CREATE', $repo );
    }
}

sub parse {
    my $lines = shift;
    trace( 3, scalar(@$lines) . " lines incoming" );

    my ( $fname, $lnum );
    for my $line (@$lines) {
        ( $fname, $lnum ) = ( $1, $2 ), next if $line =~ /^# (\S+) (\d+)$/;
        # user or repo groups
        if ( $line =~ /^(@\S+) = (.*)/ ) {
            add_to_group( $1, split( ' ', $2 ) );
        } elsif ( $line =~ /^repo (.*)/ ) {
            set_repolist( split( ' ', $1 ) );
        } elsif ( $line =~ /^(-|C|R|RW\+?(?:C?D?|D?C?)M?) (.* )?= (.+)/ ) {
            my $perm  = $1;
            my @refs  = parse_refs( $2 || '' );
            my @users = parse_users($3);

            for my $ref (@refs) {
                for my $user (@users) {
                    add_rule( $perm, $ref, $user, $fname, $lnum );
                }
            }
        } elsif ( $line =~ /^config (.+) = ?(.*)/ ) {
            my ( $key, $value ) = ( $1, $2 );
            $value =~ s/^['"](.*)["']$/$1/;
            my @validkeys = split( ' ', ( $rc{GIT_CONFIG_KEYS} || '' ) );
            push @validkeys, "gitolite-options\\..*";
            my @matched = grep { $key =~ /^$_$/i } @validkeys;
            _die "git config '$key' not allowed\ncheck GIT_CONFIG_KEYS in the rc file" if ( @matched < 1 );
            _die "bad config value '$value'" if $value =~ $UNSAFE_PATT;
            while ( my ( $mk, $mv ) = each %{ $rc{SAFE_CONFIG} } ) {
                $value =~ s/%$mk/$mv/g;
            }
            add_config( 1, $key, $value );
        } elsif ( $line =~ /^subconf (\S+)$/ ) {
            trace( 3, $line );
            set_subconf($1);
        } else {
            _warn "syntax error, ignoring: '$line'";
        }
    }
    parse_done();
}

1;
