#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# deny-create, the RW.*C flag
# ----------------------------------------------------------------------

try "plan 72";

try "DEF POK = !/DENIED/; !/failed to push/";

# test "C" permissions

confreset; confadd '
    @leads = u1 u2
    @devs = u1 u2 u3 u4

    @gfoo = foo
    repo    @gfoo
        RW+C                =   @leads
        RW+C personal/USER/ =   @devs
        RW                  =   @devs
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..
    glt clone u1 file:///foo

    cd foo
    tc t-413 t-414 t-415 t-416 t-417

    # u1 can push/rewind master on foo
    glt push u1 origin master
        POK; /master -> master/
    glt push u1 -f origin master^^:master
        POK; /master\\^\\^ -> master/

    # u2 can create newbr1 on foo
    glt push u2 file:///foo master:newbr1
        POK; /master -> newbr1/

    # u2 can create newtag on foo
    git tag newtag
    glt push u2 file:///foo newtag
        POK; /newtag -> newtag/

    # u3 can push newbr1 on foo
    tc u-962 u-963 u-964 u-965 u-966
    glt push u3 file:///foo master:newbr1
        POK; /master -> newbr1/

    # u4 canNOT create newbr2 on foo
    tc e-615 e-616 e-617 e-618 e-619
    glt push u3 file:///foo master:newbr2
        /C refs/heads/newbr2 foo u3 DENIED by fallthru/
        reject

    # u4 canNOT create newtag2 on foo
    git tag newtag2
    glt push u3 file:///foo newtag2
        /C refs/tags/newtag2 foo u3 DENIED by fallthru/
        reject

    # u4 can create/rewind personal/u4/newbr3 on foo
    tc f-664 f-665 f-666 f-667 f-668
    glt push u4 file:///foo master:personal/u4/newbr3
        POK; /master -> personal/u4/newbr3/
    glt push u4 -f origin master^^:personal/u4/newbr3
        POK; /master\\^\\^ -> personal/u4/newbr3/
";

# bar, without "C" permissions, should behave like old

confadd '
    @leads = u1 u2
    @devs = u1 u2 u3 u4

    @gbar = bar
    repo    @gbar
        RW+                 =   @leads
        RW+  personal/USER/ =   @devs
        RW                  =   @devs
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..
    glt clone u1 file:///bar

    cd bar
    tc u-907 u-908 u-909 u-910 u-911

    # u1 can push/rewind master on bar
    glt push u1 origin master
        POK; /master -> master/
    glt push u1 -f origin master^^:master
        POK; /master\\^\\^ -> master/

    # u2 can create newbr1 on bar
    glt push u2 file:///bar master:newbr1
        POK; /master -> newbr1/

    # u2 can create newtag on bar
    git tag newtag
    glt push u2 file:///bar newtag
        POK; /newtag -> newtag/

    # u3 can push newbr1 on bar
    tc y-862 y-863 y-864 y-865 y-866
    glt push u3 file:///bar master:newbr1
        POK; /master -> newbr1/

    # u4 can create newbr2 on bar
    tc q-417 q-418 q-419 q-420 q-421
    glt push u3 file:///bar master:newbr2
        POK; /master -> newbr2/

    # u4 can create newtag2 on bar
    git tag newtag2
    glt push u3 file:///bar newtag2
        POK; /newtag2 -> newtag2/

    # u4 can create/rewind personal/u4/newbr3 on bar
    tc v-605 v-606 v-607 v-608 v-609
    glt push u4 file:///bar master:personal/u4/newbr3
        POK; /master -> personal/u4/newbr3/
    glt push u4 -f origin master^^:personal/u4/newbr3
        POK; /master\\^\\^ -> personal/u4/newbr3/

";
