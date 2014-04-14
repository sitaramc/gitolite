#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;
use JSON;

# the info command
# ----------------------------------------------------------------------

try 'plan 162';

try "## info";

confreset;confadd '
    @t1 = t1
    repo    @t1
        RW              =   u1
        R               =   u2
    repo    t2
        RW  =               u2
        R   =               u1
    repo    t3
        RW  =   u3
        R   =   u4

    repo foo/..*
        C   =   u1
        RW  =   CREATOR u3
';

try "ADMIN_PUSH info; !/FATAL/" or die text();
try "
                                        /Initialized.*empty.*t1.git/
                                        /Initialized.*empty.*t2.git/
                                        /Initialized.*empty.*t3.git/
";

my $href;   # semi-global (or at least file scoped lexical!)

# testing for info -json is a bit unusual.  The actual tests are done within
# this test script itself, and we send Tsh just enough for it to decide if
# it's 'ok' or 'not ok' and print that.

try "glt info u1 -json; ok";
$href = from_json(text());
try "## u1 test_gs";
test_gs('u1');
try "## u1";
perm('foo/..*', 'r w C');
perm('testing', 'R W c');
perm('t1', 'R W c');
perm('t2', 'R w c');
perm('t3', 'r w c');

try "## u2";
try "glt info u2 -json; ok";
$href = from_json(text());
perm('foo/..*', 'r w c');
perm('testing', 'R W c');
perm('t1', 'R w c');
perm('t2', 'R W c');
perm('t3', 'r w c');

try "## u3";
try "glt info u3 -json; ok";
$href = from_json(text());
perm('foo/..*', 'R W c');
perm('testing', 'R W c');
perm('t1', 'r w c');
perm('t2', 'r w c');
perm('t3', 'R W c');

try "## u4";
try "glt info u4 -json; ok";
$href = from_json(text());
perm('foo/..*', 'r w c');
perm('testing', 'R W c');
perm('t1', 'r w c');
perm('t2', 'r w c');
perm('t3', 'R w c');

try "## u5";
try "glt info u5 -json; ok";
$href = from_json(text());
perm('foo/..*', 'r w c');
perm('testing', 'R W c');
perm('t1', 'r w c');
perm('t2', 'r w c');
perm('t3', 'r w c');

try "## u6";
try "glt info u6 -json; ok";
$href = from_json(text());
perm('foo/..*', 'r w c');
perm('testing', 'R W c');
perm('t1', 'r w c');
perm('t2', 'r w c');
perm('t3', 'r w c');

try "## ls-remote foo/one";
try "glt ls-remote u1 file:///foo/one;   ok";

try "## u1";
try "glt info u1 -json; ok; !/creator..:/";
$href = from_json(text());
perm('foo/..*', 'r w C');
perm('foo/one', 'R W c');
test_creator('foo/one', 'u1', 'undef');

try "## u2";
try "glt info u2 -json; ok; !/creator..:/";
$href = from_json(text());
perm('foo/..*', 'r w c');
perm('foo/one', 'r w c');
test_creator('foo/one', 'u1', 'undef');

try "## u3";
try "glt info u3 -json; ok; !/creator..:/";
$href = from_json(text());
perm('foo/..*', 'R W c');
perm('foo/one', 'R W c');
test_creator('foo/one', 'u1', 'undef');

try("## with -lc now");

try "## u1";
try "glt info u1 -lc -json; ok";
$href = from_json(text());
perm('foo/..*', 'r w C');
perm('foo/one', 'R W c');
test_creator('foo/one', 'u1', 1);

try "## u2";
try "glt info u2 -lc -json; ok";
$href = from_json(text());
perm('foo/..*', 'r w c');
perm('foo/one', 'r w c');
test_creator('foo/one', 'u1', 'undef');

try "## u3";
try "glt info u3 -lc -json; ok";
$href = from_json(text());
perm('foo/..*', 'R W c');
perm('foo/one', 'R W c');
test_creator('foo/one', 'u1', 1);

# ----------------------------------------------------------------------

# test perms given repo and expected perms.  (lowercase r/w/c means NOT
# expected, uppercase means expected)
sub perm {
    my ($repo, $aa) = @_;
    for my $aa1 (split ' ', $aa) {
        my $exp = 1;
        if ($aa1 =~ /[a-z]/) {
            $exp = 'undef';     # we can't use 0, though I'd like to
            $aa1 = uc($aa1);
        }
        my $perm = $href->{repos}{$repo}{perms}{$aa1} || 'undef';
        try 'perl $_ = "' . $perm  . '"; /' . $exp . '/';
    }
}

# test versions in greeting string
sub test_gs {
    my $glu = shift;
    my $res = ( $href->{GL_USER} eq $glu ? 1 : 'undef' );
    try 'perl $_ = "' . $res  . '"; /1/';
    $res = ( $href->{gitolite_version} =~ /^v3.[5-9]/ ? 1 : 'undef' );
    try 'perl $_ = "' . $res  . '"; /1/';
    $res = ( $href->{git_version} =~ /^1.[6-9]/ ? 1 : 'undef' );
    try 'perl $_ = "' . $res  . '"; /1/';
}

# test creator
sub test_creator {
    my ($r, $c, $exp) = @_;
    my $res = ( ($href->{repos}{$r}{creator} || '') eq $c ? 1 : 'undef' );
    try 'perl $_ = "' . $res  . '"; /' . $exp . '/';
}
