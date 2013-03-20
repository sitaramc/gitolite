#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;
my $h = $ENV{HOME};

# fork command
# ----------------------------------------------------------------------

try "plan 38";

my $rb = `gitolite query-rc -n GL_REPO_BASE`;

confreset;confadd '

    repo foo/CREATOR/..*
        C   =   u1 u2
        RW+ =   CREATOR
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd ..

    # make the initial repo
    glt ls-remote u1 file:///foo/u1/u1a;ok;     gsh
                                                /Initialized empty Git repository in .*/foo/u1/u1a.git/
    # vrc doesn't have the fork command
    glt fork u1 foo/u1/u1a foo/u1/u1a2; !ok;    /FATAL: unknown git/gitolite command: \\'fork/
";

# allow fork as a valid command
$ENV{G3T_RC} = "$ENV{HOME}/g3trc";
put "$ENV{G3T_RC}", "\$rc{COMMANDS}{fork} = 1;\n";

# enable set-default-roles feature, add options, push
try "
    cat $h/.gitolite.rc
    perl s/# 'set-default-roles'/'set-default-roles'/
    put $h/.gitolite.rc
";
try "cd gitolite-admin";
confadd '
    repo foo/CREATOR/..*
        C   =   u1 u2
        RW+ =   CREATOR
    option default.roles-1 = READERS @all
';
try "ADMIN_PUSH set1; !/FATAL/" or die text();
try "cd ..";

try "
    # now the fork succeeds
    glt fork u1 foo/u1/u1a foo/u1/u1a2; ok;     /Cloning into bare repository '.*/foo/u1/u1a2.git'/
                                                /foo/u1/u1a forked to foo/u1/u1a2/

    # now the actual testing starts
    # read error
    glt fork u1 foo/u1/u1c foo/u1/u1d;  !ok;    /'foo/u1/u1c' does not exist or you are not allowed to read it/
    glt fork u2 foo/u1/u1a foo/u1/u1d;  !ok;    /'foo/u1/u1a' does not exist or you are not allowed to read it/

    # write error
    glt fork u1 foo/u1/u1a foo/u2/u1d;  !ok;    /'foo/u2/u1d' already exists or you are not allowed to create it/

    # no error
    glt fork u1 foo/u1/u1a foo/u1/u1e;  ok;     /Cloning into bare repository '.*/foo/u1/u1e.git'/
                                                /warning: You appear to have cloned an empty repository/
                                                /foo/u1/u1a forked to foo/u1/u1e/
    # both exist
    glt fork u1 foo/u1/u1a foo/u1/u1e;  !ok;    /'foo/u1/u1e' already exists or you are not allowed to create it/
";

# now check the various files that should have been produced

my $t;
try "cd $rb; find . -name gl-perms"; $t = md5sum(sort (lines())); cmp $t,
'59b3a74b4d33c7631f08e75e7b60c7ce  ./foo/u1/u1a2.git/gl-perms
59b3a74b4d33c7631f08e75e7b60c7ce  ./foo/u1/u1e.git/gl-perms
';

try "cd $rb; find . -name gl-creator"; $t = md5sum(sort (lines())); cmp $t,
'e4774cdda0793f86414e8b9140bb6db4  ./foo/u1/u1a.git/gl-creator
346955ff2eadbf76e19373f07dd370a9  ./foo/u1/u1a2.git/gl-creator
346955ff2eadbf76e19373f07dd370a9  ./foo/u1/u1e.git/gl-creator
';
