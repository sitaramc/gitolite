#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# basic tests
# ----------------------------------------------------------------------

try "plan 24";
try "DEF POK = !/DENIED/; !/failed to push/";

confreset;confadd '

@leads = u1 u2
@devs = u1 u2 u3 u4

@gbar = bar/CREATOR/..*
repo    @gbar
    C               =   @leads
    RW+             =   @leads
    RW              =   WRITERS @devs
    R               =   READERS
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

my $rb = `gitolite query-rc -n GL_REPO_BASE`;
chdir($rb);
my $h = $ENV{HOME};

try "
    glt ls-remote u1 file:///bar/u1/try1
    /Initialized empty Git repository in .*/bar/u1/try1.git/

    find . -name git-daemon-export-ok
    /testing.git/git-daemon-export-ok/

    cat $h/projects.list
    /testing.git/

    glt ls-remote u1 file:///bar/u1/try2
    /Initialized empty Git repository in .*/bar/u1/try2.git/

    find $h/repositories -name git-daemon-export-ok
    /testing.git/git-daemon-export-ok/

    cat $h/projects.list
    /testing.git/

    glt perms u1 bar/u1/try1 + READERS daemon
    !/./

    glt perms u1 -l bar/u1/try1
    /READERS daemon/

    find $h/repositories -name git-daemon-export-ok
    /repositories/testing.git/git-daemon-export-ok/
    /repositories/bar/u1/try1.git/git-daemon-export-ok/

    cat $h/projects.list
    /testing.git/

    glt perms u1 bar/u1/try2 + READERS gitweb

    glt perms u1 -l bar/u1/try2
    /READERS gitweb/

    find $h/repositories -name git-daemon-export-ok
    /testing.git/git-daemon-export-ok/
    /bar/u1/try1.git/git-daemon-export-ok/

    cat $h/projects.list
    /bar/u1/try2.git/
    /testing.git/
";
