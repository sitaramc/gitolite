#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# wild repos - part 1
# ----------------------------------------------------------------------

try "plan 66";

confreset;confadd '
    @prof       =   u1
    @TAs        =   u2 u3
    @students   =   u4 u5 u6

    @gfoo = foo/CREATOR/a[0-9][0-9]
    repo    @gfoo
        C   =   @all
        RW+ =   CREATOR
        RW  =   WRITERS @TAs
        R   =   READERS @prof
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
# reasonably complex setup; we'll do everything from one repo though
cd ..

# u1 create success
glt clone u1 file:///foo/u1/a01;        ok;     /Initialized empty Git repository in .*/foo/u1/a01.git//

# u2 create success
glt clone u2 file:///foo/u2/a02;        ok;     /Initialized empty Git repository in .*/foo/u2/a02.git//

# u4 tries to create u2 repo
glt clone u4 file:///foo/u2/a12;        !ok;    /R any foo/u2/a12 u4 DENIED by fallthru/

# line anchored regexes
glt clone u4 file:///foo/u4/a1234;      !ok;    /R any foo/u4/a1234 u4 DENIED by fallthru/

# u4 tries to create his own repo
glt clone u4 file:///foo/u4/a12;        ok;     /Initialized empty Git repository in .*/foo/u4/a12.git//
                                                /warning: You appear to have cloned an empty repository./

# u4 push success
cd a12
tc p-728 p-729 p-730 p-731;             ok
glt push u4 origin master;              ok;     /To file:///foo/u4/a12/
                                                /\\* \\[new branch\\]      master -> master/

# u1 clone success
cd ..
glt clone u1 file:///foo/u4/a12 u1a12;  ok;     /Cloning into 'u1a12'.../

# u1 push fail
cd u1a12
tc m-778 m-779;                         ok;
glt push u1 origin;                     !ok;    /W any foo/u4/a12 u1 DENIED by fallthru/

# u2 clone success
cd ..
glt clone u2 file:///foo/u4/a12 u2a12;  ok;     /Cloning into 'u2a12'.../

# u2 push success
cd u2a12
tc s-708 s-709;                         ok;
glt push u2 origin;                     ok;     /To file:///foo/u4/a12/
                                                /master -> master/

# u2 rewind fail
glt push u2 -f origin master^:master;   !ok;    /\\+ refs/heads/master foo/u4/a12 u2 DENIED by fallthru/
                                                reject

# u4 pull to sync up
cd ../a12
glt pull u4;                            ok;     /Fast-forward/
                                                /From file:///foo/u4/a12/
                                                /master     -> origin/master/

# u4 rewind success
git reset --hard HEAD^;                 ok
glt push u4 -f;                         ok;     /To file:///foo/u4/a12/
                                                /\\+ .* master -> master \\(forced update\\)/

# u5 clone fail
cd ..
glt clone u5 file:///foo/u4/a12 u5a12;  !ok;    /R any foo/u4/a12 u5 DENIED by fallthru/

glt perms u4 foo/u4/a12 + READERS u5
glt perms u4 foo/u4/a12 + WRITERS u6

glt perms u4 -l foo/u4/a12
";

cmp 'READERS u5
WRITERS u6
';

try "
# u5 clone success
glt clone u5 file:///foo/u4/a12 u5a12;  ok;     /Cloning into 'u5a12'.../

# u5 push fail
cd u5a12
tc y-743 y-744;                         ok
glt push u5;                            !ok;    /W any foo/u4/a12 u5 DENIED by fallthru/

# u6 clone success
cd ..
glt clone u6 file:///foo/u4/a12 u6a12;  ok;     /Cloning into 'u6a12'.../

# u6 push success
cd u6a12
tc k-68 k-69;                           ok
glt push u6 file:///foo/u4/a12;         ok;     /To file:///foo/u4/a12/
                                                /master -> master/

# u6 rewind fail
glt push u6 -f file:///foo/u4/a12 master^:master
                                        !ok;    /\\+ refs/heads/master foo/u4/a12 u6 DENIED by fallthru/
                                                reject
";
