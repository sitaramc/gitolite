#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# more on deny-rules
# ----------------------------------------------------------------------

try "plan 126";

try "
    DEF GOOD    = /refs/\\.\\*/
    DEF BAD     = /DENIED/

    DEF Ryes    = gitolite access %1 %2 R any;  ok; GOOD
    DEF Rno     = gitolite access %1 %2 R any;  !ok; BAD

    DEF Wyes    = gitolite access %1 %2 W any;  ok; GOOD
    DEF Wno     = gitolite access %1 %2 W any;  !ok; BAD

    DEF GWyes   = Ryes %1 gitweb
    DEF GWno    = Rno  %1 gitweb

    DEF GDyes   = Ryes %1 daemon
    DEF GDno    = Rno  %1 daemon
";

confreset;confadd '
    repo one
        RW+ =   u1
        R   =   u2
        -   =   u2 u3
        R   =   @all
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    Wyes one u1

    Ryes one u2
    Wno  one u2

    Ryes one u3
    Wno  one u3

    Ryes one u6
    Wno  one u6

    GDyes one
    GWyes one
";

confadd '
    option deny-rules = 1
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    Wyes one u1

    Ryes one u2
    Wno  one u2

    Rno  one u3

    Ryes one u6
    Wno  one u6

    GDyes one
    GWyes one
";

confadd '
    repo two
        RW+ =   u1
        R   =   u2
        -   =   u2 u3 gitweb daemon
        R   =   @all
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    GWyes two
    GDyes two
";

confadd '
    option deny-rules = 1
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    GWno  two
    GDno  two
";

# set 3 -- allow gitweb to all but admin repo

confadd '
    repo gitolite-admin
        -   =   gitweb daemon
    option deny-rules = 1

    repo three
        RW+ =   u3
        R   =   gitweb daemon
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    GDyes   three
    GWyes   three
    GDno    gitolite-admin
    GWno    gitolite-admin
";

# set 4 -- allow gitweb to all but admin repo

confadd '
    repo four
        RW+ =   u4
        -   =   gitweb daemon

    repo @all
        R   =   @all
';
try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    GDyes   four
    GWyes   four
    GDno    gitolite-admin
    GWno    gitolite-admin
";

# set 5 -- go wild

confreset; confadd '
    repo foo/..*
        C   =   u1
        RW+ =   CREATOR
        -   =   gitweb daemon
        R   =   @all

    repo bar/..*
        C   =   u2
        RW+ =   CREATOR
        -   =   gitweb daemon
        R   =   @all
    option deny-rules = 1
';
try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    glt ls-remote u1 file:///foo/one
    glt ls-remote u2 file:///bar/two
    Wyes foo/one u1
    Wyes bar/two u2

    GDyes foo/one
    GDyes foo/one
    GWno  bar/two
    GWno  bar/two
";
