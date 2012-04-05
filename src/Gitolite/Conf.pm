package Gitolite::Conf;

# explode/parse a conf file
# ----------------------------------------------------------------------

@EXPORT = qw(
  compile
  explode
  parse
);

use Exporter 'import';
use Getopt::Long;

use Gitolite::Common;
use Gitolite::Rc;
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
    store();
}

sub parse {
    my $lines = shift;
    trace( 2, scalar(@$lines) . " lines incoming" );

    for my $line (@$lines) {
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
                    add_rule( $perm, $ref, $user );
                }
            }
        } elsif ( $line =~ /^config (.+) = ?(.*)/ ) {
            my ( $key, $value ) = ( $1, $2 );
            $value =~ s/^['"](.*)["']$/$1/;
            my @validkeys = split( ' ', ( $rc{GIT_CONFIG_KEYS} || '' ) );
            push @validkeys, "gitolite-options\\..*";
            my @matched = grep { $key =~ /^$_$/ } @validkeys;
            _die "git config $key not allowed\ncheck GIT_CONFIG_KEYS in the rc file" if ( @matched < 1 );
            _die "bad value '$value'" if $value =~ $UNSAFE_PATT;
            add_config( 1, $key, $value );
        } elsif ( $line =~ /^subconf (\S+)$/ ) {
            trace( 2, $line );
            set_subconf($1);
        } else {
            _warn "?? $line";
        }
    }
    parse_done();
}

1;
