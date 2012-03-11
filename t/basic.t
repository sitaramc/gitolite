#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

# basic tests
# ----------------------------------------------------------------------

try "
    plan 218
    CHECK_SETUP

    ## subtest 1
    cd ..
    CLONE dev2 file://gitolite-admin ga2
                                !ok;    gsh
                                        /DENIED by fallthru/
                                        /fatal: The remote end hung up unexpectedly/
    CLONE admin --progress file://gitolite-admin ga2
                                ok;     gsh
                                        /Counting/; /Compressing/; /Total/
    cd gitolite-admin;          ok
    ";

put "conf/gitolite.conf", "
    \@admins     =   admin dev1
    repo gitolite-admin
        -   mm  =   \@admins
        RW      =   \@admins
        RW+     =   admin

    repo testing
        RW+     =   \@all
";

try "
    # push
    git add conf;               ok
    git status -s;              ok;     /M  conf/gitolite.conf/
    git commit -m t01a;         ok;     /master.*t01a/
    PUSH dev2 origin;           !ok;    gsh
                                        /DENIED by fallthru/
                                        /fatal: The remote end hung up unexpectedly/
    PUSH admin origin;          ok;     /master -> master/
    tsh empty;                  ok;
    PUSH admin origin master:mm
                                !ok;    gsh
                                        /DENIED by refs/heads/mm/
                                        reject
    ";

put "conf/gitolite.conf", "
    \@admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    repo testing
        RW+     =   \@all

    repo t1
        R       =   u2
        RW      =   u3
        RW+     =   u4
";

try "
    ## subtest 2
    ADMIN_PUSH t01b

    # clone
    cd ..;                      ok;
    CLONE u1 file://t1;         !ok;    gsh
                                        /DENIED by fallthru/
                                        /fatal: The remote end hung up unexpectedly/
    CLONE u2 file://t1;         ok;     gsh
                                        /warning: You appear to have cloned an empty repository./
    ls -al t1;                  ok;     /$ENV{USER}.*$ENV{USER}.*\.git/
    cd t1;                      ok;

    # push
    test-commit tc1 tc2 tc2;    ok;     /f7153e3/
    PUSH u2 origin;             !ok;    gsh
                                        /DENIED by fallthru/
                                        /fatal: The remote end hung up unexpectedly/
    PUSH u3 origin master;      ok;     gsh
                                        /master -> master/

    # rewind
    reset-h HEAD^;              ok;     /HEAD is now at 537f964 tc2/
    test-tick; test-commit tc3; ok;     /a691552/
    PUSH u3 origin;             !ok;    gsh
                                        /rejected.*master -> master.*non-fast-forward./
    PUSH u3 -f origin;          !ok;    gsh
                                        reject
                                        /DENIED by fallthru/
    PUSH u4 origin +master;     ok;     gsh
                                        / \\+ f7153e3...a691552 master -> master.*forced update./
";

put "../gitolite-admin/conf/gitolite.conf", "
    \@admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    include 'i1.conf'
";

put "../gitolite-admin/conf/i1.conf", "
    \@g1 = u1
    \@g2 = u2
    \@g3 = u3
    \@gaa = aa
    repo \@gaa
        RW+                 =   \@g1
        RW                  =   \@g2
        RW+     master      =   \@g3
        RW      master      =   u4
        -       master      =   u5
        RW+     dev         =   u5
        RW                  =   u5
";

try "
    ## subtest 3
    ADMIN_PUSH t01c

    cd ..;                      ok
";

