#!/usr/bin/perl
use strict;
use warnings;
use 5.10.0;
use Data::Dumper;

# this is hardcoded; change it if needed
use lib "$ENV{PWD}/src/lib";

use Gitolite::Test;

BEGIN {
    $ENV{G3T_RC} = "$ENV{HOME}/g3trc";
    put "$ENV{G3T_RC}", "\$rc{ROLES} = {
        FORCERS => 1,
        MASTERS => 1,
        READERS => 1,
        ROOT => 1,
        TEAM => 1,
        WRITERS => 1
    }";
}

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

# permissions using role names
# ----------------------------------------------------------------------

try "plan 1163";
try "DEF POK = !/DENIED/; !/failed to push/";

# basic push admin repo
confreset; confadd '
# order is important for these next few repo group definitions, because an
# individual repo may pick and choose any combination of them, and they should
# apply sensibly.  In this example, "BASE" is pretty much required; the others
# are optional.

# if you want someone to have "ultimate" power over all refs in the repo,
# add them to the ROOT role.
repo @BASE
    RW+CD                       =   ROOT

# add this to the repo group list to allow personal branches
repo @PERSONAL
    RW+CD   dev/USER/           =   TEAM
    -       dev/                =   TEAM
    RW+CD   refs/tags/dev/USER/ =   TEAM
    -       refs/tags/dev/      =   TEAM

# add this to the repo group list to control tagging for release versions
repo @RELEASES
    RWC refs/tags/v[0-9]        =   RELEASERS
    -   refs/tags/v[0-9]        =   @all

# (the basic set of access rules continues)
repo @BASE
    # Note that "FORCERS" here, even though they have RW+CD,
    #   1.  cannot touch other users personal branches or tags if you added
    #       PER_BR to the repo group list, and
    #   2.  create a release tag unless they are also in RELEASE_TAGGERS if
    #       you added TAGS to the repo group list
    RW+CD                       =   FORCERS
    RWC master                  =   MASTERS
    -   master                  =   @all
    RWC                         =   RELEASERS MASTERS WRITERS
    # Note you can define "@all" to have the READERS role, and then this will
    # effectively be public (albeit authenticated public) readable.
    R                           =   READERS

=begin template-data

repo base = BASE
    FORCERS = u1
    MASTERS = u2
    WRITERS = u3
    READERS = u4

repo baseroot = BASE
    ROOT    = admin
    FORCERS = u1
    MASTERS = u2
    WRITERS = u3
    READERS = u4

repo basepers = BASE PERSONAL
    FORCERS = u1
    MASTERS = u2
    WRITERS = u3
    READERS = u4 u5
    TEAM    = u1 u2 u3 u5 u6

repo baserel  = BASE RELEASES
    FORCERS = u1
    MASTERS = u2
    WRITERS = u3
    READERS = u4 u5
    TEAM    = u1 u2 u3 u5 u6

repo baseall = BASE PERSONAL RELEASES
    ROOT    = admin
    FORCERS = u1
    MASTERS = u2
    WRITERS = u3
    READERS = u4 u5
    TEAM    = u1 u2 u3 u5 u6

=end
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

# now we step outside tsh, into pure perl

sub _access {
    push @_, 'any' if @_ < 4;
    my $ref = pop;
    $ref =~ s(^)(refs/heads/) if $ref ne 'any' and $ref !~ m(^(refs|VREF)/);
    push @_, $ref;

    return access(@_);
}

sub ok {
    say STDOUT (_access(@_) !~ /DENIED/ ? "ok" : "not ok");
}
sub nok {
    say STDOUT (_access(@_) =~ /DENIED/ ? "ok" : "not ok");
}

nok qw( base admin R );
nok qw( base admin W master );
nok qw( base admin W notmaster );
nok qw( base admin W refs/tags/boo );
nok qw( base admin W refs/tags/v1 );
nok qw( base admin W dev/admin/foo );
nok qw( base admin W refs/tags/dev/admin/foo );
nok qw( base admin W dev/alice/foo );
nok qw( base admin W refs/tags/dev/alice/foo );
nok qw( base admin + master );
nok qw( base admin + notmaster );
nok qw( base admin + refs/tags/boo );
nok qw( base admin + refs/tags/v1 );
nok qw( base admin + dev/admin/foo );
nok qw( base admin + refs/tags/dev/admin/foo );
nok qw( base admin + dev/alice/foo );
nok qw( base admin + refs/tags/dev/alice/foo );
nok qw( base admin C master );
nok qw( base admin C notmaster );
nok qw( base admin C refs/tags/boo );
nok qw( base admin C refs/tags/v1 );
nok qw( base admin C dev/admin/foo );
nok qw( base admin C refs/tags/dev/admin/foo );
nok qw( base admin C dev/alice/foo );
nok qw( base admin C refs/tags/dev/alice/foo );
nok qw( base admin D master );
nok qw( base admin D notmaster );
nok qw( base admin D refs/tags/boo );
nok qw( base admin D refs/tags/v1 );
nok qw( base admin D dev/admin/foo );
nok qw( base admin D refs/tags/dev/admin/foo );
nok qw( base admin D dev/alice/foo );
nok qw( base admin D refs/tags/dev/alice/foo );

ok  qw( base u1 R );
ok  qw( base u1 W master );
ok  qw( base u1 W notmaster );
ok  qw( base u1 W refs/tags/boo );
ok  qw( base u1 W refs/tags/v1 );
ok  qw( base u1 W dev/u1/foo );
ok  qw( base u1 W refs/tags/dev/u1/foo );
ok  qw( base u1 W dev/alice/foo );
ok  qw( base u1 W refs/tags/dev/alice/foo );
ok  qw( base u1 + master );
ok  qw( base u1 + notmaster );
ok  qw( base u1 + refs/tags/boo );
ok  qw( base u1 + refs/tags/v1 );
ok  qw( base u1 + dev/u1/foo );
ok  qw( base u1 + refs/tags/dev/u1/foo );
ok  qw( base u1 + dev/alice/foo );
ok  qw( base u1 + refs/tags/dev/alice/foo );
ok  qw( base u1 C master );
ok  qw( base u1 C notmaster );
ok  qw( base u1 C refs/tags/boo );
ok  qw( base u1 C refs/tags/v1 );
ok  qw( base u1 C dev/u1/foo );
ok  qw( base u1 C refs/tags/dev/u1/foo );
ok  qw( base u1 C dev/alice/foo );
ok  qw( base u1 C refs/tags/dev/alice/foo );
ok  qw( base u1 D master );
ok  qw( base u1 D notmaster );
ok  qw( base u1 D refs/tags/boo );
ok  qw( base u1 D refs/tags/v1 );
ok  qw( base u1 D dev/u1/foo );
ok  qw( base u1 D refs/tags/dev/u1/foo );
ok  qw( base u1 D dev/alice/foo );
ok  qw( base u1 D refs/tags/dev/alice/foo );

ok  qw( base u2 R );
ok  qw( base u2 W master );
ok  qw( base u2 W notmaster );
ok  qw( base u2 W refs/tags/boo );
ok  qw( base u2 W refs/tags/v1 );
ok  qw( base u2 W dev/u2/foo );
ok  qw( base u2 W refs/tags/dev/u2/foo );
ok  qw( base u2 W dev/alice/foo );
ok  qw( base u2 W refs/tags/dev/alice/foo );
nok qw( base u2 + master );
nok qw( base u2 + notmaster );
nok qw( base u2 + refs/tags/boo );
nok qw( base u2 + refs/tags/v1 );
nok qw( base u2 + dev/u2/foo );
nok qw( base u2 + refs/tags/dev/u2/foo );
nok qw( base u2 + dev/alice/foo );
nok qw( base u2 + refs/tags/dev/alice/foo );
ok  qw( base u2 C master );
ok  qw( base u2 C notmaster );
ok  qw( base u2 C refs/tags/boo );
ok  qw( base u2 C refs/tags/v1 );
ok  qw( base u2 C dev/u2/foo );
ok  qw( base u2 C refs/tags/dev/u2/foo );
ok  qw( base u2 C dev/alice/foo );
ok  qw( base u2 C refs/tags/dev/alice/foo );
nok qw( base u2 D master );
nok qw( base u2 D notmaster );
nok qw( base u2 D refs/tags/boo );
nok qw( base u2 D refs/tags/v1 );
nok qw( base u2 D dev/u2/foo );
nok qw( base u2 D refs/tags/dev/u2/foo );
nok qw( base u2 D dev/alice/foo );
nok qw( base u2 D refs/tags/dev/alice/foo );

