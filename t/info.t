#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# the info command
# ----------------------------------------------------------------------

try 'plan 78';

try "## info";

confreset;confadd '
    @t1 = t1
    repo    @t1
        RW              =   u1
        R               =   u2
    repo    t2
        RW  =               u2
        R   =               u1
    repo    t3
        RW  =   u3
        R   =   u4

    repo foo/..*
        C   =   u1
        RW  =   CREATOR u3
';

try "ADMIN_PUSH info; !/FATAL/" or die text();
try "
                                        /Initialized.*empty.*t1.git/
                                        /Initialized.*empty.*t2.git/
                                        /Initialized.*empty.*t3.git/
";

# GS == greeting string
try "DEF GS = /hello %1, this is $ENV{USER}\\@.* running gitolite/";

try "
    glt info u1; ok; GS u1
        /C\tfoo/\\.\\.\\*/
        /R W *\tt1/
        /R   *\tt2/
        /R W *\ttesting/
        !/R W *\tt3/
    glt info u2; ok; GS u2
        !/C\tfoo/
        /R   *\tt1/
        /R W *\tt2/
        /R W *\ttesting/
        !/R W *\tt3/
    glt info u3; ok; GS u3
        /R W *\tt3/
        /R W *\ttesting/
        !/R   *\tt1/
        !/R W *\tt2/
    glt info u4; ok; GS u4
        /R   *\tt3/
        /R W *\ttesting/
        !/R   *\tt1/
        !/R W *\tt2/
    glt info u5; ok; GS u5
        /R W *\ttesting/
        !/R   *\tt1/
        !/R W *\tt2/
        !/R W *\tt3/
    glt info u6; ok; GS u6
        /R W *\ttesting/
        !/R   *\tt1/
        !/R W *\tt2/
        !/R W *\tt3/
";

try "
    glt ls-remote u1 file:///foo/one;   ok
    glt info u1; ok; GS u1
        /C\tfoo/\\.\\.\\*/
        /R W *\tfoo/one/
        !/R W *\tfoo/one\tu1/
    glt info u2; ok; GS u2
        !/C\tfoo/
        !/R W *\tfoo/one/
    glt info u3; ok; GS u3
        !/C\tfoo/
        /R W *\tfoo/one/
        !/R W *\tfoo/one\tu1/
";

try "
    glt ls-remote u1 file:///foo/one;   ok
    glt info u1 -lc; ok; GS u1
        /C\tfoo/\\.\\.\\*/
        !/C\tfoo.*u1/
        /R W *\tfoo/one\tu1/
    glt info u2 -lc; ok; GS u2
        !/C\tfoo/
        !/R W *\tfoo/one/
    glt info u3 -lc; ok; GS u3
        !/C\tfoo/
        /R W *\tfoo/one\tu1/
";