try "
    CLONE u1 file://aa;         ok;     gsh
    cd aa;                      ok
    test-commit set3 t1 t2 t3 t4 t5 t6 t7 t8 t9
                                ok
    PUSH u1 origin HEAD;        ok;     gsh
                                        /To file://aa/
                                        /\\* \\[new branch\\]      HEAD -> master/
    branch dev;                 ok
    branch foo;                 ok

    # u1 rewind master ok
    reset-h HEAD^;              ok
    test-commit r1;             ok
    PUSH u1 origin +master;     ok;     gsh
                                        /To file://aa/
                                        /\\+ cecf671...70469f5 master -> master .forced update./

    # u2 rewind master !ok
    reset-h HEAD^;              ok
    test-commit r2;             ok
    PUSH u2 origin +master;     !ok;    gsh
                                        reject
                                        /DENIED by fallthru/

    # u3 rewind master ok
    reset-h HEAD^;              ok
    test-commit r3;             ok
    PUSH u3 origin +master;     ok;     gsh
                                        /To file://aa/
                                        /\\+ 70469f5...f1e6821 master -> master .forced update./

    # u4 push master ok
    test-commit u4;             ok
    PUSH u4 origin master;      ok;     gsh
                                        /To file://aa/
                                        /f1e6821..d308cfb +master -> master/

    # u4 rewind master !ok
    reset-h HEAD^;              ok
    PUSH u4 origin +master;     !ok;    gsh
                                        reject
                                        /DENIED by fallthru/

    # u3,u4 push other branches !ok
    PUSH u3 origin dev;         !ok;    gsh
                                        reject
                                        /DENIED by fallthru/
    PUSH u4 origin dev;         !ok;    gsh
                                        reject
                                        /DENIED by fallthru/
    PUSH u3 origin foo;         !ok;    gsh
                                        reject
                                        /DENIED by fallthru/
    PUSH u4 origin foo;         !ok;    gsh
                                        reject
                                        /DENIED by fallthru/

    # clean up for next set
    PUSH u1 -f origin master dev foo
                                ok;     gsh
                                        /d308cfb...f1e6821 master -> master .forced update./
                                        /new branch.*dev -> dev/
                                        /new branch.*foo -> foo/

    # u5 push master !ok
    test-commit u5
    PUSH u5 origin master;      !ok;    gsh
                                        reject
                                        /DENIED by refs/heads/master/

    # u5 rewind dev ok
    PUSH u5 origin +dev^:dev
                                ok;     gsh
                                        /\\+ cecf671...5c8a89d dev\\^ -> dev .forced update./


    # u5 rewind foo !ok
    PUSH u5 origin +foo^:foo
                                !ok;    gsh
                                        reject
                                        /remote: FATAL: \\+ refs/heads/foo aa u5 DENIED by fallthru/

    # u5 push foo ok
    git checkout foo
    /Switched to branch 'foo'/

    test-commit u5
    PUSH u5 origin foo;         ok;     gsh
                                        /cecf671..b27cf19 *foo -> foo/

    # u1 delete dev ok
    PUSH u1 origin :dev;        ok;     gsh
                                        / - \\[deleted\\] *dev/

    # push it back
    PUSH u1 origin dev;         ok;     gsh
                                        /\\* \\[new branch\\] *dev -> dev/

";

put "| cat >> ../gitolite-admin/conf/gitolite.conf", "
    \@gr1 = r1
    repo \@gr1
        RW  refs/heads/v[0-9]   = u1
        RW  refs/heads          = tester
";

try "
    ## subtest 4
    ADMIN_PUSH t01d

    cd ..;                      ok

    CLONE tester file://r1;     ok;     gsh
                                        /Cloning into 'r1'.../
    cd r1;                      ok
    test-commit r1a r1b r1c r1d r1e r1f
                                ok
    PUSH tester origin HEAD;    ok;     gsh
                                        /\\* \\[new branch\\] *HEAD -> master/
    git branch v1
    PUSH tester origin v1;      ok;     gsh
                                        /\\* \\[new branch\\] *v1 -> v1/

";

put "| cat >> ../gitolite-admin/conf/gitolite.conf", "
    \@gr2 = r2
    repo \@gr2
        RW  refs/heads/v[0-9]   = u1
        -   refs/heads/v[0-9]   = tester
        RW  refs/heads          = tester
";

try "
    ## subtest 5
    ADMIN_PUSH t01e

    cd ..;                      ok

    CLONE tester file://r2;     ok;     gsh
                                        /Cloning into 'r2'.../
    cd r2;                      ok
    test-commit r2a r2b r2c r2d r2e r2f
                                ok
    PUSH tester origin HEAD;    ok;     gsh
                                        /\\* \\[new branch\\] *HEAD -> master/
    git branch v1
    PUSH tester origin v1;      !ok;    gsh
                                        /W refs/heads/v1 r2 tester DENIED by refs/heads/v\\[0-9\\]/
"