ok  qw( base u3 R );
nok qw( base u3 W master );
ok  qw( base u3 W notmaster );
ok  qw( base u3 W refs/tags/boo );
ok  qw( base u3 W refs/tags/v1 );
ok  qw( base u3 W dev/u3/foo );
ok  qw( base u3 W refs/tags/dev/u3/foo );
ok  qw( base u3 W dev/alice/foo );
ok  qw( base u3 W refs/tags/dev/alice/foo );
nok qw( base u3 + master );
nok qw( base u3 + notmaster );
nok qw( base u3 + refs/tags/boo );
nok qw( base u3 + refs/tags/v1 );
nok qw( base u3 + dev/u3/foo );
nok qw( base u3 + refs/tags/dev/u3/foo );
nok qw( base u3 + dev/alice/foo );
nok qw( base u3 + refs/tags/dev/alice/foo );
nok qw( base u3 C master );
ok  qw( base u3 C notmaster );
ok  qw( base u3 C refs/tags/boo );
ok  qw( base u3 C refs/tags/v1 );
ok  qw( base u3 C dev/u3/foo );
ok  qw( base u3 C refs/tags/dev/u3/foo );
ok  qw( base u3 C dev/alice/foo );
ok  qw( base u3 C refs/tags/dev/alice/foo );
nok qw( base u3 D master );
nok qw( base u3 D notmaster );
nok qw( base u3 D refs/tags/boo );
nok qw( base u3 D refs/tags/v1 );
nok qw( base u3 D dev/u3/foo );
nok qw( base u3 D refs/tags/dev/u3/foo );
nok qw( base u3 D dev/alice/foo );
nok qw( base u3 D refs/tags/dev/alice/foo );

ok  qw( base u4 R );
nok qw( base u4 W master );
nok qw( base u4 W notmaster );
nok qw( base u4 W refs/tags/boo );
nok qw( base u4 W refs/tags/v1 );
nok qw( base u4 W dev/u4/foo );
nok qw( base u4 W refs/tags/dev/u4/foo );
nok qw( base u4 W dev/alice/foo );
nok qw( base u4 W refs/tags/dev/alice/foo );
nok qw( base u4 + master );
nok qw( base u4 + notmaster );
nok qw( base u4 + refs/tags/boo );
nok qw( base u4 + refs/tags/v1 );
nok qw( base u4 + dev/u4/foo );
nok qw( base u4 + refs/tags/dev/u4/foo );
nok qw( base u4 + dev/alice/foo );
nok qw( base u4 + refs/tags/dev/alice/foo );
nok qw( base u4 C master );
nok qw( base u4 C notmaster );
nok qw( base u4 C refs/tags/boo );
nok qw( base u4 C refs/tags/v1 );
nok qw( base u4 C dev/u4/foo );
nok qw( base u4 C refs/tags/dev/u4/foo );
nok qw( base u4 C dev/alice/foo );
nok qw( base u4 C refs/tags/dev/alice/foo );
nok qw( base u4 D master );
nok qw( base u4 D notmaster );
nok qw( base u4 D refs/tags/boo );
nok qw( base u4 D refs/tags/v1 );
nok qw( base u4 D dev/u4/foo );
nok qw( base u4 D refs/tags/dev/u4/foo );
nok qw( base u4 D dev/alice/foo );
nok qw( base u4 D refs/tags/dev/alice/foo );

nok qw( base u5 R );
nok qw( base u5 W master );
nok qw( base u5 W notmaster );
nok qw( base u5 W refs/tags/boo );
nok qw( base u5 W refs/tags/v1 );
nok qw( base u5 W dev/u5/foo );
nok qw( base u5 W refs/tags/dev/u5/foo );
nok qw( base u5 W dev/alice/foo );
nok qw( base u5 W refs/tags/dev/alice/foo );
nok qw( base u5 + master );
nok qw( base u5 + notmaster );
nok qw( base u5 + refs/tags/boo );
nok qw( base u5 + refs/tags/v1 );
nok qw( base u5 + dev/u5/foo );
nok qw( base u5 + refs/tags/dev/u5/foo );
nok qw( base u5 + dev/alice/foo );
nok qw( base u5 + refs/tags/dev/alice/foo );
nok qw( base u5 C master );
nok qw( base u5 C notmaster );
nok qw( base u5 C refs/tags/boo );
nok qw( base u5 C refs/tags/v1 );
nok qw( base u5 C dev/u5/foo );
nok qw( base u5 C refs/tags/dev/u5/foo );
nok qw( base u5 C dev/alice/foo );
nok qw( base u5 C refs/tags/dev/alice/foo );
nok qw( base u5 D master );
nok qw( base u5 D notmaster );
nok qw( base u5 D refs/tags/boo );
nok qw( base u5 D refs/tags/v1 );
nok qw( base u5 D dev/u5/foo );
nok qw( base u5 D refs/tags/dev/u5/foo );
nok qw( base u5 D dev/alice/foo );
nok qw( base u5 D refs/tags/dev/alice/foo );

nok qw( base u6 R );
nok qw( base u6 W master );
nok qw( base u6 W notmaster );
nok qw( base u6 W refs/tags/boo );
nok qw( base u6 W refs/tags/v1 );
nok qw( base u6 W dev/u6/foo );
nok qw( base u6 W refs/tags/dev/u6/foo );
nok qw( base u6 W dev/alice/foo );
nok qw( base u6 W refs/tags/dev/alice/foo );
nok qw( base u6 + master );
nok qw( base u6 + notmaster );
nok qw( base u6 + refs/tags/boo );
nok qw( base u6 + refs/tags/v1 );
nok qw( base u6 + dev/u6/foo );
nok qw( base u6 + refs/tags/dev/u6/foo );
nok qw( base u6 + dev/alice/foo );
nok qw( base u6 + refs/tags/dev/alice/foo );
nok qw( base u6 C master );
nok qw( base u6 C notmaster );
nok qw( base u6 C refs/tags/boo );
nok qw( base u6 C refs/tags/v1 );
nok qw( base u6 C dev/u6/foo );
nok qw( base u6 C refs/tags/dev/u6/foo );
nok qw( base u6 C dev/alice/foo );
nok qw( base u6 C refs/tags/dev/alice/foo );
nok qw( base u6 D master );
nok qw( base u6 D notmaster );
nok qw( base u6 D refs/tags/boo );
nok qw( base u6 D refs/tags/v1 );
nok qw( base u6 D dev/u6/foo );
nok qw( base u6 D refs/tags/dev/u6/foo );
nok qw( base u6 D dev/alice/foo );
nok qw( base u6 D refs/tags/dev/alice/foo );

ok  qw( baseroot admin R );
ok  qw( baseroot admin W master );
ok  qw( baseroot admin W notmaster );
ok  qw( baseroot admin W refs/tags/boo );
ok  qw( baseroot admin W refs/tags/v1 );
ok  qw( baseroot admin W dev/admin/foo );
ok  qw( baseroot admin W refs/tags/dev/admin/foo );
ok  qw( baseroot admin W dev/alice/foo );
ok  qw( baseroot admin W refs/tags/dev/alice/foo );
ok  qw( baseroot admin + master );
ok  qw( baseroot admin + notmaster );
ok  qw( baseroot admin + refs/tags/boo );
ok  qw( baseroot admin + refs/tags/v1 );
ok  qw( baseroot admin + dev/admin/foo );
ok  qw( baseroot admin + refs/tags/dev/admin/foo );
ok  qw( baseroot admin + dev/alice/foo );
ok  qw( baseroot admin + refs/tags/dev/alice/foo );
ok  qw( baseroot admin C master );
ok  qw( baseroot admin C notmaster );
ok  qw( baseroot admin C refs/tags/boo );
ok  qw( baseroot admin C refs/tags/v1 );
ok  qw( baseroot admin C dev/admin/foo );
ok  qw( baseroot admin C refs/tags/dev/admin/foo );
ok  qw( baseroot admin C dev/alice/foo );
ok  qw( baseroot admin C refs/tags/dev/alice/foo );
ok  qw( baseroot admin D master );
ok  qw( baseroot admin D notmaster );
ok  qw( baseroot admin D refs/tags/boo );
ok  qw( baseroot admin D refs/tags/v1 );
ok  qw( baseroot admin D dev/admin/foo );
ok  qw( baseroot admin D refs/tags/dev/admin/foo );
ok  qw( baseroot admin D dev/alice/foo );
ok  qw( baseroot admin D refs/tags/dev/alice/foo );

