#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Easy;
use Gitolite::Test;
# put this after ::Easy because it chdirs away from where you were and the
# 'use lib "src"', not being absolute, fails

# smoke tests for Easy.pm
# ----------------------------------------------------------------------
# for a change these are actual perl tests, so not much call for tsh here,
# although I still need the basic infrastructure for setting up the repos and
# I still can't intermix this with perl's Test.pm or Test::More etc
sub ok { (+shift) ? print "ok\n" : print "not ok\n"; }
sub nok { (+shift) ? print "not ok\n" : print "ok\n"; }
sub msg { return unless $ENV{D}; print STDERR "#" . +shift . "\n"; }

try "plan 88";

try "
    cat $ENV{HOME}/.gitolite.rc
    perl s/GIT_CONFIG_KEYS.*/GIT_CONFIG_KEYS => '.*',/
    put $ENV{HOME}/.gitolite.rc
";

# basic push admin repo
confreset;confadd '
    repo gitolite-admin
        RW+     VREF/NAME/      =   admin
        RW+     VREF/NAME/u5/   =   u5

    repo aa
        RW+     =   u1
        RW      =   u2
        R       =   u4

        config for.aa   =   1

    repo cc/..*
        C       =   u4
        RW+     =   CREATOR u5
        R       =   u6

        config for.cc   =   1

    @oddguys = u1 u3 u5
    @evensout = u2 u4 u6

    # TODO
    repo cc/sub/..*
        config sub.cc   =   1
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

# valid_user() -- an internal function but still worth testing by itself first
eval { Gitolite::Easy::valid_user(); };
ok($@ =~ /FATAL.*GL_USER not set/);
$ENV{GL_USER} = "u2";
eval { Gitolite::Easy::valid_user(); };
nok($@ =~ /FATAL.*GL_USER not set/);

# is_admin
msg('is_admin');
$ENV{GL_USER} = "admin"; ok(is_admin());
$ENV{GL_USER} = "u5"; ok(is_admin());
$ENV{GL_USER} = "u2"; nok(is_admin());

# is_super_admin -- not sure how useful it is right now
msg('is_super_admin');
$ENV{GL_USER} = "admin"; ok( is_super_admin() );
$ENV{GL_USER} = "u5";    nok( is_super_admin() );
$ENV{GL_USER} = "u2";    nok( is_super_admin() );

# in_group
msg('in_group');
$ENV{GL_USER} = "u1"; ok( in_group('oddguys') );  nok( in_group('evensout') );
$ENV{GL_USER} = "u3"; ok( in_group('oddguys') );  nok( in_group('evensout') );
$ENV{GL_USER} = "u4"; nok( in_group('oddguys') ); ok( in_group('evensout') );
$ENV{GL_USER} = "u2"; nok( in_group('oddguys') ); ok( in_group('evensout') );

# owns
msg('owns');
try("glt ls-remote u4 cc/u4; /Initialized empty.*cc/u4/");
$ENV{GL_USER} = "u3"; nok( owns("cc/u3") ); nok( owns("cc/u4") );
$ENV{GL_USER} = "u4"; nok( owns("cc/u3") ); ok( owns("cc/u4") );
$ENV{GL_USER} = "u5"; nok( owns("cc/u3") ); nok( owns("cc/u4") );

# can_read
msg('can_read');
$ENV{GL_USER} = "u1"; ok(can_read("aa"));
$ENV{GL_USER} = "u2"; ok(can_read("aa"));
$ENV{GL_USER} = "u3"; nok(can_read("aa"));
$ENV{GL_USER} = "u4"; ok(can_read("aa"));

$ENV{GL_USER} = "u1"; nok(can_read("bb"));
$ENV{GL_USER} = "u2"; nok(can_read("bb"));
$ENV{GL_USER} = "u3"; nok(can_read("bb"));
$ENV{GL_USER} = "u4"; nok(can_read("bb"));

$ENV{GL_USER} = "u3"; nok(can_read("cc/u3"));
$ENV{GL_USER} = "u4"; nok(can_read("cc/u3"));
$ENV{GL_USER} = "u5"; nok(can_read("cc/u3"));
$ENV{GL_USER} = "u6"; nok(can_read("cc/u3"));

