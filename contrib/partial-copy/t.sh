#!/bin/bash

# test script for partial copy feature

# WARNING 1: will wipe out your gitolite.conf file (you can recover by usual
# git methods if you need of course).

# WARNING 2: will wipe out (completely) the following directories:

    rm -rf ~/repositories/{foo,foo-pc}.git ~/td

# REQUIRED 1: please make sure rc file allows config 'gitolite.partialCopyOf'.

# REQUIRED 2: please make sure you copied the 2 hooks in contrib/partial-copy
# and installed them into gitolite

# REQUIRED 3: the 'tsh' command and associated Tsh.pm in PATH

# ----

set -e
mkdir ~/td

tsh "plan 83";

# ----

cd ~/gitolite-admin

cat << EOF1 > conf/gitolite.conf
# testing partial-copy
    repo    gitolite-admin
            RW+     =   tester

    repo    testing
            RW+     =   @all
EOF1

tsh "## setup base conf
    add conf; commit -m start; empty; ok; push -f; ok"

cat << EOF2 >> conf/gitolite.conf

    repo foo
            RW+                 =   u1 u2

    repo foo-pc
            -   secret-1$       =   u4
            R                   =   u4  # marker 01
            RW  next            =   u4
            RW+ dev/USER/       =   u4
            RW  refs/tags/USER/ =   u4

            config gitolite.partialCopyOf = foo

EOF2

tsh "
    ## setup partial-repos conf
    add conf; commit -m partial-repos; empty; ok;
    # /master.*partial-repos/
    push;  ok;
        /Init.*empty.*foo\\.git/
        /Init.*empty.*foo-pc\\.git/
        /u3.*u5.*u6/; !/u1/; !/u2/; !/u4/
"

cd ~/td; rm -rf foo foo-pc

tsh "
    ## populate repo foo, by user u1
    # create foo with a bunch of branches and tags
    clone u1:foo
        /appear.*cloned/
    cd foo
    dc a1; dc a2
    checkout -b dev/u1/foo; dc f1; dc f2
    checkout master; dc m1; dc m2
    checkout master; checkout -b next; dc n1; dc n2; tag nt1
    checkout -b secret-1; dc s11; dc s12; tag s1t1
    checkout next; checkout -b secret-2; dc s21; dc s22; tag s2t1
    push --all
        /new branch/; /secret-1/; /secret-2/
    push --tags
        /new tag/; /s1t1/; /s2t1/
"

tsh "
    ## user u4 tries foo, fails, tries foo-pc
    cd $HOME/td
    clone u4:foo foo4; !ok
        /R access for foo DENIED to u4/
    clone u4:foo-pc ; ok;
        /Cloning into 'foo-pc'/
        /new branch.* dev/u1/foo .* dev/u1/foo/
        /new branch.* master .* master/
        /new branch.* next .* next/
        /new branch.* secret-2 .* secret-2/
        !/new branch.* secret-1 .* secret-1/
        /new tag.* nt1 .* nt1/
        /new tag.* s2t1 .* s2t1/
        !/new tag.* s1t1 .* s1t1/

"

tsh "
    ## user u4 pushes to foo-pc
    cd $HOME/td/foo-pc
    checkout master
    dc u4m1; dc u4m2; push; !ok
        /W refs/heads/master foo-pc u4 DENIED by fallthru/
        /hook declined to update refs/heads/master/
        /To u4:foo-pc/
        /remote rejected/
        /failed to push some refs to 'u4:foo-pc'/

    checkout next
    dc u4n1; dc u4n2
    push origin next; ok
        /To /home/gl-test/repositories/foo.git/
        /new branch\]      ca3787119b7e8b9914bc22c939cefc443bc308da -> br-\d+/
        /u4:foo-pc/
        /52c7716..ca37871  next -> next/
    tag u4/nexttag; push --tags
        /To u4:foo-pc/
        /\[new tag\]         u4/nexttag -> u4/nexttag/
        /\[new branch\]      ca3787119b7e8b9914bc22c939cefc443bc308da -> br-\d+/

    checkout master
    checkout -b dev/u4/u4master
    dc devu4m1; dc devu4m2
    push origin HEAD; ok
        /To /home/gl-test/repositories/foo.git/
        /new branch\]      228353950557ed1eb13679c1fce4d2b4718a2060 -> br-\d+/
        /u4:foo-pc/
        /new branch.* HEAD -> dev/u4/u4master/