ok  qw( baseroot u1 R );
ok  qw( baseroot u1 W master );
ok  qw( baseroot u1 W notmaster );
ok  qw( baseroot u1 W refs/tags/boo );
ok  qw( baseroot u1 W refs/tags/v1 );
ok  qw( baseroot u1 W dev/u1/foo );
ok  qw( baseroot u1 W refs/tags/dev/u1/foo );
ok  qw( baseroot u1 W dev/alice/foo );
ok  qw( baseroot u1 W refs/tags/dev/alice/foo );
ok  qw( baseroot u1 + master );
ok  qw( baseroot u1 + notmaster );
ok  qw( baseroot u1 + refs/tags/boo );
ok  qw( baseroot u1 + refs/tags/v1 );
ok  qw( baseroot u1 + dev/u1/foo );
ok  qw( baseroot u1 + refs/tags/dev/u1/foo );
ok  qw( baseroot u1 + dev/alice/foo );
ok  qw( baseroot u1 + refs/tags/dev/alice/foo );
ok  qw( baseroot u1 C master );
ok  qw( baseroot u1 C notmaster );
ok  qw( baseroot u1 C refs/tags/boo );
ok  qw( baseroot u1 C refs/tags/v1 );
ok  qw( baseroot u1 C dev/u1/foo );
ok  qw( baseroot u1 C refs/tags/dev/u1/foo );
ok  qw( baseroot u1 C dev/alice/foo );
ok  qw( baseroot u1 C refs/tags/dev/alice/foo );
ok  qw( baseroot u1 D master );
ok  qw( baseroot u1 D notmaster );
ok  qw( baseroot u1 D refs/tags/boo );
ok  qw( baseroot u1 D refs/tags/v1 );
ok  qw( baseroot u1 D dev/u1/foo );
ok  qw( baseroot u1 D refs/tags/dev/u1/foo );
ok  qw( baseroot u1 D dev/alice/foo );
ok  qw( baseroot u1 D refs/tags/dev/alice/foo );

ok  qw( baseroot u2 R );
ok  qw( baseroot u2 W master );
ok  qw( baseroot u2 W notmaster );
ok  qw( baseroot u2 W refs/tags/boo );
ok  qw( baseroot u2 W refs/tags/v1 );
ok  qw( baseroot u2 W dev/u2/foo );
ok  qw( baseroot u2 W refs/tags/dev/u2/foo );
ok  qw( baseroot u2 W dev/alice/foo );
ok  qw( baseroot u2 W refs/tags/dev/alice/foo );
nok qw( baseroot u2 + master );
nok qw( baseroot u2 + notmaster );
nok qw( baseroot u2 + refs/tags/boo );
nok qw( baseroot u2 + refs/tags/v1 );
nok qw( baseroot u2 + dev/u2/foo );
nok qw( baseroot u2 + refs/tags/dev/u2/foo );
nok qw( baseroot u2 + dev/alice/foo );
nok qw( baseroot u2 + refs/tags/dev/alice/foo );
ok  qw( baseroot u2 C master );
ok  qw( baseroot u2 C notmaster );
ok  qw( baseroot u2 C refs/tags/boo );
ok  qw( baseroot u2 C refs/tags/v1 );
ok  qw( baseroot u2 C dev/u2/foo );
ok  qw( baseroot u2 C refs/tags/dev/u2/foo );
ok  qw( baseroot u2 C dev/alice/foo );
ok  qw( baseroot u2 C refs/tags/dev/alice/foo );
nok qw( baseroot u2 D master );
nok qw( baseroot u2 D notmaster );
nok qw( baseroot u2 D refs/tags/boo );
nok qw( baseroot u2 D refs/tags/v1 );
nok qw( baseroot u2 D dev/u2/foo );
nok qw( baseroot u2 D refs/tags/dev/u2/foo );
nok qw( baseroot u2 D dev/alice/foo );
nok qw( baseroot u2 D refs/tags/dev/alice/foo );

ok  qw( baseroot u3 R );
nok qw( baseroot u3 W master );
ok  qw( baseroot u3 W notmaster );
ok  qw( baseroot u3 W refs/tags/boo );
ok  qw( baseroot u3 W refs/tags/v1 );
ok  qw( baseroot u3 W dev/u3/foo );
ok  qw( baseroot u3 W refs/tags/dev/u3/foo );
ok  qw( baseroot u3 W dev/alice/foo );
ok  qw( baseroot u3 W refs/tags/dev/alice/foo );
nok qw( baseroot u3 + master );
nok qw( baseroot u3 + notmaster );
nok qw( baseroot u3 + refs/tags/boo );
nok qw( baseroot u3 + refs/tags/v1 );
nok qw( baseroot u3 + dev/u3/foo );
nok qw( baseroot u3 + refs/tags/dev/u3/foo );
nok qw( baseroot u3 + dev/alice/foo );
nok qw( baseroot u3 + refs/tags/dev/alice/foo );
nok qw( baseroot u3 C master );
ok  qw( baseroot u3 C notmaster );
ok  qw( baseroot u3 C refs/tags/boo );
ok  qw( baseroot u3 C refs/tags/v1 );
ok  qw( baseroot u3 C dev/u3/foo );
ok  qw( baseroot u3 C refs/tags/dev/u3/foo );
ok  qw( baseroot u3 C dev/alice/foo );
ok  qw( baseroot u3 C refs/tags/dev/alice/foo );
nok qw( baseroot u3 D master );
nok qw( baseroot u3 D notmaster );
nok qw( baseroot u3 D refs/tags/boo );
nok qw( baseroot u3 D refs/tags/v1 );
nok qw( baseroot u3 D dev/u3/foo );
nok qw( baseroot u3 D refs/tags/dev/u3/foo );
nok qw( baseroot u3 D dev/alice/foo );
nok qw( baseroot u3 D refs/tags/dev/alice/foo );

ok  qw( baseroot u4 R );
nok qw( baseroot u4 W master );
nok qw( baseroot u4 W notmaster );
nok qw( baseroot u4 W refs/tags/boo );
nok qw( baseroot u4 W refs/tags/v1 );
nok qw( baseroot u4 W dev/u4/foo );
nok qw( baseroot u4 W refs/tags/dev/u4/foo );
nok qw( baseroot u4 W dev/alice/foo );
nok qw( baseroot u4 W refs/tags/dev/alice/foo );
nok qw( baseroot u4 + master );
nok qw( baseroot u4 + notmaster );
nok qw( baseroot u4 + refs/tags/boo );
nok qw( baseroot u4 + refs/tags/v1 );
nok qw( baseroot u4 + dev/u4/foo );
nok qw( baseroot u4 + refs/tags/dev/u4/foo );
nok qw( baseroot u4 + dev/alice/foo );
nok qw( baseroot u4 + refs/tags/dev/alice/foo );
nok qw( baseroot u4 C master );
nok qw( baseroot u4 C notmaster );
nok qw( baseroot u4 C refs/tags/boo );
nok qw( baseroot u4 C refs/tags/v1 );
nok qw( baseroot u4 C dev/u4/foo );
nok qw( baseroot u4 C refs/tags/dev/u4/foo );
nok qw( baseroot u4 C dev/alice/foo );
nok qw( baseroot u4 C refs/tags/dev/alice/foo );
nok qw( baseroot u4 D master );
nok qw( baseroot u4 D notmaster );
nok qw( baseroot u4 D refs/tags/boo );
nok qw( baseroot u4 D refs/tags/v1 );
nok qw( baseroot u4 D dev/u4/foo );
nok qw( baseroot u4 D refs/tags/dev/u4/foo );
nok qw( baseroot u4 D dev/alice/foo );
nok qw( baseroot u4 D refs/tags/dev/alice/foo );

