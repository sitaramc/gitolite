package Gitolite::Rc;

# everything to do with 'rc'.  Also defines some 'constants'
# ----------------------------------------------------------------------

@EXPORT = qw(
  %rc
  glrc
  query_rc

  $ADC_CMD_ARGS_PATT
  $REF_OR_FILENAME_PATT
  $REPONAME_PATT
  $REPOPATT_PATT
  $USERNAME_PATT
);

use Exporter 'import';
use Getopt::Long;

use Gitolite::Common;

# ----------------------------------------------------------------------

our %rc;

# ----------------------------------------------------------------------

# variables that are/could be/should be in the rc file
# ----------------------------------------------------------------------

$rc{GL_BINDIR}     = $ENV{GL_BINDIR};
$rc{GL_ADMIN_BASE} = "$ENV{HOME}/.gitolite";
$rc{GL_REPO_BASE}  = "$ENV{HOME}/repositories";

# variables that should probably never be changed
# ----------------------------------------------------------------------

$ADC_CMD_ARGS_PATT    = qr(^[0-9a-zA-Z._\@/+:-]*$);
$REF_OR_FILENAME_PATT = qr(^[0-9a-zA-Z][0-9a-zA-Z._\@/+ :,-]*$);
$REPONAME_PATT        = qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@/+-]*$);
$REPOPATT_PATT        = qr(^\@?[0-9a-zA-Z[][\\^.$|()[\]*+?{}0-9a-zA-Z._\@/,-]*$);
$USERNAME_PATT        = qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);

# ----------------------------------------------------------------------

my $current_data_version = "3.0";

my $rc = glrc('filename');
do $rc if -r $rc;
_die "$rc seems to be for older gitolite" if defined($GL_ADMINDIR);
# let values specified in rc file override our internal ones
@rc{ keys %RC } = values %RC;

# fix PATH (TODO: do it only if 'gitolite' isn't in PATH)
$ENV{PATH} = "$ENV{GL_BINDIR}:$ENV{PATH}";

# ----------------------------------------------------------------------

use strict;
use warnings;

# ----------------------------------------------------------------------

my $glrc_default_text = '';
{
    local $/ = undef;
    $glrc_default_text = <DATA>;
}

sub glrc {
    my $cmd = shift;
    if ( $cmd eq 'default-filename' ) {
        trace( 1, "..should happen only on first run" );
        return "$ENV{HOME}/.gitolite.rc";
    } elsif ( $cmd eq 'default-text' ) {
        trace( 1, "..should happen only on first run" );
        return $glrc_default_text if $glrc_default_text;
        _die "rc file default text not set; this should not happen!";
    } elsif ( $cmd eq 'filename' ) {
        # where is the rc file?
        trace(4);

        # search $HOME first
        return "$ENV{HOME}/.gitolite.rc" if -f "$ENV{HOME}/.gitolite.rc";
        trace( 2, "$ENV{HOME}/.gitolite.rc not found" );

        # XXX for fedora, we can add the following line, but I would really prefer
        # if ~/.gitolite.rc on each $HOME was just a symlink to /etc/gitolite.rc
        # XXX return "/etc/gitolite.rc" if -f "/etc/gitolite.rc";

        return '';
    } elsif ( $cmd eq 'current-data-version' ) {
        return $current_data_version;
    } else {
        _die "unknown argument to glrc: $cmd";
    }
}

# ----------------------------------------------------------------------
# implements 'gitolite query-rc'
# ----------------------------------------------------------------------

=for usage

Usage:  gitolite query-rc -a
        gitolite query-rc [-n] <list of rc variables>

    -a          print all variables and values
    -n          do not append a newline

Example:

    gitolite query-rc GL_ADMIN_BASE GL_UMASK
    # prints "/home/git/.gitolite<tab>0077" or similar

    gitolite query-rc -a
    # prints all known variables and values, one per line
=cut

# ----------------------------------------------------------------------

my $all = 0;
my $nonl = 0;

sub query_rc {
    trace( 1, "rc file not found; default should be " . glrc('default-filename') ) if not glrc('filename');

    my @vars = args();

    no strict 'refs';

    if ( $all ) {
        for my $e (sort keys %rc) {
            print "$e=" . ( defined($rc{$e}) ? $rc{$e} : 'undef' ) . "\n";
        }
        return;
    }

    print join( "\t", map { $rc{$_} || '' } @vars ) . ($nonl ? '' : "\n") if @vars;
}

# ----------------------------------------------------------------------

sub args {
    my $help = 0;

    GetOptions(
        'all|a'  => \$all,
        'nonl|n' => \$nonl,
        'help|h' => \$help,
    ) or usage();

    usage("'-a' cannot be combined with other arguments") if $all and @ARGV;
    usage() if not $all and not @ARGV or $help;
    return @ARGV;
}

1;

# ----------------------------------------------------------------------

__DATA__
# configuration variables for gitolite

# PLEASE READ THE DOCUMENTATION BEFORE EDITING OR ASKING QUESTIONS

# this file is in perl syntax.  However, you do NOT need to know perl to edit
# it; it should be fairly self-explanatory and easy to maintain.  Just mind
# the commas, make sure the brackets and braces stay matched up!

%RC = (
    UMASK                       =>  0077,
    GL_GITCONFIG_KEYS           =>  "",

    # uncomment as needed
    SYNTACTIC_SUGAR             =>
        [
            # 'continuation-lines',
        ]
);

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;

# Local variables:
# mode: perl
# End:
# vim: set syn=perl:
