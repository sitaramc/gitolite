#!/usr/bin/perl
use strict;
use warnings;

# the commit message in which this test is introduced should have details, but
# briefly, this test makes sure that access() does not get confused by
# repo-create permissions being allowed, when looking for branch-create
# permissions.

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# branch permissions test
# ----------------------------------------------------------------------

try "plan 25";

confreset;confadd '
    repo foo/..*
        C       =   @all
        RW+CD   =   CREATOR
        RW      =   u2

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..;                          ok
    glt clone u1 file:///foo/aa;    ok
    cd aa;                          ok
    tc l-1;                         ok;     /master/
    glt push u1 origin master:m1;   ok;     /To file:///foo/aa/
                                            /\\* \\[new branch\\]      master -> m1/

    tc l-2;                         ok;     /master/
    glt push u2 origin master:m2;   !ok;    /FATAL: C/
                                            /DENIED by fallthru/
    glt push u2 origin master:m1;   ok;     /To file:///foo/aa/
                                            /8cd302a..29b8683/
                                            /master -> m1/
";
