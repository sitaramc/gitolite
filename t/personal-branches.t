#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

# basic tests
# ----------------------------------------------------------------------

try "plan 39";

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
