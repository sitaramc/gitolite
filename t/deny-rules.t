#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

# branch permissions test
# ----------------------------------------------------------------------

try "plan 11";

confreset;confadd '
    # start with...

    repo gitolite-admin
        -   =   gitweb daemon
    option deny-rules = 1

    # main ruleset goes here

    @ga = a
    @gb = b
    @gc = c

    # and end with

    repo @ga
        RW  =   u1
        -   =   @all
    option deny-rules = 1

    repo @gb
        RW  =   u2
        -   =   daemon
    option deny-rules = 1

    repo @gc
        RW  =   u3

    repo @all
        R   =   @all

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

my $rb = `gitolite query-rc -n GL_REPO_BASE`;
try "
    cat $ENV{HOME}/projects.list;                           ok
";
cmp 'b.git
c.git
testing.git
';

try "
    cd ..
    cd ..
    echo $rb
    find $rb -name git-daemon-export-ok | sort
    perl s,$rb/,,g
";
cmp 'c.git/git-daemon-export-ok
testing.git/git-daemon-export-ok
'