nok qw( baseroot u5 R );
nok qw( baseroot u5 W master );
nok qw( baseroot u5 W notmaster );
nok qw( baseroot u5 W refs/tags/boo );
nok qw( baseroot u5 W refs/tags/v1 );
nok qw( baseroot u5 W dev/u5/foo );
nok qw( baseroot u5 W refs/tags/dev/u5/foo );
nok qw( baseroot u5 W dev/alice/foo );
nok qw( baseroot u5 W refs/tags/dev/alice/foo );
nok qw( baseroot u5 + master );
nok qw( baseroot u5 + notmaster );
nok qw( baseroot u5 + refs/tags/boo );
nok qw( baseroot u5 + refs/tags/v1 );
nok qw( baseroot u5 + dev/u5/foo );
nok qw( baseroot u5 + refs/tags/dev/u5/foo );
nok qw( baseroot u5 + dev/alice/foo );
nok qw( baseroot u5 + refs/tags/dev/alice/foo );
nok qw( baseroot u5 C master );
nok qw( baseroot u5 C notmaster );
nok qw( baseroot u5 C refs/tags/boo );
nok qw( baseroot u5 C refs/tags/v1 );
nok qw( baseroot u5 C dev/u5/foo );
nok qw( baseroot u5 C refs/tags/dev/u5/foo );
nok qw( baseroot u5 C dev/alice/foo );
nok qw( baseroot u5 C refs/tags/dev/alice/foo );
nok qw( baseroot u5 D master );
nok qw( baseroot u5 D notmaster );
nok qw( baseroot u5 D refs/tags/boo );
nok qw( baseroot u5 D refs/tags/v1 );
nok qw( baseroot u5 D dev/u5/foo );
nok qw( baseroot u5 D refs/tags/dev/u5/foo );
nok qw( baseroot u5 D dev/alice/foo );
nok qw( baseroot u5 D refs/tags/dev/alice/foo );

nok qw( baseroot u6 R );
nok qw( baseroot u6 W master );
nok qw( baseroot u6 W notmaster );
nok qw( baseroot u6 W refs/tags/boo );
nok qw( baseroot u6 W refs/tags/v1 );
nok qw( baseroot u6 W dev/u6/foo );
nok qw( baseroot u6 W refs/tags/dev/u6/foo );
nok qw( baseroot u6 W dev/alice/foo );
nok qw( baseroot u6 W refs/tags/dev/alice/foo );
nok qw( baseroot u6 + master );
nok qw( baseroot u6 + notmaster );
nok qw( baseroot u6 + refs/tags/boo );
nok qw( baseroot u6 + refs/tags/v1 );
nok qw( baseroot u6 + dev/u6/foo );
nok qw( baseroot u6 + refs/tags/dev/u6/foo );
nok qw( baseroot u6 + dev/alice/foo );
nok qw( baseroot u6 + refs/tags/dev/alice/foo );
nok qw( baseroot u6 C master );
nok qw( baseroot u6 C notmaster );
nok qw( baseroot u6 C refs/tags/boo );
nok qw( baseroot u6 C refs/tags/v1 );
nok qw( baseroot u6 C dev/u6/foo );
nok qw( baseroot u6 C refs/tags/dev/u6/foo );
nok qw( baseroot u6 C dev/alice/foo );
nok qw( baseroot u6 C refs/tags/dev/alice/foo );
nok qw( baseroot u6 D master );
nok qw( baseroot u6 D notmaster );
nok qw( baseroot u6 D refs/tags/boo );
nok qw( baseroot u6 D refs/tags/v1 );
nok qw( baseroot u6 D dev/u6/foo );
nok qw( baseroot u6 D refs/tags/dev/u6/foo );
nok qw( baseroot u6 D dev/alice/foo );
nok qw( baseroot u6 D refs/tags/dev/alice/foo );

nok qw( basepers admin R );
nok qw( basepers admin W master );
nok qw( basepers admin W notmaster );
nok qw( basepers admin W refs/tags/boo );
nok qw( basepers admin W refs/tags/v1 );
nok qw( basepers admin W dev/admin/foo );
nok qw( basepers admin W refs/tags/dev/admin/foo );
nok qw( basepers admin W dev/alice/foo );
nok qw( basepers admin W refs/tags/dev/alice/foo );
nok qw( basepers admin + master );
nok qw( basepers admin + notmaster );
nok qw( basepers admin + refs/tags/boo );
nok qw( basepers admin + refs/tags/v1 );
nok qw( basepers admin + dev/admin/foo );
nok qw( basepers admin + refs/tags/dev/admin/foo );
nok qw( basepers admin + dev/alice/foo );
nok qw( basepers admin + refs/tags/dev/alice/foo );
nok qw( basepers admin C master );
nok qw( basepers admin C notmaster );
nok qw( basepers admin C refs/tags/boo );
nok qw( basepers admin C refs/tags/v1 );
nok qw( basepers admin C dev/admin/foo );
nok qw( basepers admin C refs/tags/dev/admin/foo );
nok qw( basepers admin C dev/alice/foo );
nok qw( basepers admin C refs/tags/dev/alice/foo );
nok qw( basepers admin D master );
nok qw( basepers admin D notmaster );
nok qw( basepers admin D refs/tags/boo );
nok qw( basepers admin D refs/tags/v1 );
nok qw( basepers admin D dev/admin/foo );
nok qw( basepers admin D refs/tags/dev/admin/foo );
nok qw( basepers admin D dev/alice/foo );
nok qw( basepers admin D refs/tags/dev/alice/foo );

ok  qw( basepers u1 R );
ok  qw( basepers u1 W master );
ok  qw( basepers u1 W notmaster );
ok  qw( basepers u1 W refs/tags/boo );
ok  qw( basepers u1 W refs/tags/v1 );
ok  qw( basepers u1 W dev/u1/foo );
ok  qw( basepers u1 W refs/tags/dev/u1/foo );
nok qw( basepers u1 W dev/alice/foo );
nok qw( basepers u1 W refs/tags/dev/alice/foo );
ok  qw( basepers u1 + master );
ok  qw( basepers u1 + notmaster );
ok  qw( basepers u1 + refs/tags/boo );
ok  qw( basepers u1 + refs/tags/v1 );
ok  qw( basepers u1 + dev/u1/foo );
ok  qw( basepers u1 + refs/tags/dev/u1/foo );
nok qw( basepers u1 + dev/alice/foo );
nok qw( basepers u1 + refs/tags/dev/alice/foo );
ok  qw( basepers u1 C master );
ok  qw( basepers u1 C notmaster );
ok  qw( basepers u1 C refs/tags/boo );
ok  qw( basepers u1 C refs/tags/v1 );
ok  qw( basepers u1 C dev/u1/foo );
ok  qw( basepers u1 C refs/tags/dev/u1/foo );
nok qw( basepers u1 C dev/alice/foo );
nok qw( basepers u1 C refs/tags/dev/alice/foo );
ok  qw( basepers u1 D master );
ok  qw( basepers u1 D notmaster );
ok  qw( basepers u1 D refs/tags/boo );
ok  qw( basepers u1 D refs/tags/v1 );
ok  qw( basepers u1 D dev/u1/foo );
ok  qw( basepers u1 D refs/tags/dev/u1/foo );
nok qw( basepers u1 D dev/alice/foo );
nok qw( basepers u1 D refs/tags/dev/alice/foo );

ok  qw( basepers u2 R );
ok  qw( basepers u2 W master );
ok  qw( basepers u2 W notmaster );
ok  qw( basepers u2 W refs/tags/boo );
ok  qw( basepers u2 W refs/tags/v1 );
ok  qw( basepers u2 W dev/u2/foo );
ok  qw( basepers u2 W refs/tags/dev/u2/foo );
nok qw( basepers u2 W dev/alice/foo );
nok qw( basepers u2 W refs/tags/dev/alice/foo );
nok qw( basepers u2 + master );
nok qw( basepers u2 + notmaster );
nok qw( basepers u2 + refs/tags/boo );
nok qw( basepers u2 + refs/tags/v1 );
ok  qw( basepers u2 + dev/u2/foo );
ok  qw( basepers u2 + refs/tags/dev/u2/foo );
nok qw( basepers u2 + dev/alice/foo );
nok qw( basepers u2 + refs/tags/dev/alice/foo );
ok  qw( basepers u2 C master );
ok  qw( basepers u2 C notmaster );
ok  qw( basepers u2 C refs/tags/boo );
ok  qw( basepers u2 C refs/tags/v1 );
ok  qw( basepers u2 C dev/u2/foo );
ok  qw( basepers u2 C refs/tags/dev/u2/foo );
nok qw( basepers u2 C dev/alice/foo );
nok qw( basepers u2 C refs/tags/dev/alice/foo );
nok qw( basepers u2 D master );
nok qw( basepers u2 D notmaster );
nok qw( basepers u2 D refs/tags/boo );
nok qw( basepers u2 D refs/tags/v1 );
ok  qw( basepers u2 D dev/u2/foo );
ok  qw( basepers u2 D refs/tags/dev/u2/foo );
nok qw( basepers u2 D dev/alice/foo );
nok qw( basepers u2 D refs/tags/dev/alice/foo );

