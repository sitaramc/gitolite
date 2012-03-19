#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

# the info command
# ----------------------------------------------------------------------

try 'plan 83';

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
';

try "ADMIN_PUSH info; !/FATAL/" or die text();
try "
                                        /Initialized.*empty.*t1.git/
                                        /Initialized.*empty.*t2.git/
                                        /Initialized.*empty.*t3.git/
";

# GS == greeting string
try "DEF GS = /hello %1, this is gitolite/";

try "
    glt info u1; ok; GS u1
        /R W  \t\@t1/
        /R    \tt2/
        /R W  \ttesting/
        !/R W  \tt3/
    glt info u2; ok; GS u2
        /R    \t\@t1/
        /R W  \tt2/
        /R W  \ttesting/
        !/R W  \tt3/
    glt info u3; ok; GS u3
        /R W  \tt3/
        /R W  \ttesting/
        !/R    \t\@t1/
        !/R W  \tt2/
    glt info u4; ok; GS u4
        /R    \tt3/
        /R W  \ttesting/
        !/R    \t\@t1/
        !/R W  \tt2/
    glt info u5; ok; GS u5
        /R W  \ttesting/
        !/R    \t\@t1/
        !/R W  \tt2/
        !/R W  \tt3/
    glt info u6; ok; GS u6
        /R W  \ttesting/
        !/R    \t\@t1/
        !/R W  \tt2/
        !/R W  \tt3/
";

try "
    glt info u1 -p; ok; GS u1
        /R W  \tt1/
        /R    \tt2/
        /R W  \ttesting/
        !/R W  \tt3/
    glt info u2 -p; ok; GS u2
        /R    \tt1/
        /R W  \tt2/
        /R W  \ttesting/
        !/R W  \tt3/
    glt info u3 -p; ok; GS u3
        /R W  \tt3/
        /R W  \ttesting/
        !/R    \tt1/
        !/R W  \tt2/
    glt info u4 -p; ok; GS u4
        /R    \tt3/
        /R W  \ttesting/
        !/R    \tt1/
        !/R W  \tt2/
    glt info u5 -p; ok; GS u5
        /R W  \ttesting/
        !/R    \tt1/
        !/R W  \tt2/
        !/R W  \tt3/
    glt info u6 -p; ok; GS u6
        /R W  \ttesting/
        !/R    \tt1/
        !/R W  \tt2/
        !/R W  \tt3/
";
