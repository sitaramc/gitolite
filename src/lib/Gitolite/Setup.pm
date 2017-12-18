package Gitolite::Setup;

# implements 'gitolite setup'
# ----------------------------------------------------------------------

=for args
Usage:  gitolite setup [<option>]

Setup gitolite, compile conf, run the POST_COMPILE trigger (see rc file) and
propagate hooks.

    -a, --admin <name>          admin name
    -pk, --pubkey <file>        pubkey file name
    -ho, --hooks-only           skip other steps and just propagate hooks
    -m, --message               set setup commit message

First run: either the pubkey or the admin name is *required*, depending on
whether you're using ssh mode or http mode.

Subsequent runs:

  - Without options, 'gitolite setup' is a general "fix up everything" command
    (for example, if you brought in repos from outside, or someone messed
    around with the hooks, or you made an rc file change that affects access
    rules, etc.)

  - '-pk' can be used to replace the admin key; useful if you lost the admin's
    private key but do have shell access to the server.

  - '-ho' is mainly for scripting use.  Do not combine with other options.

  - '-a' is ignored

  - '-m' can be used to replace default commit message "gitolite setup $argv"
    with a custom message (e.g. "Setting up your repository mgmt").

=cut

# ----------------------------------------------------------------------

@EXPORT = qw(
  setup
);

use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Store;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub setup {
    my ( $admin, $pubkey, $h_only, $message ) = args();

    unless ($h_only) {
        setup_glrc();
        setup_gladmin( $admin, $pubkey, $message );

        _system("gitolite compile");
        _system("gitolite trigger POST_COMPILE");
    }

    hook_repos();    # all of them, just to be sure
}

# ----------------------------------------------------------------------

sub args {
    my $admin   = '';
    my $pubkey  = '';
    my $message = '';
    my $h_only  = 0;
    my $help    = 0;
    my $argv    = join( " ", @ARGV );

    require Getopt::Long;
    Getopt::Long::GetOptions(
        'admin|a=s'     => \$admin,
        'pubkey|pk=s'   => \$pubkey,
        'message|m=s'   => \$message,
        'hooks-only|ho' => \$h_only,
        'help|h'        => \$help,
    ) or usage();

    usage() if $help or ( $pubkey and $admin );
    usage() if $h_only and ( $admin or $pubkey );

    if ($pubkey) {
        $pubkey =~ /\.pub$/                 or _die "'$pubkey' name does not end in .pub";
        tsh_try("cat $pubkey")              or _die "'$pubkey' not a readable file";
        tsh_lines() == 1                    or _die "'$pubkey' must have exactly one line";
        tsh_try("ssh-keygen -l -f $pubkey") or _die "'$pubkey' does not seem to be a valid ssh pubkey file";

        $admin = $pubkey;
        # next 2 lines duplicated from args() in ssh-authkeys
        $admin =~ s(.*/)();                # foo/bar/baz.pub -> baz.pub
        $admin =~ s/(\@[^.]+)?\.pub$//;    # baz.pub, baz@home.pub -> baz
        $pubkey =~ /\@/ and print STDERR "NOTE: the admin username is '$admin'\n";

    }

    return ( $admin || '', $pubkey || '', $h_only || 0, $message || "gitolite setup $argv");
}

sub setup_glrc {
    _print( glrc('default-filename'), glrc('default-text') ) if not glrc('filename');
}

sub setup_gladmin {
    my ( $admin, $pubkey, $message ) = @_;
    _die "'-pk' or '-a' required; see 'gitolite setup -h' for more"
      if not $admin and not -f "$rc{GL_ADMIN_BASE}/conf/gitolite.conf";

    # grab the pubkey content before we chdir() away
    my $pubkey_content = '';
    $pubkey_content = slurp($pubkey) if $pubkey;

    # set up the admin files in admin-base

    _mkdir( $rc{GL_ADMIN_BASE} );
    _chdir( $rc{GL_ADMIN_BASE} );

    _mkdir("conf");
    _mkdir("logs");
    my $conf;
    {
        local $/ = undef;
        $conf = <DATA>;
    }
    $conf =~ s/%ADMIN/$admin/g;
    $conf =~ s/%REPO_DE_ADMIN/$rc{GL_ADMIN_REPO}/g;

    _print( "conf/gitolite.conf", $conf ) if not -f "conf/gitolite.conf";

    if ($pubkey) {
        _mkdir("keydir");
        _print( "keydir/$admin.pub", $pubkey_content );
    }

    # set up the admin repo in repo-base

    _chdir();
    _mkdir( "$rc{GL_REPO_BASE}" );
    _chdir( "$rc{GL_REPO_BASE}" );
    new_repo("$rc{GL_ADMIN_REPO}") if not -d "$rc{GL_ADMIN_REPO}.git";

    # commit the admin files to the admin repo

    $ENV{GIT_WORK_TREE} = $rc{GL_ADMIN_BASE};
    _chdir("$rc{GL_REPO_BASE}/$rc{GL_ADMIN_REPO}.git");
    _system("git add conf/gitolite.conf");
    _system("git add keydir") if $pubkey;
    tsh_try("git config --get user.email") or tsh_run( "git config user.email $ENV{USER}\@" . `hostname` );
    tsh_try("git config --get user.name")  or tsh_run( "git config user.name '$ENV{USER} on '" . `hostname` );
    tsh_try("git diff --cached --quiet")
      or tsh_try("git commit -am '$message'")
      or _die "setup failed to commit to the admin repo";
    delete $ENV{GIT_WORK_TREE};
}

1;

__DATA__
repo %REPO_DE_ADMIN
    RW+     =   %ADMIN

repo testing
    RW+     =   @all
