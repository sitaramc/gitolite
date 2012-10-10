#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# assigning roles to groups instead of users
# ----------------------------------------------------------------------

try "plan 31";

try "DEF POK = !/DENIED/; !/failed to push/";

confreset; confadd '
    @leads = u1 u2
    @devs = u1 u2 u3 u4

    @gbar = bar/CREATOR/..*
    repo    @gbar
        C               =   @leads
        RW+             =   CREATOR
        RW              =   WRITERS
        R               =   READERS
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "

    # u1 auto-creates a repo
    glt ls-remote u1 file:///bar/u1/try1
        /Initialized empty Git repository in .*/bar/u1/try1.git//
    # default permissions for u2 and u4
    glt info u1 -lc
        /R W *\tbar/u1/try1\tu1/
    glt info u2 -lc
        !/R W *\tbar/u1/try1\tu1/
    glt info u4 -lc
        !/R W *\tbar/u1/try1\tu1/

    # \@leads can RW try1
    echo WRITERS \@leads | glt perms u1 bar/u1/try1; ok
    glt info u1 -lc
        /R W *\tbar/u1/try1\tu1/
    glt info u2 -lc
        /R W *\tbar/u1/try1\tu1/
    glt info u4 -lc
        !/R W *\tbar/u1/try1\tu1/

    # \@devs can R try1
    echo READERS \@devs | glt perms u1 bar/u1/try1; ok
    glt perms u1 -l bar/u1/try1
        /READERS \@devs/
        !/WRITERS \@leads/

    glt info u1 -lc
        /R W *\tbar/u1/try1\tu1/

    glt info u2 -lc
        !/R W *\tbar/u1/try1\tu1/
        /R *\tbar/u1/try1\tu1/

    glt info u4 -lc
        !/R W *\tbar/u1/try1\tu1/
        /R *\tbar/u1/try1\tu1/

# combo of previous 2
    /usr/bin/printf 'READERS \@devs\\nWRITERS \@leads\\n' | glt perms u1 bar/u1/try1; ok
    glt perms u1 -l bar/u1/try1
        /READERS \@devs/
        /WRITERS \@leads/
    glt info u1 -lc
        /R W *\tbar/u1/try1\tu1/
    glt info u2 -lc
        /R W *\tbar/u1/try1\tu1/
    glt info u4 -lc
        !/R W *\tbar/u1/try1\tu1/
        /R *\tbar/u1/try1\tu1/
";
