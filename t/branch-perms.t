#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# branch permissions test
# ----------------------------------------------------------------------

try "plan 82";

confreset;confadd '
    @g1 = u1
    @g2 = u2
    @g3 = u3
    @gaa = aa
    repo @gaa
        RW+                 =   @g1
        RW                  =   @g2
        RW+     master      =   @g3
        RW      master      =   u4
        -       master      =   u5
        RW+     dev         =   u5
        RW                  =   u5

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..;                          ok
    glt clone u1 file:///aa;         ok
    cd aa;                          ok
    tc l-995 l-996 l-997 l-998 l-999 l-1000 l-1001 l-1002 l-1003;
                                    ok;     /master ........ l-1003/
    glt push u1 origin HEAD;        ok;     /To file:///aa/
                                            /\\* \\[new branch\\]      HEAD -> master/

    git branch dev;                 ok
    git branch foo;                 ok

    # u1 rewind master succeed
    git reset --hard HEAD^;         ok;     /HEAD is now at ....... l-1002/
    tc v-865;                       ok;     /master ........ v-865/
    glt push u1 origin +master;     ok;     /\\+ ................. master -> master \\(forced update\\)/

    # u2 rewind master fail
    git reset --hard HEAD^;         ok;     /HEAD is now at ....... l-1002/
    tc s-361;                       ok;     /master ........ s-361/
    glt push u2 file:///aa +master;  !ok;    reject
                                            /\\+ refs/heads/master aa u2 DENIED by fallthru/

    # u3 rewind master succeed
    git reset --hard HEAD^;         ok
    tc m-508;                       ok
    glt push u3 file:///aa +master;  ok;     /\\+ .* master -> master \\(forced update\\)/

    # u4 push master succeed
    tc f-526;                       ok;
    glt push u4 file:///aa master;   ok;     /master -> master/

    # u4 rewind master fail
    git reset --hard HEAD^;         ok;
    glt push u4 file:///aa +master;  !ok;    /\\+ refs/heads/master aa u4 DENIED by fallthru/

    # u3 and u4 / dev foo -- all 4 fail
    glt push u3 file:///aa dev;      !ok;    /W refs/heads/dev aa u3 DENIED by fallthru/
    glt push u4 file:///aa dev;      !ok;    /W refs/heads/dev aa u4 DENIED by fallthru/
    glt push u3 file:///aa foo;      !ok;    /W refs/heads/foo aa u3 DENIED by fallthru/
    glt push u4 file:///aa foo;      !ok;    /W refs/heads/foo aa u4 DENIED by fallthru/

    # clean up for next set
    glt push u1 -f origin master dev foo
                                    ok

    # u5 push master fail
    tc l-417;                       ok
    glt push u5 file:///aa master;   !ok;    /W refs/heads/master aa u5 DENIED by refs/heads/master/

    # u5 rewind dev succeed
    glt push u5 file:///aa +dev^:dev
                                    ok;     /\\+ .* dev\\^ -> dev \\(forced update\\)/

    # u5 rewind foo fail
    glt push u5 file:///aa +foo^:foo
                                    !ok;    /\\+ refs/heads/foo aa u5 DENIED by fallthru/

    # u5 tries to push foo; succeeds
    git checkout foo;               ok;     /Switched to branch 'foo'/

    # u5 push foo succeed
    tc e-530;                       ok;
    glt push u5 file:///aa foo;      ok;     /foo -> foo/

    # u1 delete branch dev succeed
    glt push u1 origin :dev;        ok;     / - \\[deleted\\] *dev/

    # quietly push it back again
    glt push u1 origin dev;         ok;     / * \\[new branch\\]      dev -> dev/

    ";

    confadd '
        repo @gaa
            RWD     dev         =   u4
    ';

try "ADMIN_PUSH set2; !/FATAL/" or die text();

try "
    # u1 tries to delete dev on a new setup
    cd ../aa;                       ok;     /master -> master/

    # u1 delete branch dev fail
    glt push u1 origin :dev;        !ok;    /D refs/heads/dev aa u1 DENIED by fallthru/

    # u4 delete branch dev succeed
    glt push u4 file:///aa :dev;     ok;     / - \\[deleted\\] *dev/

";
