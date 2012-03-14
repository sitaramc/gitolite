#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

try 'plan 35';

try "## info";

confreset;confadd '
    repo    t1
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
try "
    glt info u1;                ok;     gsh
                                        /R W  *\tt1/
                                        /R  *\tt2/
                                        !/t3/
                                        / R W  *\ttesting/
    glt info u2;                ok;     gsh
                                        /R  *\tt1/
                                        /R W  *\tt2/
                                        !/t3/
                                        / R W  *\ttesting/
    glt info u3;                ok;     gsh
                                        /R W  *\tt3/
                                        !/t1/
                                        !/t2/
                                        / R W  *\ttesting/
    glt info u4;                ok;     gsh
                                        /R  *\tt3/
                                        !/t1/
                                        !/t2/
                                        / R W  *\ttesting/
    " or die;
