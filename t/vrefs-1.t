#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# VREFs - part 1
# ----------------------------------------------------------------------

try "plan 88";

put "conf/gitolite.conf", "
    repo gitolite-admin
        RW+     =   admin

    \@gfoo = foo
    \@lead = u1
    \@dev2 = u2
    \@dev4 = u4
    \@devs = \@dev2 \@dev4 u6
    repo  \@gfoo
          RW+                   =   \@lead \@devs
          # intentional mis-spelling
          -     VREF/MISCOUNT/2    =   \@dev2
          -     VREF/MISCOUNT/4    =   \@dev4
          -     VREF/MISCOUNT/3/NEWFILES   =   u6
          -     VREF/MISCOUNT/6            =   u6
";

try "
    ADMIN_PUSH vr1a
    cd ..
    [ -d foo ];                 !ok
    CLONE u1 foo;               ok;     /Cloning into/
                                        /You appear to have cloned an empty/
    cd foo;                     ok
    [ -d .git ];                ok

    # VREF not called for u1
    tc a1 a2 a3 a4 a5;          ok;     /aaf9e8e/
    PUSH u1 master;             ok;     /new branch.*master -. master/
                                        !/helper program missing/
                                        !/hook declined/
                                        !/remote rejected/
    # VREF is called for u2
    tc b1;                      ok;     /1f440d3/
    PUSH u2;                    !ok;    /helper program missing/
                                        /hook declined/
                                        /remote rejected/
";

put "../gitolite-admin/conf/gitolite.conf", "
    repo gitolite-admin
        RW+     =   admin

    \@gfoo = foo
    \@lead = u1
    \@dev2 = u2
    \@dev4 = u4
    \@devs = \@dev2 \@dev4 u6
    repo  \@gfoo
          RW+                   =   \@lead \@devs
          -     VREF/COUNT/2    =   \@dev2
          -     VREF/COUNT/4    =   \@dev4
          -     VREF/COUNT/3/NEWFILES   =   u6
          -     VREF/COUNT/6            =   u6
";

try "
    ADMIN_PUSH vr1b
    cd ../foo;                  ok

    # u2 1 file
    PUSH u2;                    ok;     /aaf9e8e..1f440d3.*master -. master/

    # u2 2 files
    tc b2 b3;                   ok;     /c3397f7/
    PUSH u2;                    ok;     /1f440d3..c3397f7.*master -. master/

    # u2 3 files
    tc c1 c2 c3;                ok;     /be242d7/
    PUSH u2;                    !ok;    /W VREF/COUNT/2 foo u2 DENIED by VREF/COUNT/2/
                                        /too many changed files in this push/
                                        /hook declined/
                                        /remote rejected/

    # u4 3 files
    PUSH u4;                    ok;     /c3397f7..be242d7.*master -. master/

    # u4 4 files
    tc d1 d2 d3 d4;             ok;     /88d80e2/
    PUSH u4;                    ok;     /be242d7..88d80e2.*master -. master/

    # u4 5 files
    tc d5 d6 d7 d8 d9;          ok;     /e9c60b0/
    PUSH u4;                    !ok;    /W VREF/COUNT/4 foo u4 DENIED by VREF/COUNT/4/
                                        /too many changed files in this push/
                                        /hook declined/
                                        /remote rejected/

    # u1 all files
    PUSH u1;                    ok;     /88d80e2..e9c60b0.*master -. master/

    # u6 6 old files
    test-tick
    tc d1 d2 d3 d4 d5 d6
                                ok;     /2773f0a/
    PUSH u6;                    ok;     /e9c60b0..2773f0a.*master -. master/
    tag six

    # u6 updates 7 old files
    test-tick; test-tick
    tc d1 d2 d3 d4 d5 d6 d7
                                ok;     /d3fb574/
    PUSH u6;                    !ok;    /W VREF/COUNT/6 foo u6 DENIED by VREF/COUNT/6/
                                        /too many changed files in this push/
                                        /hook declined/
                                        /remote rejected/
    reset-h six;                ok;     /HEAD is now at 2773f0a/

    # u6 4 new 2 old files
    test-tick; test-tick
    tc d1 d2 n1 n2 n3 n4
                                ok;     /9e90848/
    PUSH u6;                    !ok;    /W VREF/COUNT/3/NEWFILES foo u6 DENIED by VREF/COUNT/3/NEWFILES/
                                        /too many new files in this push/
                                        /hook declined/
                                        /remote rejected/
    reset-h six;                ok;     /HEAD is now at 2773f0a/

    # u6 3 new 3 old files
    test-tick; test-tick
    tc d1 d2 d3 n1 n2 n3
                                ok;     /e47ff5d/
    PUSH u6;                    ok;     /2773f0a..e47ff5d.*master -. master/
";
