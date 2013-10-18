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
our $non_core;

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
    say2 "FATAL: '$rc' seems to be for older gitolite; please see doc/g2migr.mkd\n" . "(online at http://gitolite.com/gitolite/g2migr.html)";

    exit 1;
}

# let values specified in rc file override our internal ones
# ----------------------------------------------------------------------
@rc{ keys %RC } = values %RC;

# expand the non_core list into INPUT, PRE_GIT, etc using 'ENABLE' settings
non_core_expand() if $rc{ENABLE};

# add internal triggers
# ----------------------------------------------------------------------

# is the server/repo in a writable state (i.e., not down for maintenance etc)
unshift @{ $rc{ACCESS_1} }, 'Writable::access_1';

# (testing only) override the rc file silently
# ----------------------------------------------------------------------
# use an env var that is highly unlikely to appear in real life :)
do $ENV{G3T_RC} if exists $ENV{G3T_RC} and -r $ENV{G3T_RC};

# setup some perl/rc/env vars, plus umask
# ----------------------------------------------------------------------

umask ( $rc{UMASK} || 0077 );

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

# ----------------------------------------------------------------------

use strict;
use warnings;

# ----------------------------------------------------------------------

my $glrc_default_text = '';
{
    local $/ = undef;
    $glrc_default_text = <DATA>;
}

# ----------------------------------------------------------------------

