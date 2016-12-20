package Gitolite::Test;

# functions for the test code to use
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
  try
  put
  text
  lines
  dump
  confreset
  confadd
  cmp
  md5sum
);
#>>>
use Exporter 'import';
use File::Path qw(mkpath);
use Carp qw(carp cluck croak confess);
use Digest::MD5 qw(md5_hex);

use Gitolite::Rc;
use Gitolite::Common;

BEGIN {
    require Gitolite::Test::Tsh;
    *{'try'}   = \&Tsh::try;
    *{'put'}   = \&Tsh::put;
    *{'text'}  = \&Tsh::text;
    *{'lines'} = \&Tsh::lines;
    *{'cmp'}   = \&Tsh::cmp;
}

use strict;
use warnings;

# ----------------------------------------------------------------------

# make sure the user is ready for it
if ( not $ENV{GITOLITE_TEST} or $ENV{GITOLITE_TEST} ne 'y' ) {
    print "Bail out! See t/README for information on how to run the tests.\n";
    exit 255;
}

# required preamble for all tests
try "
    DEF gsh = /TRACE: gsh.SOC=/
    DEF reject = /hook declined to update/; /remote rejected.*hook declined/; /error: failed to push some refs to/

    DEF AP_1 = cd ../$rc{GL_ADMIN_REPO}; ok or die cant find admin repo clone;
    DEF AP_2 = AP_1; git add conf ; ok; git commit -m %1; ok; /master.* %1/
    DEF ADMIN_PUSH = AP_2 %1; glt push admin origin; ok; gsh; /master -> master/

    DEF CS_1 = pwd; //tmp/tsh_tempdir.*$rc{GL_ADMIN_REPO}/; git remote -v; ok; /file:///$rc{GL_ADMIN_REPO}/
    DEF CHECK_SETUP = CS_1; git log; ok; /fa7564c1b903ea3dce49314753f25b34b9e0cea0/

    DEF CLONE = glt clone %1 file:///%2
    DEF PUSH  = glt push %1 origin

    # clean install
    mkdir -p $ENV{HOME}/bin
    ln -sf $ENV{PWD}/t/glt ~/bin
    ./install -ln
    cd; rm -vrf .gito* repositories
    git config --file $ENV{HOME}/.gitconfig.local user.name \"gitolite tester\"
    git config --file $ENV{HOME}/.gitconfig.local user.email \"tester\@example.com\"
    git config --global                           include.path \"~/.gitconfig.local\"

    # setup
    gitolite setup -a admin

    # clone admin repo
    cd tsh_tempdir
    glt clone admin --progress file:///$rc{GL_ADMIN_REPO}
    cd $rc{GL_ADMIN_REPO}
" or die "could not setup the test environment; errors:\n\n" . text() . "\n\n";

sub dump {
    use Data::Dumper;
    for my $i (@_) {
        print STDERR "DBG: " . Dumper($i);
    }
}

sub _confargs {
    return @_ if ( $_[1] );
    return 'gitolite.conf', $_[0];
}

sub confreset {
    chdir("../$rc{GL_ADMIN_REPO}") or die "in `pwd`, could not cd ../g-a";
    system( "rm", "-rf", "conf" );
    mkdir("conf");
    system("mv ~/repositories/$rc{GL_ADMIN_REPO}.git ~/repositories/.ga");
    system("mv ~/repositories/testing.git        ~/repositories/.te");
    system("find ~/repositories -name '*.git' |xargs rm -rf");
    system("mv ~/repositories/.ga ~/repositories/$rc{GL_ADMIN_REPO}.git");
    system("mv ~/repositories/.te ~/repositories/testing.git       ");
    put "|cut -c9- > conf/gitolite.conf", '
        repo    $rc{GL_ADMIN_REPO}
            RW+     =   admin
        repo    testing
            RW+     =   @all
';
}

sub confadd {
    chdir("../$rc{GL_ADMIN_REPO}") or die "in `pwd`, could not cd ../g-a";
    my ( $file, $string ) = _confargs(@_);
    put "|cat >> conf/$file", $string;
}

sub md5sum {
    my $out = '';
    for my $file (@_) {
        $out .= md5_hex( slurp($file) ) . "  $file\n";
    }
    return $out;
}

1;
