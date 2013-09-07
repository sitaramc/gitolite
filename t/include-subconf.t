#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# include and subconf
# ----------------------------------------------------------------------

try 'plan 58';

confreset; confadd '
    include "i1.conf"
    @i2 = b1
    subconf "i2.conf"
    include "i1.conf"
';
confadd 'i1.conf', '
    @g1 = a1 a2
    repo foo
        RW = u1

    include "j1.conf"
';
confadd 'i2.conf', '
    @g2 = b1 b2
    repo bar b1 b2 i1 i2 @i1 @i2 @g2
        RW = u2
';
confadd 'j1.conf', '
    @h2 = c1 c2
    repo baz
        RW = u3
';

try "ADMIN_PUSH set2; !/FATAL/" or die text();

try "
                                        /i1.conf already included/
	                                    /subconf 'i2' attempting to set access for \@i1, b2, bar, i1/
                                        /WARNING: expanding '\@g2'/

                                        !/attempting to set access.*i2/
                                        /Initialized.*empty.*baz.git/
                                        /Initialized.*empty.*foo.git/
                                        /Initialized.*empty.*b1.git/
                                        /Initialized.*empty.*i2.git/
                                        !/Initialized.*empty.*b2.git/
                                        !/Initialized.*empty.*i1.git/
                                        !/Initialized.*empty.*bar.git/
";

confreset;confadd '
    @g2 = i1 i2 i3
    subconf "g2.conf"
';
confadd 'g2.conf', '
    @g2 = g2 h2 i2
    repo @g2
        RW = u1
';

try "ADMIN_PUSH set3; !/FATAL/" or die text();
try "
                                        /WARNING: expanding '\@g2'/
                                        /WARNING: subconf 'g2' attempting to set access for h2/
                                        /Initialized.*empty.*g2.git/
                                        /Initialized.*empty.*i2.git/
";

confreset;confadd '
    @g2 = i1 i2 i3
    subconf "g2.conf"
';
confadd 'g2.conf', '
    subconf master
    @g2 = g2 h2 i2
    repo @g2
        RW = u1
';

try "
    ADMIN_PUSH set3;           ok;     /FATAL: subconf \\'g2\\' attempting to run 'subconf'/
";

# ----------------------------------------------------------------------

confreset; confadd '
    include "i1.conf"
    @i2 = b1
    subconf i2 "eye2.conf"
';
confadd 'eye2.conf', '
    repo @eye2
        RW = u2
';

try "ADMIN_PUSH set2; !/FATAL/" or die text();

try "
    /subconf 'i2' attempting to set access for \@eye2/
";

confreset; confadd '
    include "i1.conf"
    @i2 = b1
    subconf i2 "eye2.conf"
';
confadd 'eye2.conf', '
    repo @i2
        RW = u2
';

try "ADMIN_PUSH set2; !/FATAL/" or die text();

try "
    !/subconf 'i2' attempting to set access for \@eye2/
";