sub non_core_expand {
    my %enable;

    for my $e ( @{ $rc{ENABLE} } ) {
        my ($name, $arg) = split ' ', $e, 2;
        # store args as the hash value for the name
        $enable{$name} = $arg || '';

        # for now, we pretend everything is a command, because commands
        # are the only thing that the non_core list does not contain
        $rc{COMMANDS}{$name} = $arg || 1;
    }

    # bring in additional non-core specs from the rc file, if given
    if (my $nc2 = $rc{NON_CORE}) {
        for ($non_core, $nc2) {
            # beat 'em into shape :)
            s/#.*//g;
            s/[ \t]+/ /g; s/^ //mg; s/ $//mg;
            s/\n+/\n/g;
        }

        for ( split "\n", $nc2 ) {
            next unless /\S/;
            my ($name, $where, $module, $before, $name2) = split ' ', $_;
            if (not $before) {
                $non_core .= "$name $where $module\n";
                next;
            }
            die if $before ne 'before';
            $non_core =~ s(^(?=$name2 $where( |$)))($name $where $module\n)m;
        }
    }

    my @data = split "\n", $non_core || '';
    for (@data) {
        next if /^\s*(#|$)/;
        my ($name, $where, $module) = split ' ', $_;

        # if it appears here, it's not a command, so delete it.  At the end of
        # this loop, what's left in $rc{COMMANDS} will be those names in the
        # enable list that do not appear in the non_core list.
        delete $rc{COMMANDS}{$name};

        next unless exists $enable{$name};

        # module to call is name if specified as "."
        $module = $name if $module eq ".";

        # module to call is "name::pre_git" or such if specified as "::"
        ( $module = $name ) .= "::" . lc($where) if $module eq '::';

        # append arguments, if supplied
        $module .= " $enable{$name}" if $enable{$name};

        push @{ $rc{$where} }, $module;
    }
}

# exported functions
# ----------------------------------------------------------------------

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

    # if arg-2 (now arg-1, due to the 'shift' above) exists, it is a repo
    # name, so setup env from options
    require Gitolite::Conf::Load;
    Gitolite::Conf::Load->import('env_options');
    env_options($_[0]) if $_[0];

    if ( exists $rc{$rc_section} ) {
        if ( ref( $rc{$rc_section} ) ne 'ARRAY' ) {
            _die "'$rc_section' section in rc file is not a perl list";
        } else {
            for my $s ( @{ $rc{$rc_section} } ) {
                my ( $pgm, @args ) = split ' ', $s;

                if ( my ( $module, $sub ) = ( $pgm =~ /^(.*)::(\w+)$/ ) ) {

                    require Gitolite::Triggers;
                    trace( 2, 'trigger module', $module, $sub, @args, $rc_section, @_ );
                    Gitolite::Triggers::run( $module, $sub, @args, $rc_section, @_ );

                } else {
                    $pgm = _which("triggers/$pgm", 'x');

                    _warn("skipped trigger '$s' (not found or not executable)"), next if not $pgm;
                    trace( 2, 'trigger command', $s );
                    _system( $pgm, @args, $rc_section, @_ );    # they better all return with 0 exit codes!
                }
            }
        }
        return;
    }
    trace( 3, "'$rc_section' not found in rc" );
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

# ----------------------------------------------------------------------

BEGIN { $non_core = "
    # No user-servicable parts inside.  Warranty void if seal broken.  Refer
    # servicing to authorised service center only.

    continuation-lines      SYNTACTIC_SUGAR .
    keysubdirs-as-groups    SYNTACTIC_SUGAR .
    macros                  SYNTACTIC_SUGAR .
    refex-expr              SYNTACTIC_SUGAR .

    renice                  PRE_GIT         .

    CpuTime                 INPUT           ::
    CpuTime                 POST_GIT        ::

    Shell                   INPUT           ::

    Alias                   INPUT           ::

    Mirroring               INPUT           ::
    Mirroring               PRE_GIT         ::
    Mirroring               POST_GIT        ::

    refex-expr              ACCESS_2        RefexExpr::access_2

    RepoUmask               PRE_GIT         ::
    RepoUmask               POST_CREATE     ::

    partial-copy            PRE_GIT         .

    upstream                PRE_GIT         .

    no-create-on-read       PRE_CREATE      AutoCreate::deny_R
    no-auto-create          PRE_CREATE      AutoCreate::deny_RW

    ssh-authkeys-split      POST_COMPILE    post-compile/ssh-authkeys-split
    ssh-authkeys            POST_COMPILE    post-compile/ssh-authkeys
    Shell                   POST_COMPILE    post-compile/ssh-authkeys-shell-users

    set-default-roles       POST_CREATE     .

    git-config              POST_COMPILE    post-compile/update-git-configs
    git-config              POST_CREATE     post-compile/update-git-configs

    gitweb                  POST_CREATE     post-compile/update-gitweb-access-list
    gitweb                  POST_COMPILE    post-compile/update-gitweb-access-list

    cgit                    POST_COMPILE    post-compile/update-description-file

    daemon                  POST_CREATE     post-compile/update-git-daemon-access-list
    daemon                  POST_COMPILE    post-compile/update-git-daemon-access-list

    repo-specific-hooks     POST_COMPILE    .
    repo-specific-hooks     POST_CREATE     .
";
}

1;

# ----------------------------------------------------------------------

__DATA__
# configuration variables for gitolite

# This file is in perl syntax.  But you do NOT need to know perl to edit it --
# just mind the commas, use single quotes unless you know what you're doing,
# and make sure the brackets and braces stay matched up!

# (Tip: perl allows a comma after the last item in a list also!)

# HELP for commands can be had by running the command with "-h".

# HELP for all the other FEATURES can be found in the documentation (look for
# "list of non-core programs shipped with gitolite" in the master index) or
# directly in the corresponding source file.

%RC = (

    # ------------------------------------------------------------------

    # default umask gives you perms of '0700'; see the rc file docs for
    # how/why you might change this
    UMASK                           =>  0077,

    # look for "git-config" in the documentation
    GIT_CONFIG_KEYS                 =>  '',

    # comment out if you don't need all the extra detail in the logfile
    LOG_EXTRA                       =>  1,

    # roles.  add more roles (like MANAGER, TESTER, ...) here.
    #   WARNING: if you make changes to this hash, you MUST run 'gitolite
    #   compile' afterward, and possibly also 'gitolite trigger POST_COMPILE'
    ROLES => {
        READERS                     =>  1,
        WRITERS                     =>  1,
    },

    # ------------------------------------------------------------------

    # rc variables used by various features

    # the 'info' command prints this as additional info, if it is set
        # SITE_INFO                 =>  'Please see http://blahblah/gitolite for more help',

    # the 'desc' command uses this
        # WRITER_CAN_UPDATE_DESC    =>  1,

    # the CpuTime feature uses these
        # display user, system, and elapsed times to user after each git operation
        # DISPLAY_CPU_TIME          =>  1,
        # display a warning if total CPU times (u, s, cu, cs) crosses this limit
        # CPU_TIME_WARN_LIMIT       =>  0.1,

    # the Mirroring feature needs this
        # HOSTNAME                  =>  "foo",

    # if you enabled 'Shell', you need this
        # SHELL_USERS_LIST          =>  "$ENV{HOME}/.gitolite.shell-users",

    # ------------------------------------------------------------------

    # suggested locations for site-local gitolite code (see cust.html)

        # this one is managed directly on the server
        # LOCAL_CODE                =>  "$ENV{HOME}/local",

        # or you can use this, which lets you put everything in a subdirectory
        # called "local" in your gitolite-admin repo.  For a SECURITY WARNING
        # on this, see http://gitolite.com/gitolite/cust.html#pushcode
        # LOCAL_CODE                =>  "$rc{GL_ADMIN_BASE}/local",

    # ------------------------------------------------------------------

    # List of commands and features to enable

    ENABLE => [

        # COMMANDS

            # These are the commands enabled by default
            'help',
            'desc',
            'info',
            'perms',
            'writable',

            # Uncomment or add new commands here.
            # 'create',
            # 'fork',
            # 'mirror',
            # 'sskm',
            # 'D',

        # These FEATURES are enabled by default.

            # essential (unless you're using smart-http mode)
            'ssh-authkeys',

            # creates git-config enties from gitolite.conf file entries like 'config foo.bar = baz'
            'git-config',

            # creates git-daemon-export-ok files; if you don't use git-daemon, comment this out
            'daemon',

            # creates projects.list file; if you don't use gitweb, comment this out
            'gitweb',

        # These FEATURES are disabled by default; uncomment to enable.  If you
        # need to add new ones, ask on the mailing list :-)

        # user-visible behaviour

            # prevent wild repos auto-create on fetch/clone
            # 'no-create-on-read',
            # no auto-create at all (don't forget to enable the 'create' command!)
            # 'no-auto-create',

            # access a repo by another (possibly legacy) name
            # 'Alias',

            # give some users direct shell access
            # 'Shell',

            # set default roles from lines like 'option default.roles-1 = ...', etc.
            # 'set-default-roles',

        # system admin stuff

            # enable mirroring (don't forget to set the HOSTNAME too!)
            # 'Mirroring',

            # allow people to submit pub files with more than one key in them
            # 'ssh-authkeys-split',

            # selective read control hack
            # 'partial-copy',

            # manage local, gitolite-controlled, copies of read-only upstream repos
            # 'upstream',

            # updates 'description' file instead of 'gitweb.description' config item
            # 'cgit',

            # allow repo-specific hooks to be added
            # 'repo-specific-hooks',

        # performance, logging, monitoring...

            # be nice
            # 'renice 10',

            # log CPU times (user, system, cumulative user, cumulative system)
            # 'CpuTime',

        # syntactic_sugar for gitolite.conf and included files

            # allow backslash-escaped continuation lines in gitolite.conf
            # 'continuation-lines',

            # create implicit user groups from directory names in keydir/
            # 'keysubdirs-as-groups',

            # allow simple line-oriented macros
            # 'macros',

    ],

);

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;

# Local variables:
# mode: perl
# End:
# vim: set syn=perl:
