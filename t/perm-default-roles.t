#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# permissions using role names
# ----------------------------------------------------------------------

try "plan 27";
try "DEF POK = !/DENIED/; !/failed to push/";

my $rb = `gitolite query-rc -n GL_REPO_BASE`;

try "pwd";
my $od = text();
chomp($od);

my $t;

confreset; confadd '
    @g1 = u1
    @g2 = u2
    @g3 = u3
    @g4 = u4
        repo foo/CREATOR/..*
          C                 =   @g1 @g2
          RW+               =   CREATOR
          -     refs/tags/  =   WRITERS
          RW                =   WRITERS
          R                 =   READERS

        repo bar/CREATOR/..*
          C                 =   @g3 @g4
          RW+               =   CREATOR
          -     refs/tags/  =   WRITERS
          RW                =   WRITERS
          R                 =   READERS
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

# create repos - 1; no gl-perms files expected
try "

cd ..

# make foo/u1/u1r1
glt clone u1 file:///foo/u1/u1r1
        /Initialized empty Git repository in .*/foo/u1/u1r1.git//

# make bar/u3/u3r1
glt clone u3 file:///bar/u3/u3r1
        /Initialized empty Git repository in .*/bar/u3/u3r1.git//

cd u3r1
";

try "cd $rb; find . -name gl-perms; cd $od"; cmp text(), '';

# enable set-default-roles feature
try "
    cat $ENV{HOME}/.gitolite.rc
    perl s/# 'set-default-roles'/'set-default-roles'/
    put $ENV{HOME}/.gitolite.rc
";

# create repos - 2; empty gl-perms files expected
try "

cd ..

# make foo/u1/u1r2
glt clone u1 file:///foo/u1/u1r2
        /Initialized empty Git repository in .*/foo/u1/u1r2.git//

# make bar/u3/u3r2
glt clone u3 file:///bar/u3/u3r2
        /Initialized empty Git repository in .*/bar/u3/u3r2.git//

cd u3r2
";

try "cd $rb; find . -name gl-perms";
$t = md5sum(sort (lines()));
cmp $t, 'd41d8cd98f00b204e9800998ecf8427e  ./bar/u3/u3r2.git/gl-perms
d41d8cd98f00b204e9800998ecf8427e  ./foo/u1/u1r2.git/gl-perms
';
try "cd $od";

# enable per repo default roles
confadd '
        repo foo/CREATOR/..*
        option default.roles-1  =   READERS u3
        option default.roles-2  =   WRITERS u4

        repo bar/CREATOR/..*
        option default.roles-1  =   READERS u5
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

# create repos - 3; filled gl-perms expected
try "

cd ..

# make foo/u1/u1r3
glt clone u1 file:///foo/u1/u1r3
        /Initialized empty Git repository in .*/foo/u1/u1r3.git//

# make bar/u3/u3r3
glt clone u3 file:///bar/u3/u3r3
        /Initialized empty Git repository in .*/bar/u3/u3r3.git//

cd u3r3
";

try "cd $rb; find . -name gl-perms";
$t = md5sum(sort (lines()));
cmp $t, 'd41d8cd98f00b204e9800998ecf8427e  ./bar/u3/u3r2.git/gl-perms
b09856c1addc8e46f6ce0d21a666a633  ./bar/u3/u3r3.git/gl-perms
d41d8cd98f00b204e9800998ecf8427e  ./foo/u1/u1r2.git/gl-perms
1b5af29692fad391318573bbe633b476  ./foo/u1/u1r3.git/gl-perms
';
try "cd $od";

# add perms to an old repo
try "
echo WRITERS \@h1 | glt perms u1 foo/u1/u1r1
";

try "cd $rb; find . -name gl-perms";
$t = md5sum(sort (lines()));
cmp $t, 'd41d8cd98f00b204e9800998ecf8427e  ./bar/u3/u3r2.git/gl-perms
b09856c1addc8e46f6ce0d21a666a633  ./bar/u3/u3r3.git/gl-perms
f8f0fd8e139ddb64cd5572914b98750a  ./foo/u1/u1r1.git/gl-perms
d41d8cd98f00b204e9800998ecf8427e  ./foo/u1/u1r2.git/gl-perms
1b5af29692fad391318573bbe633b476  ./foo/u1/u1r3.git/gl-perms
';
try "cd $od";

# add perms to a new repo
try "
echo WRITERS \@h2 | glt perms u1 -c foo/u1/u1r4
";

try "cd $rb; find . -name gl-perms";
$t = md5sum(sort (lines()));
cmp $t, 'd41d8cd98f00b204e9800998ecf8427e  ./bar/u3/u3r2.git/gl-perms
b09856c1addc8e46f6ce0d21a666a633  ./bar/u3/u3r3.git/gl-perms
f8f0fd8e139ddb64cd5572914b98750a  ./foo/u1/u1r1.git/gl-perms
d41d8cd98f00b204e9800998ecf8427e  ./foo/u1/u1r2.git/gl-perms
1b5af29692fad391318573bbe633b476  ./foo/u1/u1r3.git/gl-perms
df17cd2d47e4d99642d7c5ce4093d115  ./foo/u1/u1r4.git/gl-perms
';
try "cd $od";