ok  qw( basepers u3 R );
nok qw( basepers u3 W master );
ok  qw( basepers u3 W notmaster );
ok  qw( basepers u3 W refs/tags/boo );
ok  qw( basepers u3 W refs/tags/v1 );
ok  qw( basepers u3 W dev/u3/foo );
ok  qw( basepers u3 W refs/tags/dev/u3/foo );
nok qw( basepers u3 W dev/alice/foo );
nok qw( basepers u3 W refs/tags/dev/alice/foo );
nok qw( basepers u3 + master );
nok qw( basepers u3 + notmaster );
nok qw( basepers u3 + refs/tags/boo );
nok qw( basepers u3 + refs/tags/v1 );
ok  qw( basepers u3 + dev/u3/foo );
ok  qw( basepers u3 + refs/tags/dev/u3/foo );
nok qw( basepers u3 + dev/alice/foo );
nok qw( basepers u3 + refs/tags/dev/alice/foo );
nok qw( basepers u3 C master );
ok  qw( basepers u3 C notmaster );
ok  qw( basepers u3 C refs/tags/boo );
ok  qw( basepers u3 C refs/tags/v1 );
ok  qw( basepers u3 C dev/u3/foo );
ok  qw( basepers u3 C refs/tags/dev/u3/foo );
nok qw( basepers u3 C dev/alice/foo );
nok qw( basepers u3 C refs/tags/dev/alice/foo );
nok qw( basepers u3 D master );
nok qw( basepers u3 D notmaster );
nok qw( basepers u3 D refs/tags/boo );
nok qw( basepers u3 D refs/tags/v1 );
ok  qw( basepers u3 D dev/u3/foo );
ok  qw( basepers u3 D refs/tags/dev/u3/foo );
nok qw( basepers u3 D dev/alice/foo );
nok qw( basepers u3 D refs/tags/dev/alice/foo );

ok  qw( basepers u4 R );
nok qw( basepers u4 W master );
nok qw( basepers u4 W notmaster );
nok qw( basepers u4 W refs/tags/boo );
nok qw( basepers u4 W refs/tags/v1 );
nok qw( basepers u4 W dev/u4/foo );
nok qw( basepers u4 W refs/tags/dev/u4/foo );
nok qw( basepers u4 W dev/alice/foo );
nok qw( basepers u4 W refs/tags/dev/alice/foo );
nok qw( basepers u4 + master );
nok qw( basepers u4 + notmaster );
nok qw( basepers u4 + refs/tags/boo );
nok qw( basepers u4 + refs/tags/v1 );
nok qw( basepers u4 + dev/u4/foo );
nok qw( basepers u4 + refs/tags/dev/u4/foo );
nok qw( basepers u4 + dev/alice/foo );
nok qw( basepers u4 + refs/tags/dev/alice/foo );
nok qw( basepers u4 C master );
nok qw( basepers u4 C notmaster );
nok qw( basepers u4 C refs/tags/boo );
nok qw( basepers u4 C refs/tags/v1 );
nok qw( basepers u4 C dev/u4/foo );
nok qw( basepers u4 C refs/tags/dev/u4/foo );
nok qw( basepers u4 C dev/alice/foo );
nok qw( basepers u4 C refs/tags/dev/alice/foo );
nok qw( basepers u4 D master );
nok qw( basepers u4 D notmaster );
nok qw( basepers u4 D refs/tags/boo );
nok qw( basepers u4 D refs/tags/v1 );
nok qw( basepers u4 D dev/u4/foo );
nok qw( basepers u4 D refs/tags/dev/u4/foo );
nok qw( basepers u4 D dev/alice/foo );
nok qw( basepers u4 D refs/tags/dev/alice/foo );

ok  qw( basepers u5 R );
nok qw( basepers u5 W master );
nok qw( basepers u5 W notmaster );
nok qw( basepers u5 W refs/tags/boo );
nok qw( basepers u5 W refs/tags/v1 );
ok  qw( basepers u5 W dev/u5/foo );
ok  qw( basepers u5 W refs/tags/dev/u5/foo );
nok qw( basepers u5 W dev/alice/foo );
nok qw( basepers u5 W refs/tags/dev/alice/foo );
nok qw( basepers u5 + master );
nok qw( basepers u5 + notmaster );
nok qw( basepers u5 + refs/tags/boo );
nok qw( basepers u5 + refs/tags/v1 );
ok  qw( basepers u5 + dev/u5/foo );
ok  qw( basepers u5 + refs/tags/dev/u5/foo );
nok qw( basepers u5 + dev/alice/foo );
nok qw( basepers u5 + refs/tags/dev/alice/foo );
nok qw( basepers u5 C master );
nok qw( basepers u5 C notmaster );
nok qw( basepers u5 C refs/tags/boo );
nok qw( basepers u5 C refs/tags/v1 );
ok  qw( basepers u5 C dev/u5/foo );
ok  qw( basepers u5 C refs/tags/dev/u5/foo );
nok qw( basepers u5 C dev/alice/foo );
nok qw( basepers u5 C refs/tags/dev/alice/foo );
nok qw( basepers u5 D master );
nok qw( basepers u5 D notmaster );
nok qw( basepers u5 D refs/tags/boo );
nok qw( basepers u5 D refs/tags/v1 );
ok  qw( basepers u5 D dev/u5/foo );
ok  qw( basepers u5 D refs/tags/dev/u5/foo );
nok qw( basepers u5 D dev/alice/foo );
nok qw( basepers u5 D refs/tags/dev/alice/foo );

ok  qw( basepers u6 R );
nok qw( basepers u6 W master );
nok qw( basepers u6 W notmaster );
nok qw( basepers u6 W refs/tags/boo );
nok qw( basepers u6 W refs/tags/v1 );
ok  qw( basepers u6 W dev/u6/foo );
ok  qw( basepers u6 W refs/tags/dev/u6/foo );
nok qw( basepers u6 W dev/alice/foo );
nok qw( basepers u6 W refs/tags/dev/alice/foo );
nok qw( basepers u6 + master );
nok qw( basepers u6 + notmaster );
nok qw( basepers u6 + refs/tags/boo );
nok qw( basepers u6 + refs/tags/v1 );
ok  qw( basepers u6 + dev/u6/foo );
ok  qw( basepers u6 + refs/tags/dev/u6/foo );
nok qw( basepers u6 + dev/alice/foo );
nok qw( basepers u6 + refs/tags/dev/alice/foo );
nok qw( basepers u6 C master );
nok qw( basepers u6 C notmaster );
nok qw( basepers u6 C refs/tags/boo );
nok qw( basepers u6 C refs/tags/v1 );
ok  qw( basepers u6 C dev/u6/foo );
ok  qw( basepers u6 C refs/tags/dev/u6/foo );
nok qw( basepers u6 C dev/alice/foo );
nok qw( basepers u6 C refs/tags/dev/alice/foo );
nok qw( basepers u6 D master );
nok qw( basepers u6 D notmaster );
nok qw( basepers u6 D refs/tags/boo );
nok qw( basepers u6 D refs/tags/v1 );
ok  qw( basepers u6 D dev/u6/foo );
ok  qw( basepers u6 D refs/tags/dev/u6/foo );
nok qw( basepers u6 D dev/alice/foo );
nok qw( basepers u6 D refs/tags/dev/alice/foo );

