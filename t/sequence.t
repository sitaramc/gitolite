#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# uhh, seems to be another rule sequence test
# ----------------------------------------------------------------------

try "plan 48";

confreset;confadd '
    @staff = u1 u2 u3
    @gfoo = foo/CREATOR/..*
    repo  @gfoo
          C       = u1
          RW+     = CREATOR
          RW      = WRITERS
          -       = @staff
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..
    glt clone u1 file:///foo/u1/bar;    ok
        /Initialized empty Git repository in .*/foo/u1/bar.git//

    cd bar
    tc p-906
    glt push u1 origin master
        /To file:///foo/u1/bar/
        /\\[new branch\\]      master -> master/
    echo WRITERS u2 | glt perms u1 foo/u1/bar
    glt perms u1 -l foo/u1/bar
        /WRITERS u2/
    # expand
    glt info u2
        /R W *\tfoo/u1/bar/
        /R W *\ttesting/

    # push
    cd ..
    glt clone u2 file:///foo/u1/bar u2bar
        /Cloning into 'u2bar'.../
    cd u2bar
    tc p-222
    glt push u2
        /master -> master/
        !/DENIED/
        !/failed to push/
";

confreset;confadd '
    @staff = u1 u2 u3
    @gfoo = foo/CREATOR/.+
    repo  @gfoo
          C       = u1
          RW+     = CREATOR
          -       = @staff
          RW      = WRITERS
          R       = READERS
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..
    rm -rf bar u2bar
    glt clone u1 file:///foo/u1/bar;    ok
        /Initialized empty Git repository in .*/foo/u1/bar.git//

    cd bar
    tc p-906
    glt push u1 origin master
        /To file:///foo/u1/bar/
        /\\[new branch\\]      master -> master/
    echo WRITERS u2 | glt perms u1 foo/u1/bar
    glt perms u1 -l foo/u1/bar
        /WRITERS u2/
    # expand
    glt info u2
        !/R W *\tfoo/u1/baz/
        /R W *\tfoo/u1/bar/
        /R W *\ttesting/

    # push
    cd ..
    glt clone u2 file:///foo/u1/bar u2bar
        /Cloning into 'u2bar'.../
    cd u2bar
    tc p-222
    glt push u2
        !ok
        reject
        /W refs/heads/master foo/u1/bar u2 DENIED by refs/\\.\\*/

    # auto-create using perms fail
    echo READERS u5 | glt perms u4 -c foo/u4/baz
        !/Initialized empty Git repository in .*/foo/u4/baz.git/
        /FATAL: .C any foo/u4/baz u4 DENIED by fallthru/

    # auto-create using perms
    echo READERS u2 | glt perms u1 -c foo/u1/baz
        /Initialized empty Git repository in .*/foo/u1/baz.git/

    glt perms u1 -l foo/u1/baz
        /READERS u2/
    # expand
    glt info u2
        /R   *\tfoo/u1/baz/
        /R W *\tfoo/u1/bar/
        /R W *\ttesting/
";
