package Gitolite::Rc;

# everything to do with 'rc'.  Also defines some 'constants'
# ----------------------------------------------------------------------

@EXPORT = qw(
  %rc
  glrc
  query_rc
  version
  trigger
  _which

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

# pre-populate some important rc keys
# ----------------------------------------------------------------------

$rc{GL_BINDIR} = $ENV{GL_BINDIR};
$rc{GL_LIBDIR} = $ENV{GL_LIBDIR};

# these keys could be overridden by the rc file later
$rc{GL_REPO_BASE}  = "$ENV{HOME}/repositories";
$rc{GL_ADMIN_BASE} = "$ENV{HOME}/.gitolite";
$rc{LOG_TEMPLATE}  = "$ENV{HOME}/.gitolite/logs/gitolite-%y-%m.log";

# variables that should probably never be changed but someone will want to, I'll bet...
# ----------------------------------------------------------------------

#<<<
$REMOTE_COMMAND_PATT  =                qr(^[-0-9a-zA-Z._\@/+ :,\%=]*$);
$REF_OR_FILENAME_PATT =     qr(^[0-9a-zA-Z][-0-9a-zA-Z._\@/+ :,]*$);
$REPONAME_PATT        =  qr(^\@?[0-9a-zA-Z][-0-9a-zA-Z._\@/+]*$);
$REPOPATT_PATT        = qr(^\@?[[0-9a-zA-Z][-0-9a-zA-Z._\@/+\\^$|()[\]*?{},]*$);
$USERNAME_PATT        =  qr(^\@?[0-9a-zA-Z][-0-9a-zA-Z._\@+]*$);

$UNSAFE_PATT          = qr([`~#\$\&()|;<>]);
#>>>

# ----------------------------------------------------------------------

# find the rc file and 'do' it
# ----------------------------------------------------------------------
my $current_data_version = "3.2";

my $rc = glrc('filename');
if (-r $rc and -s $rc) {
    do $rc or die $@;
}
if ( defined($GL_ADMINDIR) ) {
    say2 "";
    say2 "FATAL: '$rc' seems to be for older gitolite; please see doc/g2migr.mkd\n" . "(online at http://sitaramc.github.com/gitolite/g2migr.html)";

    exit 1;
}

# let values specified in rc file override our internal ones
# ----------------------------------------------------------------------
@rc{ keys %RC } = values %RC;

# add internal triggers
# ----------------------------------------------------------------------

# is the server/repo in a writable state (i.e., not down for maintenance etc)
unshift @{ $rc{ACCESS_1} }, 'Writable::access_1';

# (testing only) override the rc file silently
# ----------------------------------------------------------------------
# use an env var that is highly unlikely to appear in real life :)
do $ENV{G3T_RC} if exists $ENV{G3T_RC} and -r $ENV{G3T_RC};

# setup some perl/rc/env vars
# ----------------------------------------------------------------------

unshift @INC, "$rc{LOCAL_CODE}/lib" if $rc{LOCAL_CODE};

$ENV{PATH} = "$ENV{GL_BINDIR}:$ENV{PATH}" unless $ENV{PATH} =~ /^$ENV{GL_BINDIR}:/;

{
    $rc{GL_TID} = $ENV{GL_TID} ||= $$;
    # TID: loosely, transaction ID.  The first PID at the entry point passes
    # it down to all its children so you can track each access, across all the
    # various commands it spawns and actions it generates.

    $rc{GL_LOGFILE} = $ENV{GL_LOGFILE} ||= gen_lfn( $rc{LOG_TEMPLATE} );
}

# these two are meant to help externally written commands (see
# src/commands/writable for an example)
$ENV{GL_REPO_BASE}  = $rc{GL_REPO_BASE};
$ENV{GL_ADMIN_BASE} = $rc{GL_ADMIN_BASE};

# add potential Git custom binaries path
$ENV{PATH} = "$rc{GIT_BINDIR}:$ENV{PATH}" if $rc{GIT_BINDIR};

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

        return '';
    } elsif ( $cmd eq 'current-data-version' ) {
        return $current_data_version;
    } else {
        _die "unknown argument to glrc: '$cmd'";
    }
}

# exported functions
# ----------------------------------------------------------------------

my $all   = 0;
my $nonl  = 0;
my $quiet = 0;

sub query_rc {

    my @vars = args();

    no strict 'refs';

    if ($all) {
        for my $e ( sort keys %rc ) {
            print "$e=" . ( defined( $rc{$e} ) ? $rc{$e} : 'undef' ) . "\n";
        }
        exit 0;
    }

    my $cv = \%rc;  # current "value"
    while (@vars) {
        my $v = shift @vars;

        # dig into the rc hash, using each var as a component
        if (not ref($cv)) {
            _warn "unused arguments...";
            last;
        } elsif (ref($cv) eq 'HASH') {
            $cv = $cv->{$v} || '';
        } elsif (ref($cv) eq 'ARRAY') {
            $cv = $cv->[$v] || '';
        } else {
            _die "dont know what to do with " . ref($cv) . " item in the rc file";
        }
    }

    # we've run out of arguments so $cv is what we have.  If we're supposed to
    # be quiet, we don't have to print anything so let's get that done first:
    exit ( $cv ? 0 : 1 ) if $quiet;     # shell truth

    # print values (notice we ignore the '-n' option if it's a ref)
    if (ref($cv) eq 'HASH') {
        print join("\n", sort keys %$cv), "\n" if %$cv;
    } elsif (ref($cv) eq 'ARRAY') {
        print join("\n", @$cv), "\n" if @$cv;
    } else {
        print $cv . ( $nonl ? '' : "\n" ) if $cv;
    }
    exit ( $cv ? 0 : 1 );   # shell truth
}

sub version {
    my $version = '';
    $version = '(unknown)';
    for ("$ENV{GL_BINDIR}/VERSION") {
        $version = slurp($_) if -r $_;
    }
    chomp($version);
    return $version;
}

sub trigger {
    my $rc_section = shift;

    if ( exists $rc{$rc_section} ) {
        if ( ref( $rc{$rc_section} ) ne 'ARRAY' ) {
            _die "'$rc_section' section in rc file is not a perl list";
        } else {
            for my $s ( @{ $rc{$rc_section} } ) {
                my ( $pgm, @args ) = split ' ', $s;

                if ( my ( $module, $sub ) = ( $pgm =~ /^(.*)::(\w+)$/ ) ) {

                    require Gitolite::Triggers;
                    trace( 1, 'trigger', $module, $sub, @args, $rc_section, @_ );
                    Gitolite::Triggers::run( $module, $sub, @args, $rc_section, @_ );

                } else {
                    $pgm = _which("triggers/$pgm", 'x');

                    _warn("skipped command '$s'"), next if not $pgm;
                    trace( 2, "command: $s" );
                    _system( $pgm, @args, $rc_section, @_ );    # they better all return with 0 exit codes!
                }
            }
        }
        return;
    }
    trace( 2, "'$rc_section' not found in rc" );
}

sub _which {
    # looks for a file in LOCAL_CODE or GL_BINDIR.  Returns whichever exists
    # (LOCAL_CODE preferred if defined) or 0 if not found.
    my $file = shift;
    my $mode = shift;   # could be 'x' or 'r'

    my @files = ("$rc{GL_BINDIR}/$file");
    unshift @files, ("$rc{LOCAL_CODE}/$file") if $rc{LOCAL_CODE};

    for my $f ( @files ) {
        return $f if -x $f;
        return $f if -r $f and $mode eq 'r';
    }

    return 0;
}

# ----------------------------------------------------------------------

=for args
Usage:  gitolite query-rc -a
        gitolite query-rc [-n] [-q] rc-variable

    -a          print all variables and values (first level only)
    -n          do not append a newline if variable is scalar
    -q          exit code only (shell truth; 0 is success)

Query the rc hash.  Second and subsequent arguments dig deeper into the hash.
The examples are for the default configuration; yours may be different.

Single values:
    gitolite query-rc GL_ADMIN_BASE     # prints "/home/git/.gitolite" or similar
    gitolite query-rc UMASK             # prints "63" (that's 0077 in decimal!)

Hashes:
    gitolite query-rc COMMANDS
        # prints "desc", "help", "info", "perms", "writable", one per line
    gitolite query-rc COMMANDS help     # prints 1
    gitolite query-rc -q COMMANDS help  # prints nothing; exit code is 0
    gitolite query-rc COMMANDS fork     # prints nothing; exit code is 1

Arrays (somewhat less useful):
    gitolite query-rc POST_GIT          # prints nothing; exit code is 0
    gitolite query-rc POST_COMPILE      # prints 4 lines
    gitolite query-rc POST_COMPILE 0    # prints the first of those 4 lines

Explore:
    gitolite query-rc -a
    # prints all first level variables and values, one per line.  Any that are
    # listed as HASH or ARRAY can be explored further in subsequent commands.
=cut

sub args {
    my $help = 0;

    GetOptions(
        'all|a'   => \$all,
        'nonl|n'  => \$nonl,
        'quiet|q' => \$quiet,
        'help|h'  => \$help,
    ) or usage();

    usage("'-a' cannot be combined with other arguments or options") if $all and ( @ARGV or $nonl or $quiet );
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

# HELP for commands (see COMMANDS list below) can be had by running the
# command with "-h" as the sole argument.

# HELP for all the other external programs (the syntactic sugar helpers and
# the various programs/functions in the 8 trigger lists), can be found in
# doc/non-core.mkd (http://sitaramc.github.com/gitolite/non-core.html) or in
# the corresponding source file itself.

%RC = (
    # if you're using mirroring, you need a hostname.  This is *one* simple
    # word, not a full domain name.  See documentation if in doubt
    # HOSTNAME                  =>  'darkstar',
    UMASK                       =>  0077,

    # look in the "GIT-CONFIG" section in the README for what to do
    GIT_CONFIG_KEYS             =>  '',

    # comment out if you don't need all the extra detail in the logfile
    LOG_EXTRA                   =>  1,

    # settings used by external programs; uncomment and change as needed.  You
    # can add your own variables for use in your own external programs; take a
    # look at the info and desc commands for perl and shell samples.

    # used by the CpuTime trigger
    # DISPLAY_CPU_TIME          =>  1,
    # CPU_TIME_WARN_LIMIT       =>  0.1,
    # used by the desc command
    # WRITER_CAN_UPDATE_DESC    =>  1,
    # used by the info command
    # SITE_INFO                 =>  'Please see http://blahblah/gitolite for more help',

    # comment out if your Git binaries are located outside your standard path
    # GIT_BINDIR => '/opt/bin',

    # add more roles (like MANAGER, TESTER, ...) here.
    #   WARNING: if you make changes to this hash, you MUST run 'gitolite
    #   compile' afterward, and possibly also 'gitolite trigger POST_COMPILE'
    ROLES                       =>
        {
            READERS             =>  1,
            WRITERS             =>  1,
        },
    # uncomment (and change) this if you wish
    # DEFAULT_ROLE_PERMS          =>  'READERS @all',

    # comment out or uncomment as needed
    # these are available to remote users
    COMMANDS                    =>
        {
            'help'              =>  1,
            'desc'              =>  1,
            # 'fork'            =>  1,
            'info'              =>  1,
            # 'mirror'          =>  1,
            'perms'             =>  1,
            # 'sskm'            =>  1,
            'writable'          =>  1,
            # 'D'               =>  1,
        },

    # comment out or uncomment as needed
    # these will run in sequence during the conf file parse
    SYNTACTIC_SUGAR             =>
        [
            # 'continuation-lines',
            # 'keysubdirs-as-groups',
        ],

    # comment out or uncomment as needed
    # these will run in sequence to modify the input (arguments and environment)
    INPUT                       =>
        [
            # 'CpuTime::input',
            # 'Shell::input',
            # 'Alias::input',
            # 'Mirroring::input',
        ],

    # comment out or uncomment as needed
    # these will run in sequence just after the first access check is done
    ACCESS_1                    =>
        [
        ],

    # comment out or uncomment as needed
    # these will run in sequence just before the actual git command is invoked
    PRE_GIT                     =>
        [
            # 'renice 10',
            # 'Mirroring::pre_git',
            # 'partial-copy',
        ],

    # comment out or uncomment as needed
    # these will run in sequence just after the second access check is done
    ACCESS_2                    =>
        [
        ],

    # comment out or uncomment as needed
    # these will run in sequence after the git command returns
    POST_GIT                    =>
        [
            # 'Mirroring::post_git',
            # 'CpuTime::post_git',
        ],

    # comment out or uncomment as needed
    # these will run in sequence before a new wild repo is created
    PRE_CREATE                  =>
        [
        ],

    # comment out or uncomment as needed
    # these will run in sequence after a new repo is created
    POST_CREATE                 =>
        [
            'post-compile/update-git-configs',
            'post-compile/update-gitweb-access-list',
            'post-compile/update-git-daemon-access-list',
        ],

    # comment out or uncomment as needed
    # these will run in sequence after post-update
    POST_COMPILE                =>
        [
            'post-compile/ssh-authkeys',
            'post-compile/update-git-configs',
            'post-compile/update-gitweb-access-list',
            'post-compile/update-git-daemon-access-list',
        ],
);

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;

# Local variables:
# mode: perl
# End:
# vim: set syn=perl:
