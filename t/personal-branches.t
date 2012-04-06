#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# personal branches
# ----------------------------------------------------------------------

try "plan 64";

confreset;confadd '
    @admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    repo testing
        RW+     =   @all

    @g1 = t1
    repo @g1
        R               =   u2
        RW              =   u3
        RW+             =   u4
        RW  a/USER/     =   @all
        RW+ p/USER/     =   u1 u6
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "

    gitolite access t1 u1;                              ok;     /refs/heads/p/u1//; !/DENIED/
    gitolite access t1 u5;                              !ok;    /\\+ any t1 u5 DENIED by fallthru/
    gitolite access \@g1 u5 W;                          ok;     /refs/heads/a/u5//; !/DENIED/

    gitolite access t1 u1 W refs/heads/a/user1/foo;     !ok;    /W refs/heads/a/user1/foo t1 u1 DENIED by fallthru/
    gitolite access \@g1 u1 + refs/heads/a/user1/foo;   !ok;    /\\+ refs/heads/a/user1/foo \@g1 u1 DENIED by fallthru/
    gitolite access t1 u1 W refs/heads/p/user1/foo;     !ok;    /W refs/heads/p/user1/foo t1 u1 DENIED by fallthru/
    gitolite access \@g1 u1 + refs/heads/p/user1/foo;   !ok;    /\\+ refs/heads/p/user1/foo \@g1 u1 DENIED by fallthru/

    gitolite access \@g1 u1 W refs/heads/a/u1/foo;      ok;     /refs/heads/a/u1//; !/DENIED/
    gitolite access t1 u1 + refs/heads/a/u1/foo;        !ok;    /\\+ refs/heads/a/u1/foo t1 u1 DENIED by fallthru/
    gitolite access \@g1 u1 W refs/heads/p/u1/foo;      ok;     /refs/heads/p/u1//; !/DENIED/
    gitolite access t1 u1 + refs/heads/p/u1/foo;        ok;     /refs/heads/p/u1//; !/DENIED/

    gitolite access \@g1 u1 W refs/heads/p/u2/foo;      !ok;    /W refs/heads/p/u2/foo \@g1 u1 DENIED by fallthru/
    gitolite access t1 u1 + refs/heads/p/u2/foo;        !ok;    /\\+ refs/heads/p/u2/foo t1 u1 DENIED by fallthru/
";

confreset; confadd '
    @staff = u1 u2 u3 u4 u5 u6
    @gfoo = foo
    repo  @gfoo
          RW+                       = u1 u2
          RW+   p/USER/             = u3 u4
          RW    temp                = u5 u6
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    DEF OK  =   gitolite access foo %1 %2 refs/heads/%3;    ok
    DEF NOK =   gitolite access foo %1 %2 refs/heads/%3;    !ok
";

try "

# u1 and u2 can push
    OK  u1  W   master
    OK  u2  W   master
    OK  u2  W   p/u1/foo
    OK  u1  W   p/u2/foo
    OK  u1  W   p/u3/foo

# u3 cant push u1/u4 personal branches
    NOK u3  W   p/u1/foo
    NOK u3  W   p/u4/doo

# u4 can push u4 personal branch
    OK  u4  W   p/u4/foo
# u5 push temp
    OK  u5  W   temp

# u1 and u2 can rewind
    OK  u1  +   master
    OK  u2  +   p/u1/foo
    OK  u1  +   p/u2/foo
    OK  u1  +   p/u3/foo

# u3 cant rewind u1/u4 personal branches
    NOK u3  +   p/u1/foo
    NOK u3  +   p/u4/foo
# u4 can rewind u4 personal branch
    OK  u4  +   p/u4/foo
# u5 cant rewind temp
    NOK u5  +   temp
";
