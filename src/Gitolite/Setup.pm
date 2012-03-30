package Gitolite::Setup;

# implements 'gitolite setup'
# ----------------------------------------------------------------------

=for args
Usage:  gitolite setup [<option>]

    -pk, --pubkey <file>        pubkey file name

Setup gitolite, compile conf, and fixup hooks.  The pubkey is required on the
first run.

Subsequent runs:

  - 'gitolite setup': fix up hooks if you brought in repos from outside, or if
    someone has been playing around with the hooks and may have deleted some.

  - 'gitolite setup -pk YourName.pub': replace keydir/YourName.pub and
    recompile/push.  Useful if you lost your key.  In fact you can do this for
    any key in keydir (but not in subdirectories).
=cut

# ----------------------------------------------------------------------

@EXPORT = qw(
  setup
);

use Exporter 'import';
use Getopt::Long;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Store;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub setup {
    my ( $admin, $pubkey, $argv ) = args();
    setup_glrc();
    setup_gladmin( $admin, $pubkey, $argv );

    _system("$ENV{GL_BINDIR}/gitolite compile");
    _system("$ENV{GL_BINDIR}/gitolite trigger POST_COMPILE");

    hook_repos();    # all of them, just to be sure
}

# ----------------------------------------------------------------------

sub args {
    my $admin  = '';
    my $pubkey = '';
    my $help   = 0;
    my $argv   = join( " ", @ARGV );

    GetOptions(
        'admin|a=s'   => \$admin,
        'pubkey|pk=s' => \$pubkey,
        'help|h'      => \$help,
    ) or usage();

    usage() if $help or ( $pubkey and $admin );

    if ($pubkey) {
        $pubkey =~ /\.pub$/ or _die "$pubkey name does not end in .pub";
        $pubkey =~ /\@/ and _die "$pubkey name contains '\@'";
        tsh_try("cat $pubkey")              or _die "$pubkey not a readable file";
        tsh_lines() == 1                    or _die "$pubkey must have exactly one line";
        tsh_try("ssh-keygen -l -f $pubkey") or _die "$pubkey does not seem to be a valid ssh pubkey file";

        $admin = $pubkey;
        $admin =~ s(.*/)();
        $admin =~ s/\.pub$//;
    }

    return ( $admin || '', $pubkey || '', $argv );
}

sub setup_glrc {
    _print( glrc('default-filename'), glrc('default-text') ) if not glrc('filename');
}

sub setup_gladmin {
    my ( $admin, $pubkey, $argv ) = @_;
    _die "no existing conf file found, '-a' required"
      if not $admin and not -f "$rc{GL_ADMIN_BASE}/conf/gitolite.conf";

    # reminder: 'admin files' are in ~/.gitolite, 'admin repo' is
    # $rc{GL_REPO_BASE}/gitolite-admin.git

    # grab the pubkey content before we chdir() away
    my $pubkey_content = '';
    $pubkey_content = slurp($pubkey) if $pubkey;

    # set up the admin files in admin-base

    _mkdir( $rc{GL_ADMIN_BASE} );
    _chdir( $rc{GL_ADMIN_BASE} );

    tsh_try("cd \$GL_BINDIR; git describe --tags --long --dirty=-dt 2>/dev/null")
      and _print( "VERSION", tsh_text() );

    _mkdir("conf");
    _mkdir("logs");
    my $conf;
    {
        local $/ = undef;
        $conf = <DATA>;
    }
    $conf =~ s/%ADMIN/$admin/g;

    _print( "conf/gitolite.conf", $conf ) if not -f "conf/gitolite.conf";

    if ($pubkey) {
        _mkdir("keydir");
        _print( "keydir/$admin.pub", $pubkey_content );
    }

    # set up the admin repo in repo-base

    _chdir();
    _mkdir( $rc{GL_REPO_BASE} );
    _chdir( $rc{GL_REPO_BASE} );

    new_repo("gitolite-admin") if not -d "gitolite-admin.git";

    # commit the admin files to the admin repo

    $ENV{GIT_WORK_TREE} = $rc{GL_ADMIN_BASE};
    _chdir("$rc{GL_REPO_BASE}/gitolite-admin.git");
    _system("git add conf/gitolite.conf");
    _system("git add keydir") if $pubkey;
    tsh_try("git config --get user.email") or tsh_run( "git config user.email $ENV{USER}\@" . `hostname` );
    tsh_try("git config --get user.name")  or tsh_run( "git config user.name '$ENV{USER} on '" . `hostname` );
    tsh_try("git diff --cached --quiet")
      or tsh_try("git commit -am 'gl-setup $argv'")
      or die "setup failed to commit to the admin repo";
    delete $ENV{GIT_WORK_TREE};
}

1;

__DATA__
repo gitolite-admin
    RW+     =   %ADMIN

repo testing
    RW+     =   @all
