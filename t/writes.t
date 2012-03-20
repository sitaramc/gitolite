#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;
use Cwd;
my $workdir = getcwd();

# 'gitolite writes' command
# ----------------------------------------------------------------------

my $sf = ".gitolite.down";

try "plan 58";
try "DEF POK = !/DENIED/; !/failed to push/";

# delete the down file
unlink "$ENV{HOME}/$sf";

# add foo, bar/..* repos to the config and push
confreset;confadd '
    repo foo
        RW  =   u1
        R   =   u2

    repo bar/..*
        C   =   u2 u4 u6
        RW  =   CREATOR
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    # clone and push to foo
    CLONE u1 foo;               ok
    cd foo;                     ok
    tc f1;                      ok
    PUSH u1 master;             ok;     /new branch/

    # auto-clone and push to bar/u2
    cd ..
    CLONE u2 bar/u2;            ok;     /appear to have cloned an empty/
                                        /Initialized empty/
    cd u2;
    tc f2
    PUSH u2 master;             ok;

    # disable site with some message
    gitolite writes off \@all testing site-wide disable; ok

    # try push foo and see fail + message
    cd ../foo;                  ok
    tc f3;                      ok
    PUSH u1;                    !ok;    /testing site-wide disable/
    # try push bar/u2 and ...
    cd ../u2;                   ok
    tc f4;                      ok
    PUSH u2;                    !ok;    /testing site-wide disable/

    # try auto-create push bar/u4 and this works!!
    cd ..
    CLONE u4 bar/u4;            ok;     /appear to have cloned an empty/
                                        /Initialized empty/
                                        !/testing site-wide disable/
    cd u4;                      ok

    # enable site
    gitolite writes on \@all; ok

    # try same 3 again

    # try push foo and see fail + message
    cd ../foo;                  ok
    tc g3;                      ok
    PUSH u1;                    ok;    /master -> master/
    # try push bar/u2 and ...
    cd ../u2;                   ok
    tc g4;                      ok
    PUSH u2;                    ok;    /master -> master/

    # try auto-create push bar/u4 and this works!!
    cd ..
    CLONE u6 bar/u6;            ok;     /appear to have cloned an empty/
                                        /Initialized empty/
                                        !/testing site-wide disable/
    cd u6;                      ok

    # disable just foo
    gitolite writes off foo foo down

    # try push foo and see the message
    cd ../foo;                  ok
    tc g3;                      ok
    PUSH u1;                    !ok;    /foo down/
                                        !/testing site-wide disable/
    # push bar/u2 ok
    cd ../u2
    tc g4
    PUSH u2;                    ok;     /master -> master/

    # enable foo, disable bar/u2
    gitolite writes on foo
    gitolite writes off bar/u2 the bar is closed

    # try both
    cd ../foo;                  ok
    tc h3;                      ok
    PUSH u1;                    ok;     /master -> master/
    # push bar/u2 ok
    cd ../u2
    tc h4
    PUSH u2;                    !ok;    /the bar is closed/
";
