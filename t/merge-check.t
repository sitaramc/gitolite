#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# merge check -- the M flag
# ----------------------------------------------------------------------

try "plan 57";

confreset;confadd '
    repo  foo
          RW+M      =   u1
          RW+       =   u2
          RWM      .=   u3
          RW        =   u4
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

# setup a merged push

try "
    cd ..
    ls -al foo;         !ok;    /cannot access foo: No such file or directory/
    glt clone u1 file:///foo
                        ok;     /Cloning into/
                                /You appear to have cloned an empty/
";

try "
    cd foo;             ok
    ls -Al;             ok;     /\.git/
    test-commit aa;     ok;     /1 file changed, 1 insertion/
    tag start;          ok
    glt push u1 origin master
                        ok;     /new branch.*master.-..master/
                                /create.delete ignored.*merge-check/
    checkout -b new;    ok;     /Switched to a new branch 'new'/
    test-commit bb cc;  ok
    checkout master;    ok;     /Switched to branch 'master'/
    test-commit dd ee;  ok
    git merge new;      ok;     /Merge made.*recursive/
    test-commit ff;     ok
    tag end;            ok
";

# push by u4 should fail
try "
    glt push u4 file:///foo master
                        !ok;    /WM refs/heads/master foo u4 DENIED by fallthru/
                                /To file:///foo/
                                /remote rejected.*hook declined/
                                /failed to push some refs/
";

# push by u3 should succeed
try "
    glt push u3 file:///foo master
                        ok;     /To file:///foo/; /master.-..master/
";

# rewind by u3 should fail
try "
    reset-h start;      ok;     /HEAD is now at .* aa /
    glt push u3 file:///foo +master
                         !ok;   /rejected.*hook declined/
                                /failed to push some refs/
";

# rewind by u2 should succeed
try "
    glt push u2 file:///foo +master
                         ok;    /To file:///foo/
                                /forced update/
";

# push by u2 should fail
try "
    reset-h end;        ok;     /HEAD is now at .* ff /
    glt push u2 file:///foo master
                        !ok;    /WM refs/heads/master foo u2 DENIED by fallthru/
                                /To file:///foo/
                                /remote rejected.*hook declined/
                                /failed to push some refs/
";

# push by u1 should succeed
try "
    glt push u1 file:///foo master
                        ok;     /master.-..master/
";
