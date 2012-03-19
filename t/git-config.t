#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

# git config settings
# ----------------------------------------------------------------------

try "plan 21";

try "pwd";
my $od = text();
chomp($od);

# make foo.bar a valid gc key
$ENV{G3T_RC} = "$ENV{HOME}/g3trc";
put "$ENV{G3T_RC}", "\$rc{GIT_CONFIG_KEYS} = 'foo\.bar';\n";

confreset;confadd '

    repo @all
        config foo.bar  =   dft

    repo gitolite-admin
        RW+     =   admin
        config foo.bar  =

    repo testing
        RW+     =   @all

    repo foo
        RW      =   u1
        config foo.bar  =   f1

    repo frob
        RW      =   u3

    repo bar
        RW      =   u2
        config foo.bar  =   one

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

my $rb = `gitolite query-rc -n GL_REPO_BASE`;
try "
    cd $rb;                             ok
    egrep foo\\|bar *.git/config | sort
";
cmp 'bar.git/config:	bare = true
bar.git/config:	bar = one
bar.git/config:[foo]
foo.git/config:	bare = true
foo.git/config:	bar = f1
foo.git/config:[foo]
frob.git/config:	bar = dft
frob.git/config:	bare = true
frob.git/config:[foo]
gitolite-admin.git/config:	bare = true
testing.git/config:	bar = dft
testing.git/config:	bare = true
testing.git/config:[foo]
';

try "cd $od; ok";

confadd '

    repo frob
        RW      =   u3
        config foo.bar  =   none

    repo bar
        RW      =   u2
        config foo.bar  =   one

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd $rb;                             ok
    egrep foo\\|bar *.git/config | sort
";

cmp 'bar.git/config:	bare = true
bar.git/config:	bar = one
bar.git/config:[foo]
foo.git/config:	bare = true
foo.git/config:	bar = f1
foo.git/config:[foo]
frob.git/config:	bare = true
frob.git/config:	bar = none
frob.git/config:[foo]
gitolite-admin.git/config:	bare = true
testing.git/config:	bar = dft
testing.git/config:	bare = true
testing.git/config:[foo]
';
