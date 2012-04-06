#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# rule sequence
# ----------------------------------------------------------------------

# this is the specific example in commit 32056e0 of g2

try "plan 27";

try "DEF POK = !/DENIED/; !/failed to push/";

confreset; confadd '
    @private-owners = u1 u2
    @experienced-private-owners = u3 u4

    repo CREATOR/.*
      C   = @private-owners @experienced-private-owners
      RWD = CREATOR
      RW  = WRITERS
      R   = READERS
      -   = @private-owners
      RW+D = CREATOR
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..
    glt clone u1 file:///u1/r1
        /Initialized empty Git repository in .*/u1/r1.git//
    cd r1
    tc h-395
    glt push u1 origin master
    git checkout -b br1
    tc m-367
    tc i-747

    # u1 create branch
    glt push u1 origin br1
        /\\* \\[new branch\\]      br1 -> br1/
        POK; /br1 -> br1/

    # u1 rewind branch
    git reset --hard HEAD^
    tc e-633
    glt push u1 origin +br1
        /\\+ refs/heads/br1 u1/r1 u1 DENIED by refs//
        /error: hook declined to update refs/heads/br1/
        reject

    # u1 delete branch
    glt push u1 origin :br1
        /\\[deleted\\]         br1/

    cd ..
    rm -rf r1
    glt clone u3 file:///u3/r1
        /Initialized empty Git repository in .*/u3/r1.git//
    cd r1
    tc p-274
    glt push u3 origin master
    git checkout -b br1
    tc s-613
    tc k-988

    # u3 create branch
    glt push u3 origin br1
        /\\* \\[new branch\\]      br1 -> br1/
        POK; /br1 -> br1/

    # u3 rewind branch
    git reset --hard HEAD^
    tc n-919
    glt push u3 origin +br1
        /To file:///u3/r1/
        /\\+ .......\\.\\.\\........ br1 -> br1 \\(forced update\\)/

    # u3 delete branch
    glt push u3 origin :br1
        /\\[deleted\\]         br1/
";