"

tsh "
    ## user u1 gets u4's updates, makes some more
    cd $HOME/td/foo
    git remote update
        /Fetching origin/
        /From u1:foo/
        /new branch\]      dev/u4/u4master -> origin/dev/u4/u4master/
        /new tag\]         u4/nexttag -> u4/nexttag/
        /52c7716..ca37871  next       -> origin/next/
    checkout master; dc u1ma1; dc u1ma2;
        /\[master 8ab1ff5\] u1ma2 at Thu Jul  7 06:23:20 2011/
    tag mt2; push-om; ok
    checkout secret-1; dc u1s1b1; dc u1s1b2
        /\[secret-1 5f96cb5\] u1s1b2 at Thu Jul  7 06:23:20 2011/
    tag s1t2; push origin HEAD; ok
    checkout secret-2; dc u1s2b1; dc u1s2b2
        /\[secret-2 1ede682\] u1s2b2 at Thu Jul  7 06:23:20 2011/
    tag s2t2; push origin HEAD; ok
    push --tags; ok

    git ls-remote origin
        /8ab1ff512faf5935dc0fbff357b6f453b66bb98b\trefs/tags/mt2/
        /5f96cb5ff73c730fb040eb2d01981f7677ca6dba\trefs/tags/s1t2/
        /1ede6829ec7b75a53cd6acb7da64e5a8011e6050\trefs/tags/s2t2/
"

tsh "
    ## u4 gets updates but without the tag in secret-1
    cd $HOME/td/foo-pc
    git ls-remote origin;
        !/ refs/heads/secret-1/; !/s1t1/; !/s1t2/
        /8ab1ff512faf5935dc0fbff357b6f453b66bb98b\tHEAD/
        /8ced4a374b3935bac1a5ba27ef8dd950bd867d47\trefs/heads/dev/u1/foo/
        /228353950557ed1eb13679c1fce4d2b4718a2060\trefs/heads/dev/u4/u4master/
        /8ab1ff512faf5935dc0fbff357b6f453b66bb98b\trefs/heads/master/
        /ca3787119b7e8b9914bc22c939cefc443bc308da\trefs/heads/next/
        /1ede6829ec7b75a53cd6acb7da64e5a8011e6050\trefs/heads/secret-2/
        /8ab1ff512faf5935dc0fbff357b6f453b66bb98b\trefs/tags/mt2/
        /52c7716c6b029963dd167c647c1ff6222a366499\trefs/tags/nt1/
        /01f04ece6519e7c0e6aea3d26c7e75e9c4e4b06d\trefs/tags/s2t1/
        /1ede6829ec7b75a53cd6acb7da64e5a8011e6050\trefs/tags/s2t2/

    git remote update
        /3ea704d..8ab1ff5  master     -> origin/master/
        /01f04ec..1ede682  secret-2   -> origin/secret-2/
        /\[new tag\]         mt2        -> mt2/
        /\[new tag\]         s2t2       -> s2t2/
        !/ refs/heads/secret-1/; !/s1t1/; !/s1t2/

"

echo DONE
# last words...
git ls-remote u4:foo-pc

cd ~/gitolite-admin
perl -ni -e 'print unless /marker 01/' conf/gitolite.conf
git test 'add conf' 'commit -m erdel' 'ok' 'push -f' 'ok'

git ls-remote u4:foo-pc

cat >&2 <<RANT

This is where things go all screwy.  Because we still have the *objects*
pointed to by tags s2t1 and s2t2, we still get them back from the main repo.

<sigh>

RANT