$ENV{GL_USER} = "u3"; nok(can_read("cc/u4"));
$ENV{GL_USER} = "u4"; ok(can_read("cc/u4"));
$ENV{GL_USER} = "u5"; ok(can_read("cc/u4"));
$ENV{GL_USER} = "u6"; ok(can_read("cc/u4"));

# can_write
msg('can_write');
$ENV{GL_USER} = "u1"; ok(can_write("aa"));
$ENV{GL_USER} = "u2"; ok(can_write("aa"));
$ENV{GL_USER} = "u3"; nok(can_write("aa"));
$ENV{GL_USER} = "u4"; nok(can_write("aa"));

$ENV{GL_USER} = "u1"; nok(can_write("bb"));
$ENV{GL_USER} = "u2"; nok(can_write("bb"));
$ENV{GL_USER} = "u3"; nok(can_write("bb"));
$ENV{GL_USER} = "u4"; nok(can_write("bb"));

$ENV{GL_USER} = "u3"; nok(can_write("cc/u3"));
$ENV{GL_USER} = "u4"; nok(can_write("cc/u3"));
$ENV{GL_USER} = "u5"; nok(can_write("cc/u3"));
$ENV{GL_USER} = "u6"; nok(can_write("cc/u3"));

$ENV{GL_USER} = "u3"; nok(can_write("cc/u4"));
$ENV{GL_USER} = "u4"; ok(can_write("cc/u4"));
$ENV{GL_USER} = "u5"; ok(can_write("cc/u4"));
$ENV{GL_USER} = "u6"; nok(can_write("cc/u4"));

# config
try("glt ls-remote u4 cc/sub/one; /Initialized empty.*cc/sub/one/");
try("glt ls-remote u4 cc/two; /Initialized empty.*cc/two/");
ok(1);
my @a;
@a = config("aa", "fo..aa");   ok($a[0] eq 'for.aa' and $a[1] eq '1');
@a = config("aa", "for.aa");   ok($a[0] eq 'for.aa' and $a[1] eq '1');
@a = config("aa", "fo\\..aa"); ok(scalar(@a) == 0);

@a = config("aa", "fo..cc");   ok(scalar(@a) == 0);
@a = config("aa", "for.cc");   ok(scalar(@a) == 0);
@a = config("aa", "fo\\..cc"); ok(scalar(@a) == 0);

@a = config("bb", "fo..aa");   ok(scalar(@a) == 0);
@a = config("bb", "for.aa");   ok(scalar(@a) == 0);
@a = config("bb", "fo\\..aa"); ok(scalar(@a) == 0);

@a = config("cc/u4", "fo..aa");   ok(scalar(@a) == 0);
@a = config("cc/u4", "for.aa");   ok(scalar(@a) == 0);
@a = config("cc/u4", "fo\\..aa"); ok(scalar(@a) == 0);

@a = config("cc/u4", "fo..cc");   ok($a[0] eq 'for.cc' and $a[1] eq '1');
@a = config("cc/u4", "for.cc");   ok($a[0] eq 'for.cc' and $a[1] eq '1');
@a = config("cc/u4", "fo\\..cc"); ok(scalar(@a) == 0);

@a = config("cc/two", "fo..cc");   ok($a[0] eq 'for.cc' and $a[1] eq '1');
@a = config("cc/two", "for.cc");   ok($a[0] eq 'for.cc' and $a[1] eq '1');
@a = config("cc/two", "fo\\..cc"); ok(scalar(@a) == 0);

@a = config("cc/sub/one", "fo..cc");   ok($a[0] eq 'for.cc' and $a[1] eq '1');
@a = config("cc/sub/one", "for.cc");   ok($a[0] eq 'for.cc' and $a[1] eq '1');
@a = config("cc/sub/one", "fo\\..cc"); ok(scalar(@a) == 0);

# TODO
# @a = config("cc/sub/one", "su..cc");   ok($a[0] eq 'sub.cc' and $a[1] eq '1');
# @a = config("cc/sub/one", "sub.cc");   ok($a[0] eq 'sub.cc' and $a[1] eq '1');
@a = config("cc/sub/one", "su\\..cc"); ok(scalar(@a) == 0);