nok qw( baserel admin R );
nok qw( baserel admin W master );
nok qw( baserel admin W notmaster );
nok qw( baserel admin W refs/tags/boo );
nok qw( baserel admin W refs/tags/v1 );
nok qw( baserel admin W dev/admin/foo );
nok qw( baserel admin W refs/tags/dev/admin/foo );
nok qw( baserel admin W dev/alice/foo );
nok qw( baserel admin W refs/tags/dev/alice/foo );
nok qw( baserel admin + master );
nok qw( baserel admin + notmaster );
nok qw( baserel admin + refs/tags/boo );
nok qw( baserel admin + refs/tags/v1 );
nok qw( baserel admin + dev/admin/foo );
nok qw( baserel admin + refs/tags/dev/admin/foo );
nok qw( baserel admin + dev/alice/foo );
nok qw( baserel admin + refs/tags/dev/alice/foo );
nok qw( baserel admin C master );
nok qw( baserel admin C notmaster );
nok qw( baserel admin C refs/tags/boo );
nok qw( baserel admin C refs/tags/v1 );
nok qw( baserel admin C dev/admin/foo );
nok qw( baserel admin C refs/tags/dev/admin/foo );
nok qw( baserel admin C dev/alice/foo );
nok qw( baserel admin C refs/tags/dev/alice/foo );
nok qw( baserel admin D master );
nok qw( baserel admin D notmaster );
nok qw( baserel admin D refs/tags/boo );
nok qw( baserel admin D refs/tags/v1 );
nok qw( baserel admin D dev/admin/foo );
nok qw( baserel admin D refs/tags/dev/admin/foo );
nok qw( baserel admin D dev/alice/foo );
nok qw( baserel admin D refs/tags/dev/alice/foo );

ok  qw( baserel u1 R );
ok  qw( baserel u1 W master );
ok  qw( baserel u1 W notmaster );
ok  qw( baserel u1 W refs/tags/boo );
nok qw( baserel u1 W refs/tags/v1 );
ok  qw( baserel u1 W dev/u1/foo );
ok  qw( baserel u1 W refs/tags/dev/u1/foo );
ok  qw( baserel u1 W dev/alice/foo );
ok  qw( baserel u1 W refs/tags/dev/alice/foo );
ok  qw( baserel u1 + master );
ok  qw( baserel u1 + notmaster );
ok  qw( baserel u1 + refs/tags/boo );
nok qw( baserel u1 + refs/tags/v1 );
ok  qw( baserel u1 + dev/u1/foo );
ok  qw( baserel u1 + refs/tags/dev/u1/foo );
ok  qw( baserel u1 + dev/alice/foo );
ok  qw( baserel u1 + refs/tags/dev/alice/foo );
ok  qw( baserel u1 C master );
ok  qw( baserel u1 C notmaster );
ok  qw( baserel u1 C refs/tags/boo );
nok qw( baserel u1 C refs/tags/v1 );
ok  qw( baserel u1 C dev/u1/foo );
ok  qw( baserel u1 C refs/tags/dev/u1/foo );
ok  qw( baserel u1 C dev/alice/foo );
ok  qw( baserel u1 C refs/tags/dev/alice/foo );
ok  qw( baserel u1 D master );
ok  qw( baserel u1 D notmaster );
ok  qw( baserel u1 D refs/tags/boo );
nok qw( baserel u1 D refs/tags/v1 );
ok  qw( baserel u1 D dev/u1/foo );
ok  qw( baserel u1 D refs/tags/dev/u1/foo );
ok  qw( baserel u1 D dev/alice/foo );
ok  qw( baserel u1 D refs/tags/dev/alice/foo );

ok  qw( baserel u2 R );
ok  qw( baserel u2 W master );
ok  qw( baserel u2 W notmaster );
ok  qw( baserel u2 W refs/tags/boo );
nok qw( baserel u2 W refs/tags/v1 );
ok  qw( baserel u2 W dev/u2/foo );
ok  qw( baserel u2 W refs/tags/dev/u2/foo );
ok  qw( baserel u2 W dev/alice/foo );
ok  qw( baserel u2 W refs/tags/dev/alice/foo );
nok qw( baserel u2 + master );
nok qw( baserel u2 + notmaster );
nok qw( baserel u2 + refs/tags/boo );
nok qw( baserel u2 + refs/tags/v1 );
nok qw( baserel u2 + dev/u2/foo );
nok qw( baserel u2 + refs/tags/dev/u2/foo );
nok qw( baserel u2 + dev/alice/foo );
nok qw( baserel u2 + refs/tags/dev/alice/foo );
ok  qw( baserel u2 C master );
ok  qw( baserel u2 C notmaster );
ok  qw( baserel u2 C refs/tags/boo );
nok qw( baserel u2 C refs/tags/v1 );
ok  qw( baserel u2 C dev/u2/foo );
ok  qw( baserel u2 C refs/tags/dev/u2/foo );
ok  qw( baserel u2 C dev/alice/foo );
ok  qw( baserel u2 C refs/tags/dev/alice/foo );
nok qw( baserel u2 D master );
nok qw( baserel u2 D notmaster );
nok qw( baserel u2 D refs/tags/boo );
nok qw( baserel u2 D refs/tags/v1 );
nok qw( baserel u2 D dev/u2/foo );
nok qw( baserel u2 D refs/tags/dev/u2/foo );
nok qw( baserel u2 D dev/alice/foo );
nok qw( baserel u2 D refs/tags/dev/alice/foo );

ok  qw( baserel u3 R );
nok qw( baserel u3 W master );
ok  qw( baserel u3 W notmaster );
ok  qw( baserel u3 W refs/tags/boo );
nok qw( baserel u3 W refs/tags/v1 );
ok  qw( baserel u3 W dev/u3/foo );
ok  qw( baserel u3 W refs/tags/dev/u3/foo );
ok  qw( baserel u3 W dev/alice/foo );
ok  qw( baserel u3 W refs/tags/dev/alice/foo );
nok qw( baserel u3 + master );
nok qw( baserel u3 + notmaster );
nok qw( baserel u3 + refs/tags/boo );
nok qw( baserel u3 + refs/tags/v1 );
nok qw( baserel u3 + dev/u3/foo );
nok qw( baserel u3 + refs/tags/dev/u3/foo );
nok qw( baserel u3 + dev/alice/foo );
nok qw( baserel u3 + refs/tags/dev/alice/foo );
nok qw( baserel u3 C master );
ok  qw( baserel u3 C notmaster );
ok  qw( baserel u3 C refs/tags/boo );
nok qw( baserel u3 C refs/tags/v1 );
ok  qw( baserel u3 C dev/u3/foo );
ok  qw( baserel u3 C refs/tags/dev/u3/foo );
ok  qw( baserel u3 C dev/alice/foo );
ok  qw( baserel u3 C refs/tags/dev/alice/foo );
nok qw( baserel u3 D master );
nok qw( baserel u3 D notmaster );
nok qw( baserel u3 D refs/tags/boo );
nok qw( baserel u3 D refs/tags/v1 );
nok qw( baserel u3 D dev/u3/foo );
nok qw( baserel u3 D refs/tags/dev/u3/foo );
nok qw( baserel u3 D dev/alice/foo );
nok qw( baserel u3 D refs/tags/dev/alice/foo );

ok  qw( baserel u4 R );
nok qw( baserel u4 W master );
nok qw( baserel u4 W notmaster );
nok qw( baserel u4 W refs/tags/boo );
nok qw( baserel u4 W refs/tags/v1 );
nok qw( baserel u4 W dev/u4/foo );
nok qw( baserel u4 W refs/tags/dev/u4/foo );
nok qw( baserel u4 W dev/alice/foo );
nok qw( baserel u4 W refs/tags/dev/alice/foo );
nok qw( baserel u4 + master );
nok qw( baserel u4 + notmaster );
nok qw( baserel u4 + refs/tags/boo );
nok qw( baserel u4 + refs/tags/v1 );
nok qw( baserel u4 + dev/u4/foo );
nok qw( baserel u4 + refs/tags/dev/u4/foo );
nok qw( baserel u4 + dev/alice/foo );
nok qw( baserel u4 + refs/tags/dev/alice/foo );
nok qw( baserel u4 C master );
nok qw( baserel u4 C notmaster );
nok qw( baserel u4 C refs/tags/boo );
nok qw( baserel u4 C refs/tags/v1 );
nok qw( baserel u4 C dev/u4/foo );
nok qw( baserel u4 C refs/tags/dev/u4/foo );
nok qw( baserel u4 C dev/alice/foo );
nok qw( baserel u4 C refs/tags/dev/alice/foo );
nok qw( baserel u4 D master );
nok qw( baserel u4 D notmaster );
nok qw( baserel u4 D refs/tags/boo );
nok qw( baserel u4 D refs/tags/v1 );
nok qw( baserel u4 D dev/u4/foo );
nok qw( baserel u4 D refs/tags/dev/u4/foo );
nok qw( baserel u4 D dev/alice/foo );
nok qw( baserel u4 D refs/tags/dev/alice/foo );

