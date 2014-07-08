#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# invalid refnames
# ----------------------------------------------------------------------

try "plan 56";
try "DEF POK = !/DENIED/; !/failed to push/";

confreset; confadd '
    repo aa
        RW+                 =   @all
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "

cd ..
rm -rf aa
glt clone u1 file:///aa
cd aa
tc v-869

glt push u1 origin HEAD
        /To file:///aa/
        POK; /\\* \\[new branch\\]      HEAD -> master/

# push file aa,bb ok
tc  aa,bb
glt push u1 origin HEAD
        /To file:///aa/
        POK; /HEAD -> master/

# push file aa=bb ok
tc  aa=bb
glt push u1 origin HEAD
        /To file:///aa/
        POK; /HEAD -> master/

# push to branch dd,ee ok
glt push u1 origin master:dd,ee
        /To file:///aa/
        POK; /\\* \\[new branch\\]      master -> dd,ee/

# push to branch dd=ee fail
glt push u1 origin master:dd=ee
        /invalid characters in ref or filename: \\'refs/heads/dd=ee/
        reject
";

confreset; confadd '
    repo aa
        RW+                 =   @all
        RW+ NAME/           =   @all
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "

cd ..
rm -rf aa
glt clone u1 file:///aa
cd aa
tc  file-1

glt push u1 origin HEAD
        /To file:///aa/
        POK; /\\* \\[new branch\\]      HEAD -> master/

# push file aa,bb ok
tc  aa,bb
glt push u1 origin HEAD
        /To file:///aa/
        POK; /HEAD -> master/

# push file aa=bb fail
tc  aa=bb
glt push u1 origin HEAD
        /To file:///aa/
        POK; /HEAD -> master/

# push to branch dd,ee ok
git reset --hard HEAD^
tc  some-file
glt push u1 origin master:dd,ee
        /To file:///aa/
        POK; /\\* \\[new branch\\]      master -> dd,ee/

# push to branch dd=ee fail
glt push u1 origin master:dd=ee
        /invalid characters in ref or filename: \\'refs/heads/dd=ee/
        reject
";
