package Gitolite::Setup;

# implements 'gitolite setup'
# ----------------------------------------------------------------------

=for usage
Usage:  gitolite setup [<at least one option>]


    -a, --admin <name>          admin user name
    -pk --pubkey <file>         pubkey file name
    -f, --fixup-hooks           fixup hooks

First run:
    -a      required
    -pk     required for ssh mode install

Later runs:
    no options required; but '-f' can be specified for clarity
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
    # first time
    if ( first_run() ) {
        trace( 1, "..should happen only on first run" );
        setup_glrc();
        setup_gladmin( $admin, $pubkey, $argv );
    }

    _system("$ENV{GL_BINDIR}/gitolite compile");
    _system("$ENV{GL_BINDIR}/gitolite post-compile ssh-authkeys") if $pubkey;

    hook_repos();    # all of them, just to be sure
}

# ----------------------------------------------------------------------

sub first_run {
    # if the rc file could not be found, it's *definitely* a first run!
    return not glrc('filename');
}

sub args {
    my $admin  = '';
    my $pubkey = '';
    my $fixup  = 0;
    my $help   = 0;
    my $argv   = join( " ", @ARGV );

    GetOptions(
        'admin|a=s'     => \$admin,
        'pubkey|pk=s'   => \$pubkey,
        'fixup-hooks|f' => \$fixup,
        'help|h'        => \$help,
    ) or usage();

    usage() if $help;
    usage("first run requires '-a'")     if first_run() and not($admin);
    _warn("not setting up ssh...")       if first_run() and $admin and not $pubkey;
    _warn("first run, ignoring '-f'...") if first_run() and $fixup;
    _warn("not first run, ignoring '-a' / '-pk'...") if not first_run() and ( $admin or $pubkey );

    if ($pubkey) {
        $pubkey =~ /\.pub$/ or _die "$pubkey name does not end in .pub";
        tsh_try("cat $pubkey")              or _die "$pubkey not a readable file";
        tsh_lines() == 1                    or _die "$pubkey must have exactly one line";
        tsh_try("ssh-keygen -l -f $pubkey") or _die "$pubkey does not seem to be a valid ssh pubkey file";
    }

    return ( $admin || '', $pubkey || '', $argv );
}

sub setup_glrc {
    trace(1);
    _print( glrc('default-filename'), glrc('default-text') );
}

sub setup_gladmin {
    my ( $admin, $pubkey, $argv ) = @_;
    trace( 1, $admin );

    # reminder: 'admin files' are in ~/.gitolite, 'admin repo' is
    # $rc{GL_REPO_BASE}/gitolite-admin.git

    # grab the pubkey content before we chdir() away

    my $pubkey_content = '';
    if ($pubkey) {
        $pubkey_content = slurp($pubkey);
        $pubkey =~ s(.*/)();    # basename
    }

    # set up the admin files in admin-base

    _mkdir( $rc{GL_ADMIN_BASE} );
    _chdir( $rc{GL_ADMIN_BASE} );

    _mkdir("conf");
    my $conf;
    {
        local $/ = undef;
        $conf = <DATA>;
    }
    $conf =~ s/%ADMIN/$admin/g;

    _print( "conf/gitolite.conf", $conf );

    if ($pubkey) {
        _mkdir("keydir");
        _print( "keydir/$pubkey", $pubkey_content );
    }

    # set up the admin repo in repo-base

    _chdir();
    _mkdir( $rc{GL_REPO_BASE} );
    _chdir( $rc{GL_REPO_BASE} );

    new_repo("gitolite-admin");

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