ok  qw( baserel u5 R );
nok qw( baserel u5 W master );
nok qw( baserel u5 W notmaster );
nok qw( baserel u5 W refs/tags/boo );
nok qw( baserel u5 W refs/tags/v1 );
nok qw( baserel u5 W dev/u5/foo );
nok qw( baserel u5 W refs/tags/dev/u5/foo );
nok qw( baserel u5 W dev/alice/foo );
nok qw( baserel u5 W refs/tags/dev/alice/foo );
nok qw( baserel u5 + master );
nok qw( baserel u5 + notmaster );
nok qw( baserel u5 + refs/tags/boo );
nok qw( baserel u5 + refs/tags/v1 );
nok qw( baserel u5 + dev/u5/foo );
nok qw( baserel u5 + refs/tags/dev/u5/foo );
nok qw( baserel u5 + dev/alice/foo );
nok qw( baserel u5 + refs/tags/dev/alice/foo );
nok qw( baserel u5 C master );
nok qw( baserel u5 C notmaster );
nok qw( baserel u5 C refs/tags/boo );
nok qw( baserel u5 C refs/tags/v1 );
nok qw( baserel u5 C dev/u5/foo );
nok qw( baserel u5 C refs/tags/dev/u5/foo );
nok qw( baserel u5 C dev/alice/foo );
nok qw( baserel u5 C refs/tags/dev/alice/foo );
nok qw( baserel u5 D master );
nok qw( baserel u5 D notmaster );
nok qw( baserel u5 D refs/tags/boo );
nok qw( baserel u5 D refs/tags/v1 );
nok qw( baserel u5 D dev/u5/foo );
nok qw( baserel u5 D refs/tags/dev/u5/foo );
nok qw( baserel u5 D dev/alice/foo );
nok qw( baserel u5 D refs/tags/dev/alice/foo );

nok qw( baserel u6 R );
nok qw( baserel u6 W master );
nok qw( baserel u6 W notmaster );
nok qw( baserel u6 W refs/tags/boo );
nok qw( baserel u6 W refs/tags/v1 );
nok qw( baserel u6 W dev/u6/foo );
nok qw( baserel u6 W refs/tags/dev/u6/foo );
nok qw( baserel u6 W dev/alice/foo );
nok qw( baserel u6 W refs/tags/dev/alice/foo );
nok qw( baserel u6 + master );
nok qw( baserel u6 + notmaster );
nok qw( baserel u6 + refs/tags/boo );
nok qw( baserel u6 + refs/tags/v1 );
nok qw( baserel u6 + dev/u6/foo );
nok qw( baserel u6 + refs/tags/dev/u6/foo );
nok qw( baserel u6 + dev/alice/foo );
nok qw( baserel u6 + refs/tags/dev/alice/foo );
nok qw( baserel u6 C master );
nok qw( baserel u6 C notmaster );
nok qw( baserel u6 C refs/tags/boo );
nok qw( baserel u6 C refs/tags/v1 );
nok qw( baserel u6 C dev/u6/foo );
nok qw( baserel u6 C refs/tags/dev/u6/foo );
nok qw( baserel u6 C dev/alice/foo );
nok qw( baserel u6 C refs/tags/dev/alice/foo );
nok qw( baserel u6 D master );
nok qw( baserel u6 D notmaster );
nok qw( baserel u6 D refs/tags/boo );
nok qw( baserel u6 D refs/tags/v1 );
nok qw( baserel u6 D dev/u6/foo );
nok qw( baserel u6 D refs/tags/dev/u6/foo );
nok qw( baserel u6 D dev/alice/foo );
nok qw( baserel u6 D refs/tags/dev/alice/foo );

ok  qw( baseall admin R );
ok  qw( baseall admin W master );
ok  qw( baseall admin W notmaster );
ok  qw( baseall admin W refs/tags/boo );
ok  qw( baseall admin W refs/tags/v1 );
ok  qw( baseall admin W dev/admin/foo );
ok  qw( baseall admin W refs/tags/dev/admin/foo );
ok  qw( baseall admin W dev/alice/foo );
ok  qw( baseall admin W refs/tags/dev/alice/foo );
ok  qw( baseall admin + master );
ok  qw( baseall admin + notmaster );
ok  qw( baseall admin + refs/tags/boo );
ok  qw( baseall admin + refs/tags/v1 );
ok  qw( baseall admin + dev/admin/foo );
ok  qw( baseall admin + refs/tags/dev/admin/foo );
ok  qw( baseall admin + dev/alice/foo );
ok  qw( baseall admin + refs/tags/dev/alice/foo );
ok  qw( baseall admin C master );
ok  qw( baseall admin C notmaster );
ok  qw( baseall admin C refs/tags/boo );
ok  qw( baseall admin C refs/tags/v1 );
ok  qw( baseall admin C dev/admin/foo );
ok  qw( baseall admin C refs/tags/dev/admin/foo );
ok  qw( baseall admin C dev/alice/foo );
ok  qw( baseall admin C refs/tags/dev/alice/foo );
ok  qw( baseall admin D master );
ok  qw( baseall admin D notmaster );
ok  qw( baseall admin D refs/tags/boo );
ok  qw( baseall admin D refs/tags/v1 );
ok  qw( baseall admin D dev/admin/foo );
ok  qw( baseall admin D refs/tags/dev/admin/foo );
ok  qw( baseall admin D dev/alice/foo );
ok  qw( baseall admin D refs/tags/dev/alice/foo );

ok  qw( baseall u1 R );
ok  qw( baseall u1 W master );
ok  qw( baseall u1 W notmaster );
ok  qw( baseall u1 W refs/tags/boo );
nok qw( baseall u1 W refs/tags/v1 );
ok  qw( baseall u1 W dev/u1/foo );
ok  qw( baseall u1 W refs/tags/dev/u1/foo );
nok qw( baseall u1 W dev/alice/foo );
nok qw( baseall u1 W refs/tags/dev/alice/foo );
ok  qw( baseall u1 + master );
ok  qw( baseall u1 + notmaster );
ok  qw( baseall u1 + refs/tags/boo );
nok qw( baseall u1 + refs/tags/v1 );
ok  qw( baseall u1 + dev/u1/foo );
ok  qw( baseall u1 + refs/tags/dev/u1/foo );
nok qw( baseall u1 + dev/alice/foo );
nok qw( baseall u1 + refs/tags/dev/alice/foo );
ok  qw( baseall u1 C master );
ok  qw( baseall u1 C notmaster );
ok  qw( baseall u1 C refs/tags/boo );
nok qw( baseall u1 C refs/tags/v1 );
ok  qw( baseall u1 C dev/u1/foo );
ok  qw( baseall u1 C refs/tags/dev/u1/foo );
nok qw( baseall u1 C dev/alice/foo );
nok qw( baseall u1 C refs/tags/dev/alice/foo );
ok  qw( baseall u1 D master );
ok  qw( baseall u1 D notmaster );
ok  qw( baseall u1 D refs/tags/boo );
nok qw( baseall u1 D refs/tags/v1 );
ok  qw( baseall u1 D dev/u1/foo );
ok  qw( baseall u1 D refs/tags/dev/u1/foo );
nok qw( baseall u1 D dev/alice/foo );
nok qw( baseall u1 D refs/tags/dev/alice/foo );

ok  qw( baseall u2 R );
ok  qw( baseall u2 W master );
ok  qw( baseall u2 W notmaster );
ok  qw( baseall u2 W refs/tags/boo );
nok qw( baseall u2 W refs/tags/v1 );
ok  qw( baseall u2 W dev/u2/foo );
ok  qw( baseall u2 W refs/tags/dev/u2/foo );
nok qw( baseall u2 W dev/alice/foo );
nok qw( baseall u2 W refs/tags/dev/alice/foo );
nok qw( baseall u2 + master );
nok qw( baseall u2 + notmaster );
nok qw( baseall u2 + refs/tags/boo );
nok qw( baseall u2 + refs/tags/v1 );
ok  qw( baseall u2 + dev/u2/foo );
ok  qw( baseall u2 + refs/tags/dev/u2/foo );
nok qw( baseall u2 + dev/alice/foo );
nok qw( baseall u2 + refs/tags/dev/alice/foo );
ok  qw( baseall u2 C master );
ok  qw( baseall u2 C notmaster );
ok  qw( baseall u2 C refs/tags/boo );
nok qw( baseall u2 C refs/tags/v1 );
ok  qw( baseall u2 C dev/u2/foo );
ok  qw( baseall u2 C refs/tags/dev/u2/foo );
nok qw( baseall u2 C dev/alice/foo );
nok qw( baseall u2 C refs/tags/dev/alice/foo );
nok qw( baseall u2 D master );
nok qw( baseall u2 D notmaster );
nok qw( baseall u2 D refs/tags/boo );
nok qw( baseall u2 D refs/tags/v1 );
ok  qw( baseall u2 D dev/u2/foo );
ok  qw( baseall u2 D refs/tags/dev/u2/foo );
nok qw( baseall u2 D dev/alice/foo );
nok qw( baseall u2 D refs/tags/dev/alice/foo );

ok  qw( baseall u3 R );
nok qw( baseall u3 W master );
ok  qw( baseall u3 W notmaster );
ok  qw( baseall u3 W refs/tags/boo );
nok qw( baseall u3 W refs/tags/v1 );
ok  qw( baseall u3 W dev/u3/foo );
ok  qw( baseall u3 W refs/tags/dev/u3/foo );
nok qw( baseall u3 W dev/alice/foo );
nok qw( baseall u3 W refs/tags/dev/alice/foo );
nok qw( baseall u3 + master );
nok qw( baseall u3 + notmaster );
nok qw( baseall u3 + refs/tags/boo );
nok qw( baseall u3 + refs/tags/v1 );
ok  qw( baseall u3 + dev/u3/foo );
ok  qw( baseall u3 + refs/tags/dev/u3/foo );
nok qw( baseall u3 + dev/alice/foo );
nok qw( baseall u3 + refs/tags/dev/alice/foo );
nok qw( baseall u3 C master );
ok  qw( baseall u3 C notmaster );
ok  qw( baseall u3 C refs/tags/boo );
nok qw( baseall u3 C refs/tags/v1 );
ok  qw( baseall u3 C dev/u3/foo );
ok  qw( baseall u3 C refs/tags/dev/u3/foo );
nok qw( baseall u3 C dev/alice/foo );
nok qw( baseall u3 C refs/tags/dev/alice/foo );
nok qw( baseall u3 D master );
nok qw( baseall u3 D notmaster );
nok qw( baseall u3 D refs/tags/boo );
nok qw( baseall u3 D refs/tags/v1 );
ok  qw( baseall u3 D dev/u3/foo );
ok  qw( baseall u3 D refs/tags/dev/u3/foo );
nok qw( baseall u3 D dev/alice/foo );
nok qw( baseall u3 D refs/tags/dev/alice/foo );

ok  qw( baseall u4 R );
nok qw( baseall u4 W master );
nok qw( baseall u4 W notmaster );
nok qw( baseall u4 W refs/tags/boo );
nok qw( baseall u4 W refs/tags/v1 );
nok qw( baseall u4 W dev/u4/foo );
nok qw( baseall u4 W refs/tags/dev/u4/foo );
nok qw( baseall u4 W dev/alice/foo );
nok qw( baseall u4 W refs/tags/dev/alice/foo );
nok qw( baseall u4 + master );
nok qw( baseall u4 + notmaster );
nok qw( baseall u4 + refs/tags/boo );
nok qw( baseall u4 + refs/tags/v1 );
nok qw( baseall u4 + dev/u4/foo );
nok qw( baseall u4 + refs/tags/dev/u4/foo );
nok qw( baseall u4 + dev/alice/foo );
nok qw( baseall u4 + refs/tags/dev/alice/foo );
nok qw( baseall u4 C master );
nok qw( baseall u4 C notmaster );
nok qw( baseall u4 C refs/tags/boo );
nok qw( baseall u4 C refs/tags/v1 );
nok qw( baseall u4 C dev/u4/foo );
nok qw( baseall u4 C refs/tags/dev/u4/foo );
nok qw( baseall u4 C dev/alice/foo );
nok qw( baseall u4 C refs/tags/dev/alice/foo );
nok qw( baseall u4 D master );
nok qw( baseall u4 D notmaster );
nok qw( baseall u4 D refs/tags/boo );
nok qw( baseall u4 D refs/tags/v1 );
nok qw( baseall u4 D dev/u4/foo );
nok qw( baseall u4 D refs/tags/dev/u4/foo );
nok qw( baseall u4 D dev/alice/foo );
nok qw( baseall u4 D refs/tags/dev/alice/foo );

ok  qw( baseall u5 R );
nok qw( baseall u5 W master );
nok qw( baseall u5 W notmaster );
nok qw( baseall u5 W refs/tags/boo );
nok qw( baseall u5 W refs/tags/v1 );
ok  qw( baseall u5 W dev/u5/foo );
ok  qw( baseall u5 W refs/tags/dev/u5/foo );
nok qw( baseall u5 W dev/alice/foo );
nok qw( baseall u5 W refs/tags/dev/alice/foo );
nok qw( baseall u5 + master );
nok qw( baseall u5 + notmaster );
nok qw( baseall u5 + refs/tags/boo );
nok qw( baseall u5 + refs/tags/v1 );
ok  qw( baseall u5 + dev/u5/foo );
ok  qw( baseall u5 + refs/tags/dev/u5/foo );
nok qw( baseall u5 + dev/alice/foo );
nok qw( baseall u5 + refs/tags/dev/alice/foo );
nok qw( baseall u5 C master );
nok qw( baseall u5 C notmaster );
nok qw( baseall u5 C refs/tags/boo );
nok qw( baseall u5 C refs/tags/v1 );
ok  qw( baseall u5 C dev/u5/foo );
ok  qw( baseall u5 C refs/tags/dev/u5/foo );
nok qw( baseall u5 C dev/alice/foo );
nok qw( baseall u5 C refs/tags/dev/alice/foo );
nok qw( baseall u5 D master );
nok qw( baseall u5 D notmaster );
nok qw( baseall u5 D refs/tags/boo );
nok qw( baseall u5 D refs/tags/v1 );
ok  qw( baseall u5 D dev/u5/foo );
ok  qw( baseall u5 D refs/tags/dev/u5/foo );
nok qw( baseall u5 D dev/alice/foo );
nok qw( baseall u5 D refs/tags/dev/alice/foo );

ok  qw( baseall u6 R );
nok qw( baseall u6 W master );
nok qw( baseall u6 W notmaster );
nok qw( baseall u6 W refs/tags/boo );
nok qw( baseall u6 W refs/tags/v1 );
ok  qw( baseall u6 W dev/u6/foo );
ok  qw( baseall u6 W refs/tags/dev/u6/foo );
nok qw( baseall u6 W dev/alice/foo );
nok qw( baseall u6 W refs/tags/dev/alice/foo );
nok qw( baseall u6 + master );
nok qw( baseall u6 + notmaster );
nok qw( baseall u6 + refs/tags/boo );
nok qw( baseall u6 + refs/tags/v1 );
ok  qw( baseall u6 + dev/u6/foo );
ok  qw( baseall u6 + refs/tags/dev/u6/foo );
nok qw( baseall u6 + dev/alice/foo );
nok qw( baseall u6 + refs/tags/dev/alice/foo );
nok qw( baseall u6 C master );
nok qw( baseall u6 C notmaster );
nok qw( baseall u6 C refs/tags/boo );
nok qw( baseall u6 C refs/tags/v1 );
ok  qw( baseall u6 C dev/u6/foo );
ok  qw( baseall u6 C refs/tags/dev/u6/foo );
nok qw( baseall u6 C dev/alice/foo );
nok qw( baseall u6 C refs/tags/dev/alice/foo );
nok qw( baseall u6 D master );
nok qw( baseall u6 D notmaster );
nok qw( baseall u6 D refs/tags/boo );
nok qw( baseall u6 D refs/tags/v1 );
ok  qw( baseall u6 D dev/u6/foo );
ok  qw( baseall u6 D refs/tags/dev/u6/foo );
nok qw( baseall u6 D dev/alice/foo );
nok qw( baseall u6 D refs/tags/dev/alice/foo );

