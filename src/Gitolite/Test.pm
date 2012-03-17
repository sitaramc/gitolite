package Gitolite::Test;

# functions for the test code to use
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
  try
  put
  text
  dump
  confreset
  confadd
  cmp
);
#>>>
use Exporter 'import';
use File::Path qw(mkpath);
use Carp qw(carp cluck croak confess);

use Gitolite::Common;

BEGIN {
    require Gitolite::Test::Tsh;
    *{'try'}  = \&Tsh::try;
    *{'put'}  = \&Tsh::put;
    *{'text'} = \&Tsh::text;
    *{'cmp'}  = \&Tsh::cmp;
}

use strict;
use warnings;

# ----------------------------------------------------------------------

# required preamble for all tests
try "
    DEF gsh = /TRACE: gsh.SOC=/
    DEF reject = /hook declined to update/; /remote rejected.*hook declined/; /error: failed to push some refs to/

    DEF AP_1 = cd ../gitolite-admin; ok or die cant find admin repo clone;
    DEF AP_2 = AP_1; git add conf ; ok; git commit -m %1; ok; /master.* %1/
    DEF ADMIN_PUSH = AP_2 %1; glt push admin origin; ok; gsh; /master -> master/

    DEF CS_1 = pwd; //tmp/tsh_tempdir.*gitolite-admin/; git remote -v; ok; /file://gitolite-admin/
    DEF CHECK_SETUP = CS_1; git log; ok; /6b18ec2ab0f765122ec133959b36c57f77d4565c/

    DEF CLONE = glt clone
    DEF PUSH  = glt push

    # clean install
    mkdir -p $ENV{HOME}/bin
    ln -sf $ENV{PWD}/src/gitolite $ENV{PWD}/t/glt ~/bin
    cd; rm -vrf .gito* gito* repositories
    git config --global user.name \"gitolite tester\"
    git config --global user.email \"tester\@example.com\"

    # setup
    gitolite setup -a admin

    # clone admin repo
    cd tsh_tempdir
    glt clone admin --progress file://gitolite-admin
    cd gitolite-admin
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
    chdir("../gitolite-admin") or die "in `pwd`, could not cd ../g-a";
    system( "rm", "-rf", "conf" );
    mkdir("conf");
    system("mv ~/repositories/gitolite-admin.git ~/repositories/.ga");
    system("mv ~/repositories/testing.git        ~/repositories/.te");
    system("find ~/repositories -name '*.git' |xargs rm -rf");
    system("mv ~/repositories/.ga ~/repositories/gitolite-admin.git");
    system("mv ~/repositories/.te ~/repositories/testing.git       ");
    put "conf/gitolite.conf", '
        repo    gitolite-admin
            RW+     =   admin
        repo    testing
            RW+     =   @all
';
}

sub confadd {
    chdir("../gitolite-admin") or die "in `pwd`, could not cd ../g-a";
    my ( $file, $string ) = _confargs(@_);
    put "|cat >> conf/$file", $string;
}

1;
