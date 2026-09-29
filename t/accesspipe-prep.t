#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# test 'gitolite access'
# ----------------------------------------------------------------------

try "plan 32";

confreset;confadd '
    @admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

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

confadd '
    @admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    @gr1 = r1
    repo @gr1
        RW  refs/heads/v[0-9]   = u1
        RW  refs/heads          = tester

    @gr2 = r2
    repo @gr2
        RW  refs/heads/v[0-9]   = u1
        -   refs/heads/v[0-9]   = tester
        RW  refs/heads          = tester
';

try "ADMIN_PUSH set2; !/FATAL/" or die text();

confadd '
    repo @all
        R   =   gitweb

    repo c0
        RW+ =   @all
    repo c1
        RWC =   u1
        RW+ =   @all
';

try "ADMIN_PUSH set3; !/FATAL/" or die text();

confadd '
    repo foo
        R   =   u1
        RW  =   u2
        RW+ =   u3

    repo bar
        R   =   u1
        RW  =   u2
        RW+ =   u3
        RW+CDM  =   u6

';

try "ADMIN_PUSH set4; !/FATAL/" or die text();
