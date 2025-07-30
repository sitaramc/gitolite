#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# test script for partial copy feature
# ----------------------------------------------------------------------

try "plan 82";
try "DEF POK = !/DENIED/; !/failed to push/";
my $h = $ENV{HOME};

try "
    cat $h/.gitolite.rc
    perl s/GIT_CONFIG_KEYS.*/GIT_CONFIG_KEYS => '.*',/
    perl s/# 'partial-copy'/'partial-copy'/
    put $h/.gitolite.rc
";

confreset;confadd '
    repo foo
            RW+                 =   u1 u2

    repo foo-pc
            -   secret-1$       =   u4
            R                   =   u4  # marker 01
            RW  next            =   u4
            RW+ dev/USER/       =   u4
            RW  refs/tags/USER/ =   u4

            -   VREF/partial-copy   =   @all
            config gitolite.partialCopyOf = foo
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
        /Init.*empty.*foo\\.git/
        /Init.*empty.*foo-pc\\.git/
";

try "
    cd ..

    ## populate repo foo, by user u1
    # create foo with a bunch of branches and tags
    CLONE u1 foo
        /appear.*cloned/
    cd foo
    tc a1 a2
    checkout -b dev/u1/foo; tc f1 f2
    checkout master; tc m1 m2
    checkout master; checkout -b next; tc n1 n2; tag nt1
    checkout -b secret-1; tc s11 s12; tag s1t1
    checkout next; checkout -b secret-2; tc s21 s22; tag s2t1
    glt push u1 --all
        /new branch/; /secret-1/; /secret-2/
    glt push u1 --tags
        /new tag/; /s1t1/; /s2t1/

    ## user u4 tries foo, fails, tries foo-pc
    cd ..
    CLONE u4 foo foo4; !ok
        /R any foo u4 DENIED by fallthru/
    CLONE u4 foo-pc ; ok;
        /Cloning into 'foo-pc'/
        /new branch.* dev/u1/foo .* dev/u1/foo/
        /new branch.* master .* master/
        /new branch.* next .* next/
        /new branch.* secret-2 .* secret-2/
        !/new branch.* secret-1 .* secret-1/
        /new tag.* nt1 .* nt1/
        /new tag.* s2t1 .* s2t1/
        !/new tag.* s1t1 .* s1t1/

    ## user u4 pushes to foo-pc
    cd foo-pc
    checkout master
    tc u4m1 u4m2; PUSH u4; !ok
        /W refs/heads/master foo-pc u4 DENIED by fallthru/
        /hook declined to update refs/heads/master/
        /To file:///foo-pc/
        /remote rejected/
        /failed to push some refs to 'file:///foo-pc'/

    checkout next
    tc u4n1 u4n2
    PUSH u4 next; ok
        /To .*/foo.git/
        /new reference\\]   77ab9e6affcaf2168cf7264b3d41a087800fbb2a1c29438ed6b405d8edcd64da -> refs/partial/br-\\d+/
        /file:///foo-pc/
        /................  next -> next/
    tag u4/nexttag; glt push u4 --tags
        /To file:///foo-pc/
        /\\[new tag\\]         u4/nexttag +-> +u4/nexttag/
        /\\[new reference\\]   77ab9e6affcaf2168cf7264b3d41a087800fbb2a1c29438ed6b405d8edcd64da -> refs/partial/br-\\d+/

    checkout master
    checkout -b dev/u4/u4master
    tc devu4m1 devu4m2
    PUSH u4 HEAD; ok
        /To .*/foo.git/
        /new reference\\]   27dacda49a9aef8f461e252817339a2dad6c8e8bc6fc68315b638c50d0388985 -> refs/partial/br-\\d+/
        /file:///foo-pc/
        /new branch.* HEAD -> dev/u4/u4master/

    ## user u1 gets u4's updates, makes some more
    cd ../foo
    glt fetch u1
        /From file:///foo/
        /new branch\\]      dev/u4/u4master -> origin/dev/u4/u4master/
        /new tag\\]         u4/nexttag +-> +u4/nexttag/
        /................  next +-> +origin/next/
    checkout master; tc u1ma1 u1ma2;
        /\\[master .......\\] u1ma2 at Thu Jul  7 06:23:20 2011/
    tag mt2; PUSH u1 master; ok
    checkout secret-1; tc u1s1b1 u1s1b2
        /\\[secret-1 .......\\] u1s1b2 at Thu Jul  7 06:23:20 2011/
    tag s1t2; PUSH u1 HEAD; ok
    checkout secret-2; tc u1s2b1 u1s2b2
        /\\[secret-2 .......\\] u1s2b2 at Thu Jul  7 06:23:20 2011/
    tag s2t2; PUSH u1 HEAD; ok
    glt push u1 --tags; ok

    glt ls-remote u1 origin
        /........................................\trefs/tags/mt2/
        /........................................\trefs/tags/s1t2/
        /........................................\trefs/tags/s2t2/

    ## u4 gets updates but without the tag in secret-1
    cd ../foo-pc
    glt ls-remote u4 origin
        !/ refs/heads/secret-1/; !/s1t1/; !/s1t2/
        /........................................\tHEAD/
        /........................................\trefs/heads/dev/u1/foo/
        /........................................\trefs/heads/dev/u4/u4master/
        /........................................\trefs/heads/master/
        /........................................\trefs/heads/next/
        /........................................\trefs/heads/secret-2/
        /........................................\trefs/tags/mt2/
        /........................................\trefs/tags/nt1/
        /........................................\trefs/tags/s2t1/
        /........................................\trefs/tags/s2t2/

    glt fetch u4
        /................  master     -> origin/master/
        /................  secret-2   -> origin/secret-2/
        /\\[new tag\\]         mt2        -> mt2/
        /\\[new tag\\]         s2t2       -> s2t2/
        !/ refs/heads/secret-1/; !/s1t1/; !/s1t2/
";
__END__

# last words...
glt ls-remote u4 file:///foo-pc

cd ../gitolite-admin
cat conf/gitolite.conf
perl s/.*marker 01.*//;
put conf/gitolite.conf
add conf; commit -m erdel; ok; PUSH admin; ok

glt ls-remote u4 file:///foo-pc
# see rant below at this point

cd $h/repositories/foo-pc.git
git branch -D secret-2
git tag -d s2t1 s2t2
git gc --prune=now
glt ls-remote u4 file:///foo-pc
# only *now* does the rant get addressed

__END__

RANT...

This is where things go all screwy.  Because we still have the *objects*
pointed to by tags s2t1 and s2t2, we still get them back from the main repo.
