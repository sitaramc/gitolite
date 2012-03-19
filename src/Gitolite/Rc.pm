package Gitolite::Rc;

# everything to do with 'rc'.  Also defines some 'constants'
# ----------------------------------------------------------------------

@EXPORT = qw(
  %rc
  glrc
  query_rc
  version
  trigger

  $REMOTE_COMMAND_PATT
  $REF_OR_FILENAME_PATT
  $REPONAME_PATT
  $REPOPATT_PATT
  $USERNAME_PATT
  $UNSAFE_PATT
);

use Exporter 'import';
use Getopt::Long;

use Gitolite::Common;

# ----------------------------------------------------------------------

our %rc;

# ----------------------------------------------------------------------

# variables that could be overridden by the rc file
# ----------------------------------------------------------------------

$rc{GL_BINDIR}    = $ENV{GL_BINDIR};
$rc{GL_REPO_BASE} = "$ENV{HOME}/repositories";

$rc{GL_ADMIN_BASE} = "$ENV{HOME}/.gitolite";
$rc{LOG_TEMPLATE}  = "$ENV{HOME}/.gitolite/logs/gitolite-%y-%m.log";

# variables that should probably never be changed but someone will want to, I'll bet...
# ----------------------------------------------------------------------

$REMOTE_COMMAND_PATT  = qr(^[- 0-9a-zA-Z\@\%_=+:,./]*$);
$REF_OR_FILENAME_PATT = qr(^[0-9a-zA-Z][0-9a-zA-Z._\@/+ :,-]*$);
$REPONAME_PATT        = qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@/+-]*$);
$REPOPATT_PATT        = qr(^\@?[0-9a-zA-Z[][\\^.$|()[\]*+?{}0-9a-zA-Z._\@/,-]*$);
$USERNAME_PATT        = qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);
$UNSAFE_PATT          = qr([`~#\$\&()|;<>]);

# ----------------------------------------------------------------------

# find the rc file and 'do' it
# ----------------------------------------------------------------------

my $current_data_version = "3.0";

my $rc = glrc('filename');
do $rc if -r $rc;
_die "$rc seems to be for older gitolite" if defined($GL_ADMINDIR);
# let values specified in rc file override our internal ones
@rc{ keys %RC } = values %RC;

# (testing only) testing sometimes requires all of it to be overridden
# silently; use an env var that is highly unlikely to appear in real life :)
do $ENV{G3T_RC} if exists $ENV{G3T_RC} and -r $ENV{G3T_RC};

# fix some env vars, setup gitolite internal "env" vars (aka rc vars)
# ----------------------------------------------------------------------

# fix PATH (TODO: do it only if 'gitolite' isn't in PATH)
$ENV{PATH} = "$ENV{GL_BINDIR}:$ENV{PATH}";

{
    my ( $ts, $lfn ) = gen_ts_lfn( $rc{LOG_TEMPLATE} );
    $rc{GL_LOGFILE} = $ENV{GL_LOGFILE} = $lfn;
    $rc{GL_TS}      = $ENV{GL_TS}      = $ts;
}

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
        return "$ENV{HOME}/.gitolite.rc";
    } elsif ( $cmd eq 'default-text' ) {
        return $glrc_default_text if $glrc_default_text;
        _die "rc file default text not set; this should not happen!";
    } elsif ( $cmd eq 'filename' ) {
        # where is the rc file?

        # search $HOME first
        return "$ENV{HOME}/.gitolite.rc" if -f "$ENV{HOME}/.gitolite.rc";

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

# exported functions
# ----------------------------------------------------------------------

my $all  = 0;
my $nonl = 0;

sub query_rc {

    my @vars = args();

    no strict 'refs';

    if ($all) {
        for my $e ( sort keys %rc ) {
            print "$e=" . ( defined( $rc{$e} ) ? $rc{$e} : 'undef' ) . "\n";
        }
        exit 0;
    }

    my @res = map { $rc{$_} } grep { $rc{$_} } @vars;
    print join( "\t", @res ) . ( $nonl ? '' : "\n" ) if @res;
    # shell truth
    exit 0 if @res;
    exit 1;
}

sub version {
    my $version = '';
    $version = '(unknown)';
    for ("$rc{GL_ADMIN_BASE}/VERSION") {
        $version = slurp($_) if -r $_;
    }
    chomp($version);
    return $version;
}

sub trigger {
    my $rc_section = shift;

    if ( exists $rc{$rc_section} ) {
        if ( ref( $rc{$rc_section} ) ne 'ARRAY' ) {
            _die "$rc_section section in rc file is not a perl list";
        } else {
            for my $s ( @{ $rc{$rc_section} } ) {

                # perl-ism; apart from keeping the full path separate from the
                # simple name, this also protects %rc from change by implicit
                # aliasing, which would happen if you touched $s itself
                my $sfp = "$ENV{GL_BINDIR}/commands/$s";

                _warn("skipped command '$s'"), next if not -x $sfp;
                trace( 2, "command: $s" );
                _system( $sfp, @_ );    # they better all return with 0 exit codes!
            }
        }
        return;
    }
    trace( 2, "'$rc_section' not found in rc" );
}

# ----------------------------------------------------------------------

=for args
Usage:  gitolite query-rc -a
        gitolite query-rc [-n] <list of rc variables>

    -a          print all variables and values
    -n          do not append a newline

Example:

    gitolite query-rc GL_ADMIN_BASE UMASK
    # prints "/home/git/.gitolite<tab>0077" or similar

    gitolite query-rc -a
    # prints all known variables and values, one per line
=cut

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

# This file is in perl syntax.  But you do NOT need to know perl to edit it --
# just mind the commas, use single quotes unless you know what you're doing,
# and make sure the brackets and braces stay matched up!

# (Tip: perl allows a comma after the last item in a list also!)

%RC = (
    UMASK                       =>  0077,
    GIT_CONFIG_KEYS             =>  '',

    # add more roles (like MANAGER, TESTER, ...) here
    ROLES                       =>
        {
            READERS             =>  1,
            WRITERS             =>  1,
        },
    # uncomment (and change) this if you wish
    # DEFAULT_ROLE_PERMS          =>  'READERS @all',

    # comment out or uncomment as needed
    # these will run in sequence during the conf file parse
    SYNTACTIC_SUGAR             =>
        [
            # 'continuation-lines',
            'legacy-delegation-abort',
        ],

    # comment out or uncomment as needed
    # these will run in sequence after post-update
    POST_COMPILE                =>
        [
            'post-compile/ssh-authkeys',
            'post-compile/update-gitweb-access-list',
            'post-compile/update-git-daemon-access-list',
        ],

    # comment out or uncomment as needed
    # these will run in sequence after a new wild repo is created
    POST_CREATE                 =>
        [
            # 'post-compile/update-gitweb-access-list',
            # 'post-compile/update-git-daemon-access-list',
        ],

    # comment out or uncomment as needed
    # these are available to remote users
    COMMANDS                    =>
        {
            'help'              =>  1,
            'info'              =>  1,
            'perms'             =>  1,
        },
);

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;

# Local variables:
# mode: perl
# End:
# vim: set syn=perl:
