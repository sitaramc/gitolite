#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# testing the (separate) authkeys handler
# ----------------------------------------------------------------------

$ENV{GL_BINDIR} = "$ENV{PWD}/src";

my $ak = "$ENV{HOME}/.ssh/authorized_keys";
mkdir("$ENV{HOME}/.ssh", 0700) if not -d "$ENV{HOME}/.ssh";
my $kd = `gitolite query-rc -n GL_ADMIN_BASE` . "/keydir";

try "plan 49";

my $pgm = "gitolite ../triggers/post-compile/ssh-authkeys";

try "
    # prep
    rm -rf $ak;                 ok

    $pgm;                       ok
    mkdir $kd;                  ok
    cd $kd;                     ok
    $pgm;                       ok;     /authorized_keys missing/
                                        /creating/
    wc < $ak;                   ok;     /0 *0 *0/
    # some gl keys
    ssh-keygen -N '' -q -f alice -C alice
    ssh-keygen -N '' -q -f bob   -C bob
    ssh-keygen -N '' -q -f carol -C carol
    ssh-keygen -N '' -q -f dave  -C dave
    ssh-keygen -N '' -q -f eve   -C eve
    rm alice bob carol dave eve
    ls -a;                      ok;     /alice.pub/; /bob.pub/; /carol.pub/; /dave.pub/; /eve.pub/
    $pgm;                       ok;
    wc    < $ak;                ok;     /^ *7 .*/;
    grep gitolite $ak;          ok;     /start/
                                        /end/

    # some normal keys
    mv alice.pub $ak;           ok
    cat carol.pub >> $ak;       ok
    $pgm;                       ok;     /carol.pub duplicates.*non-gitolite key/
    wc < $ak;                   ok;     /^ *8 .*/;

    # moving normal keys up
    mv dave.pub dave
    $pgm;                       ok
    cat dave >> $ak;            ok
    grep -n dave $ak;           ok;     /8:ssh-rsa/
    mv dave dave.pub
    $pgm;                       ok;     /carol.pub duplicates.*non-gitolite key/
                                         /dave.pub duplicates.*non-gitolite key/
    grep -n dave $ak;           ok;     /3:ssh-rsa/

    # a bad key
    ls -al > bad.pub
    $pgm;                       !ok;    /fingerprinting failed for \\'keydir/bad.pub\\'/
    wc < $ak;                   ok;     /^ *9 .*/;
    # a good key doesn't get added
    ssh-keygen -N '' -q -f good
    $pgm;                       !ok;    /fingerprinting failed for \\'keydir/bad.pub\\'/
    wc < $ak;                   ok;     /^ *9 .*/;
    # till the bad key is removed
    rm bad.pub
    $pgm;                       ok;
    wc < $ak;                   ok;     /^ *10 .*/;

    # duplicate gl key
    cp bob.pub robert.pub
    $pgm;                       ok;     /robert.pub duplicates.*bob.pub/
";
