#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# could anything be clearer than "all y'all"?
# ----------------------------------------------------------------------

try "plan 26";

confreset;confadd '
    repo @all
        R   =   @all
    repo foo
        RW+ =   u1
    repo bar
        RW+ =   u2
    repo dev/..*
        C   =   u3 u4
        RW+ =   CREATOR
';

try "
    rm $ENV{HOME}/projects.list
";
try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    glt ls-remote u1 file:///dev/wild1
                /FATAL: R any dev/wild1 u1 DENIED by fallthru/

    glt clone u3 file:///dev/wild1
                /Cloning into 'wild1'.../
                /Initialized empty Git repository in .*/dev/wild1.git//
                /warning: You appear to have cloned an empty repository./

    cd wild1
    tc n-855 n-856
    glt push u3 origin master:wild1
                /To file:///dev/wild1/
                /\\* \\[new branch\\]      master -> wild1/
    glt push u1 file:///foo master:br-foo
                /To file:///foo/
                /\\* \\[new branch\\]      master -> br-foo/
    glt push u2 file:///bar master:br-bar
                /To file:///bar/
                /\\* \\[new branch\\]      master -> br-bar/

    glt ls-remote u6 file:///foo
                /refs/heads/br-foo/

    glt ls-remote u6 file:///bar
                /refs/heads/br-bar/

    glt ls-remote u6 file:///dev/wild1
                /refs/heads/wild1/
";

try "
    gitolite ../triggers/post-compile/update-git-daemon-access-list;    ok
    gitolite ../triggers/post-compile/update-gitweb-access-list;        ok
    cat $ENV{HOME}/projects.list;                           ok
";
cmp 'bar.git
dev/wild1.git
foo.git
gitolite-admin.git
testing.git
';

my $rb = `gitolite query-rc -n GL_REPO_BASE`;

try "
    cd ..
    cd ..
    echo $rb
    find $rb -name git-daemon-export-ok | sort
    perl s,$rb/,,g
";

cmp 'bar.git/git-daemon-export-ok
dev/wild1.git/git-daemon-export-ok
foo.git/git-daemon-export-ok
gitolite-admin.git/git-daemon-export-ok
testing.git/git-daemon-export-ok
';
