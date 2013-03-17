#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# the various list-* commands
# ----------------------------------------------------------------------

try 'plan 30';

try "## info";

confreset;confadd '
    @oss = git gitolite gitolite3
    @prop = cc p4
    @crypto = alice bob carol
    @dilbert = alice wally ashok

    repo    @oss
        RW              =   u1 @crypto
        R               =   u2 @dilbert
    repo    @prop
        RW  =               u2 @dilbert
        R   =               u1
    repo    t3
                    RW  =   u3
                    R   =   u4
';

try "ADMIN_PUSH info; !/FATAL/" or die text();
try "
                                        /Initialized.*empty.*cc.git/
                                        /Initialized.*empty.*p4.git/
                                        /Initialized.*empty.*git.git/
                                        /Initialized.*empty.*gitolite.git/
                                        /Initialized.*empty.*gitolite3.git/
                                        /Initialized.*empty.*t3.git/
";

try "gitolite list-groups"; cmp
'@crypto
@dilbert
@oss
@prop
';

try "gitolite list-users"; cmp
'@all
@crypto
@dilbert
admin
u1
u2
u3
u4
';
try "gitolite list-repos"; cmp
'@oss
@prop
gitolite-admin
t3
testing
';

try "gitolite list-phy-repos"; cmp
'cc
git
gitolite
gitolite-admin
gitolite3
p4
t3
testing
';

try "gitolite list-memberships -u alice"; cmp
'@crypto
@dilbert
';

try "gitolite list-memberships -u ashok"; cmp
'@dilbert
';

try "gitolite list-memberships -u carol"; cmp
'@crypto
';

try "gitolite list-memberships -r git"; cmp
'@oss
';

try "gitolite list-memberships -r gitolite"; cmp
'@oss
';

try "gitolite list-memberships -r gitolite3"; cmp
'@oss
';

try "gitolite list-memberships -r cc"; cmp
'@prop
';

try "gitolite list-memberships -r p4"; cmp
'@prop
';

try "gitolite list-members \@crypto"; cmp
'alice
bob
carol
';

try "gitolite list-members \@dilbert"; cmp
'alice
ashok
wally
';

try "gitolite list-members \@oss"; cmp
'git
gitolite
gitolite3
';

try "gitolite list-members \@prop"; cmp
'cc
p4
';

