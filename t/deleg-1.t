#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# delegation tests -- part 1
# ----------------------------------------------------------------------

try "plan 54";

try "
    DEF SP_1 = git add conf ; ok; git commit -m %1; ok; /master.* %1/
    DEF SUBCONF_PUSH = SP_1 %2; glt push %1 origin; gsh; /master -> master/
";

confreset;confadd '
    @u1r    =   r1a r1b
    @u2r    =   r2a r2b
    @u3r    =   r3a r3b

    # the admin repo access was probably like this to start with:
    repo gitolite-admin
        RW                              = u1 u2 u3
        RW+ NAME/                       = admin
        RW  NAME/conf/fragments/u1r     = u1
        RW  NAME/conf/fragments/u2r     = u2
        RW  NAME/conf/fragments/u3r     = u3
        -   NAME/                       = @all

        subconf "fragments/*.conf"
';
try "ADMIN_PUSH set1; !/FATAL/" or die text();

mkdir "conf/fragments";
put   "conf/fragments/u1r.conf", '
    repo @u1r
        RW+     =   tester
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();
try "
        /Initialized empty Git repository in .*/r1a.git//
        /Initialized empty Git repository in .*/r1b.git//
";

# u1 push u1r pass
put   "conf/fragments/u1r.conf", '
    repo @u1r
        RW+     =   u5
';
try "SUBCONF_PUSH u1 u1; !/FATAL/" or die text();

# u2 main push fail
confadd '
    repo @u1r
        RW+     =   u6
';
try "SUBCONF_PUSH u2 u2; /FATAL/;
        /W VREF/NAME/conf/gitolite.conf gitolite-admin u2 DENIED by VREF/NAME//
";

try "git reset --hard origin/master; ok";

# u2 push u1r fail
put   "conf/fragments/u1r.conf", '
    repo @u1r
        RW+     =   u6
';
try "SUBCONF_PUSH u2 u2; /FATAL/
        /W VREF/NAME/conf/fragments/u1r.conf gitolite-admin u2 DENIED by VREF/NAME//
";

try "git reset --hard origin/master; ok";

# u3 set perms for r2a fail
put   "conf/fragments/u3r.conf", '
    repo r2a
        RW+     =   u6
';
try "SUBCONF_PUSH u3 u3;
        /WARNING: subconf 'u3r' attempting to set access for r2a/
";

try "git reset --hard origin/master; ok";

# u3 add r2b to u3r fail

put   "conf/fragments/u3r.conf", '
    @u3r    =   r2b
    repo @u3r
        RW+     =   u6
';

try "SUBCONF_PUSH u3 u3
        /WARNING: expanding '\@u3r'/
        /WARNING: subconf 'u3r' attempting to set access for r2b/
";
