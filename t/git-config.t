#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# git config settings
# ----------------------------------------------------------------------

try "plan 68";

try "pwd";
my $od = text();
chomp($od);

my $t;  # temp

# try an invalid config key
confreset;confadd '

    repo @all
        config foo.bar  =   dft
';

try "ADMIN_PUSH set1; /FATAL/" or die text();
try "
    /git config \\'foo.bar\\' not allowed/
    /check GIT_CONFIG_KEYS in the rc file/
";

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
    egrep foo\\|bar *.git/config
";
$t = join("\n", sort (lines()));

cmp $t, 'bar.git/config:	bar = one
bar.git/config:	bare = true
bar.git/config:[foo]
foo.git/config:	bar = f1
foo.git/config:	bare = true
foo.git/config:[foo]
frob.git/config:	bar = dft
frob.git/config:	bare = true
frob.git/config:[foo]
gitolite-admin.git/config:	bare = true
testing.git/config:	bar = dft
testing.git/config:	bare = true
testing.git/config:[foo]';

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
    egrep foo\\|bar *.git/config
";
$t = join("\n", sort (lines()));

cmp $t, 'bar.git/config:	bar = one
bar.git/config:	bare = true
bar.git/config:[foo]
foo.git/config:	bar = f1
foo.git/config:	bare = true
foo.git/config:[foo]
frob.git/config:	bar = none
frob.git/config:	bare = true
frob.git/config:[foo]
gitolite-admin.git/config:	bare = true
testing.git/config:	bar = dft
testing.git/config:	bare = true
testing.git/config:[foo]';

try "cd $od; ok";

confadd '

    repo bar
        RW      =   u2
        config foo.bar  =   

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd $rb;                             ok
    egrep foo\\|bar *.git/config
";
$t = join("\n", sort (lines()));

cmp $t, 'bar.git/config:	bare = true
foo.git/config:	bar = f1
foo.git/config:	bare = true
foo.git/config:[foo]
frob.git/config:	bar = none
frob.git/config:	bare = true
frob.git/config:[foo]
gitolite-admin.git/config:	bare = true
testing.git/config:	bar = dft
testing.git/config:	bare = true
testing.git/config:[foo]';

try "cd $od; ok";

confreset;confadd '

    repo @gr1
        RW      =   u1
        config foo.bar  =   f1

    repo bar/CREATOR/[one].*
        C       =   u2
        RW      =   u2
        config foo.bar  =   one

    @gr1 = foo frob

';
try "ADMIN_PUSH set1; !/FATAL/" or die text();
try "
    glt ls-remote u2 file:///bar/u2/one;        ok;     /Initialized empty/
    glt ls-remote u2 file:///bar/u2/two;        !ok;    /DENIED by fallthru/
";

try "
    cd $rb;                             ok
    find . -name config | xargs egrep foo\\|bar
";
$t = join("\n", sort (lines()));

cmp $t, './bar/u2/one.git/config:	bar = one
./bar/u2/one.git/config:	bare = true
./bar/u2/one.git/config:[foo]
./foo.git/config:	bar = f1
./foo.git/config:	bare = true
./foo.git/config:[foo]
./frob.git/config:	bar = f1
./frob.git/config:	bare = true
./frob.git/config:[foo]
./gitolite-admin.git/config:	bare = true
./testing.git/config:	bar = dft
./testing.git/config:	bare = true
./testing.git/config:[foo]';

put "$ENV{G3T_RC}", "\$rc{GIT_CONFIG_KEYS} = 'foo\.bar foo\.qux foo\.foo';
\$rc{GIT_MULTI_CONFIG_KEYS} = 'foo\.qux foo\.foo';\n";

try "cd $od; ok";

confreset;confadd '

    repo @all
        config foo.bar  =   dft
        config foo.qux  =   dft
        config foo.foo  =

    repo gitolite-admin
        RW+     =   admin
        config foo.bar  =
        config foo.qux  =

    repo testing
        RW+     =   @all
        config foo.foo  =

    repo foo
        RW      =   u1
        config foo.bar  =   f1
        config foo.qux  =   f1
        config foo.qux  =   f2

    repo frob
        RW      =   u3
        config foo.foo  =   f1

    repo bar
        RW      =   u2
        config foo.bar  =   zero
        config foo.bar  =   one
        config foo.qux  =   one

';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
    cd $rb;                             ok
    egrep foo\\|bar\\|qux *.git/config
";
$t = join("\n", sort (lines()));

cmp $t, 'bar.git/config:	bar = one
bar.git/config:	bare = true
bar.git/config:	qux = dft
bar.git/config:	qux = one
bar.git/config:[foo]
foo.git/config:	bar = f1
foo.git/config:	bare = true
foo.git/config:	qux = dft
foo.git/config:	qux = f1
foo.git/config:	qux = f2
foo.git/config:[foo]
frob.git/config:	bar = dft
frob.git/config:	bare = true
frob.git/config:	foo = f1
frob.git/config:	qux = dft
frob.git/config:[foo]
gitolite-admin.git/config:	bare = true
gitolite-admin.git/config:	qux = dft
gitolite-admin.git/config:[foo]
testing.git/config:	bar = dft
testing.git/config:	bare = true
testing.git/config:	qux = dft
testing.git/config:[foo]';
