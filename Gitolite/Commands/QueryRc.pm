package Gitolite::Commands::QueryRc;

# implements 'gitolite query-rc'
# ----------------------------------------------------------------------

=for usage

Usage:  gitolite query-rc -a
        gitolite query-rc <list of rc variables>

Example:

    gitolite query-rc GL_ADMIN_BASE GL_UMASK
    # prints "/home/git/.gitolite<tab>0077" or similar

    gitolite query-rc -a
    # prints all known variables and values, one per line
=cut

# ----------------------------------------------------------------------

@EXPORT = qw(
  query_rc
);

use Exporter 'import';
use Getopt::Long;

use lib $ENV{GL_BINDIR};
use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# ----------------------------------------------------------------------

my $all = 0;

# ----------------------------------------------------------------------

sub query_rc {
    trace( 1, "rc file not found; default should be " . glrc_default_filename() ) if not glrc_filename();

    my @vars = args();

    no strict 'refs';

    if ( $vars[0] eq '-a' ) {
        for my $e (@Gitolite::Rc::EXPORT) {
            # perl-ism warning: if you don't do this the implicit aliasing
            # screws up Rc's EXPORT list
            my $v = $e;
            # we stop on the first non-$ var
            last unless $v =~ s/^\$//;
            print "$v=" . ( defined($$v) ? $$v : 'undef' ) . "\n";
        }
    }

    our $GL_BINDIR = $ENV{GL_BINDIR};

    print join( "\t", map { $$_ } grep { $$_ } @vars ) . "\n" if @vars;
}

# ----------------------------------------------------------------------

sub args {
    my $help = 0;

    GetOptions(
        'all|a'  => \$all,
        'help|h' => \$help,
    ) or usage();

    usage("'-a' cannot be combined with other arguments") if $all and @ARGV;
    return '-a' if $all;
    usage() if not @ARGV or $help;
    return @ARGV;
}

1;
