#!/usr/bin/env perl
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

try "gitolite list-memberships alice"; cmp
'@all
@crypto
@dilbert
alice
';

try "gitolite list-memberships ashok"; cmp
'@all
@dilbert
ashok
';

try "gitolite list-memberships carol"; cmp
'@all
@crypto
carol
';

try "gitolite list-memberships git"; cmp
'@all
@oss
git
';

try "gitolite list-memberships gitolite"; cmp
'@all
@oss
gitolite
';

try "gitolite list-memberships gitolite3"; cmp
'@all
@oss
gitolite3
';

try "gitolite list-memberships cc"; cmp
'@all
@prop
cc
';

try "gitolite list-memberships p4"; cmp
'@all
@prop
p4
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

