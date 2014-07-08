#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# permissions using role names
# ----------------------------------------------------------------------

try "plan 91";
try "DEF POK = !/DENIED/; !/failed to push/";

confreset; confadd '
    @g1 = u1
    @g2 = u2
    @g3 = u3
    @g4 = u4
        repo foo/CREATOR/..*
          C                 =   @g1
          RW+               =   CREATOR
          -     refs/tags/  =   WRITERS
          RW                =   WRITERS
          R                 =   READERS
          RW+D              =   MANAGERS
          RW    refs/tags/  =   TESTERS
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "

cd ..

# make foo/u1/u1r1
rm -rf ~/td/u1r1
glt clone u1 file:///foo/u1/u1r1
        /Initialized empty Git repository in .*/foo/u1/u1r1.git//
cd u1r1

# CREATOR can push
tc e-549 e-550
glt push u1 file:///foo/u1/u1r1 master:master
        POK; /master -> master/
# CREATOR can create branch
tc w-277 w-278
glt push u1 file:///foo/u1/u1r1 master:b1
        POK; /master -> b1/
# CREATOR can rewind branch
git reset --hard HEAD^
tc d-987 d-988
glt push u1 file:///foo/u1/u1r1 +master:b1
        POK; /master -> b1 \\(forced update\\)/
# CREATOR cannot delete branch
glt push u1 file:///foo/u1/u1r1 :b1
        /D refs/heads/b1 foo/u1/u1r1 u1 DENIED by fallthru/
        reject

# CREATOR can push a tag
git tag t1 HEAD^^
glt push u1 file:///foo/u1/u1r1 t1
        POK; /\\[new tag\\]         t1 -> t1/

# add u2 to WRITERS
echo WRITERS \@g2 | glt perms u1 foo/u1/u1r1
glt perms u1 -l foo/u1/u1r1
        /WRITERS \@g2/

glt fetch u1
git reset --hard origin/master

# WRITERS can push
tc j-185 j-186
glt push u2 file:///foo/u1/u1r1 master:master
        POK; /master -> master/
# WRITERS can create branch
tc u-420 u-421
glt push u2 file:///foo/u1/u1r1 master:b2
        POK; /master -> b2/
# WRITERS cannot rewind branch
git reset --hard HEAD^
tc l-136 l-137
glt push u2 file:///foo/u1/u1r1 +master:b2
        /\\+ refs/heads/b2 foo/u1/u1r1 u2 DENIED by fallthru/
        reject
# WRITERS cannot delete branch
glt push u2 file:///foo/u1/u1r1 :b2
        /D refs/heads/b2 foo/u1/u1r1 u2 DENIED by fallthru/
        reject
# WRITERS cannot push a tag
git tag t2 HEAD^^
glt push u2 file:///foo/u1/u1r1 t2
        /W refs/tags/t2 foo/u1/u1r1 u2 DENIED by refs/tags//
        reject

# change u2 to READERS
echo READERS u2 | glt perms u1 foo/u1/u1r1
glt perms u1 -l foo/u1/u1r1
        /READERS u2/

glt fetch u1
git reset --hard origin/master

# READERS cannot push at all
tc v-753 v-754
glt push u2 file:///foo/u1/u1r1 master:master
        /W any foo/u1/u1r1 u2 DENIED by fallthru/

# add invalid category MANAGERS
    /usr/bin/printf 'READERS u6\\nMANAGERS u2\\n' | glt perms u1 foo/u1/u1r1
        !ok
        /Invalid role 'MANAGERS'/
";

# make MANAGERS valid
put "$ENV{HOME}/g3trc", "\$rc{ROLES}{MANAGERS} = 1;\n";

# add u2 to now valid MANAGERS
try "
    ENV G3T_RC=$ENV{HOME}/g3trc
    gitolite compile;   ok or die compile failed
    /usr/bin/printf 'READERS u6\\nMANAGERS u2\\n' | glt perms u1 foo/u1/u1r1
                            ok;    !/Invalid role 'MANAGERS'/
    glt perms u1 -l foo/u1/u1r1
";

cmp 'READERS u6
MANAGERS u2
';

try "
glt fetch u1
git reset --hard origin/master

# MANAGERS can push
tc d-714 d-715
glt push u2 file:///foo/u1/u1r1 master:master
        POK; /master -> master/

# MANAGERS can create branch
tc n-614 n-615
glt push u2 file:///foo/u1/u1r1 master:b3
        POK; /master -> b3/
# MANAGERS can rewind branch
git reset --hard HEAD^
tc a-511 a-512
glt push u2 file:///foo/u1/u1r1 +master:b3
        POK; /master -> b3 \\(forced update\\)/
# MANAGERS cannot delete branch
glt push u2 file:///foo/u1/u1r1 :b3
        / - \\[deleted\\]         b3/
# MANAGERS can push a tag
git tag t3 HEAD^^
glt push u2 file:///foo/u1/u1r1 t3
        POK; /\\[new tag\\]         t3 -> t3/

# add invalid category TESTERS
echo TESTERS u2 | glt perms u1 foo/u1/u1r1
        !ok
        /Invalid role 'TESTERS'/
";

# make TESTERS valid
put "|cat >> $ENV{HOME}/g3trc", "\$rc{ROLES}{TESTERS} = 1;\n";

try "
gitolite compile;   ok or die compile failed
# add u2 to now valid TESTERS
echo TESTERS u2 | glt perms u1 foo/u1/u1r1
        !/Invalid role 'TESTERS'/
glt perms u1 -l foo/u1/u1r1
";

cmp 'TESTERS u2
';

try "
glt fetch u1
git reset --hard origin/master

# TESTERS cannot push
tc d-134 d-135
glt push u2 file:///foo/u1/u1r1 master:master
        /W refs/heads/master foo/u1/u1r1 u2 DENIED by fallthru/
        reject
# TESTERS cannot create branch
tc p-668 p-669
glt push u2 file:///foo/u1/u1r1 master:b4
        /W refs/heads/b4 foo/u1/u1r1 u2 DENIED by fallthru/
        reject
# TESTERS cannot delete branch
glt push u2 file:///foo/u1/u1r1 :b2
        /D refs/heads/b2 foo/u1/u1r1 u2 DENIED by fallthru/
        reject
# TESTERS can push a tag
git tag t4 HEAD^^
glt push u2 file:///foo/u1/u1r1 t4
        POK; /\\[new tag\\]         t4 -> t4/
";

# make TESTERS invalid again
put "$ENV{HOME}/g3trc", "\$rc{ROLES}{MANAGERS} = 1;\n";

try "
gitolite compile;   ok or die compile failed
# CREATOR can push
glt fetch u1
git reset --hard origin/master
tc y-626 y-627
glt push u1 file:///foo/u1/u1r1 master:master
        POK; /master -> master/
# TESTERS is an invalid category
git tag t5 HEAD^^
glt push u2 file:///foo/u1/u1r1 t5
        /role 'TESTERS' not allowed, ignoring/
        /W any foo/u1/u1r1 u2 DENIED by fallthru/
";
