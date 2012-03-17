#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Common;
use Gitolite::Test;

my $bd = `gitolite query-rc -n GL_BINDIR`;
my $h  = $ENV{HOME};
my $ab = `gitolite query-rc -n GL_ADMIN_BASE`;
umask 0077;

try "
    plan 26

    # reset stuff
    rm -f $h/.ssh/authorized_keys;          ok or die 1

    cp $bd/../t/keys/u[1-6]* $h/.ssh;       ok or die 2
    cp $bd/../t/keys/admin*  $h/.ssh;       ok or die 3
    cp $bd/../t/keys/config  $h/.ssh;       ok or die 4

    mkdir                  $ab/keydir;      ok or die 5
    cp $bd/../t/keys/*.pub $ab/keydir;      ok or die 6
";

system("gitolite post-compile/ssh-authkeys");

# basic tests
# ----------------------------------------------------------------------

confreset; confadd '
    @g1 = u1
    @g2 = u2
    repo foo
        RW = @g1 u3
        R  = @g2 u4
';

try "ADMIN_PUSH set3; !/FATAL/" or die text();

try "
    ssh u1 info;                ok;     /R W  \tfoo/
    ssh u2 info;                ok;     /R    \tfoo/
    ssh u3 info;                ok;     /R W  \tfoo/
    ssh u4 info;                ok;     /R    \tfoo/
    ssh u5 info;                ok;     !/foo/
    ssh u6 info;                ok;     !/foo/
"
