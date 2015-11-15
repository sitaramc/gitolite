#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# test script for partial copy feature
# ----------------------------------------------------------------------

try "plan 128";
my $h = $ENV{HOME};
my $rb = `gitolite query-rc -n GL_REPO_BASE`;

try 'cd tsh_tempdir; mkdir -p local/hooks/repo-specific';

foreach my $h (qw/first second/) {
    put "local/hooks/repo-specific/$h", "#!/bin/sh
echo \$0
if [ \$# -ne 0 ]; then
    echo \$0 has args: \$@
else
    echo \$0 has stdin: `cat`
fi
";
}
try 'chmod +x local/hooks/repo-specific/*';

try 'pwd';
my $tempdir = join("\n", sort (lines()));
try 'cd gitolite-admin';

try "# Enable LOCAL_CODE and repo-specific-hooks
    cat $h/.gitolite.rc
    perl s/# 'repo-specific-hooks'/'repo-specific-hooks'/
    perl s%# LOCAL_CODE%LOCAL_CODE => '$tempdir/local', #%
    put $h/.gitolite.rc
";

confreset;confadd '
    repo foo
            RW+                 =   @all

    repo bar
            RW+                 =   @all

    repo baz
            RW+                 =   @all

    repo frob
            RW+                 =   @all
';

try "ADMIN_PUSH repo-specific-hooks-0; !/FATAL/" or die text();

try "
    /Init.*empty.*foo\\.git/
    /Init.*empty.*bar\\.git/
    /Init.*empty.*baz\\.git/
    /Init.*empty.*frob\\.git/
";

my $failing_hook = "#!/bin/sh
exit 1
";

# Place a existing hooks in repos
put "$rb/foo.git/hooks/post-recieve", $failing_hook;
put "$rb/bar.git/hooks/pre-recieve", $failing_hook;
put "$rb/baz.git/hooks/post-update", $failing_hook;
put "$rb/frob.git/hooks/post-update", $failing_hook;

try "# Verify hooks
    ls -l $rb/foo.git/hooks/*;  ok;     !/post-receive -. .*local/hooks/multi-hook-driver/
    ls -l $rb/bar.git/hooks/*;  ok;     !/pre-receive -. .*local/hooks/multi-hook-driver/
    ls -l $rb/baz.git/hooks/*;  ok;     !/post-update -. .*local/hooks/multi-hook-driver/
    ls -l $rb/frob.git/hooks/*; ok;     !/post-update -. .*local/hooks/multi-hook-driver/
";

confreset;confadd '
    repo foo
            RW+                 =   @all
            option hook.post-receive =  first

    repo bar
            RW+                 =   @all
            option hook.pre-receive =  first second

    repo baz
            RW+                 =   @all
            option hook.post-receive =  first
            option hook.post-update =  first second

    repo frob
            RW+                 =   @all
            option hook.post-receive.b      =   first
            option hook.post-receive.a      =   second

    repo gitolite-admin
            option hook.post-receive = second
';


try "ADMIN_PUSH repo-specific-hooks-1; !/FATAL/" or die text();

try "# Verify hooks
    ls -l $rb/foo.git/hooks/*;  ok;     /post-receive.h00-first/
                                       !/post-receive.h01/
                                        /post-receive -. .*local/hooks/multi-hook-driver/
    ls -l $rb/bar.git/hooks/*;  ok;     /pre-receive.h00-first/
                                        /pre-receive.h01-second/
                                        /pre-receive -. .*local/hooks/multi-hook-driver/
    ls -l $rb/baz.git/hooks/*;  ok;     /post-receive.h00-first/
                                        /post-update.h00-first/
                                        /post-update.h01-second/
                                        /post-update -. .*local/hooks/multi-hook-driver/
    ls -l $rb/frob.git/hooks/*; ok;     /post-receive.h00-second/
                                        /post-receive.h01-first/
                                        /post-receive -. .*local/hooks/multi-hook-driver/
    ls -l $rb/gitolite-admin.git/hooks/*
                                ok;     /post-receive.h/
                                        /post-receive -. .*local/hooks/multi-hook-driver/
                                       !/post-update -. .*local/hooks/multi-hook-driver/
";

try "
    cd ..

    # Single hook still works
    [ -d foo ];            !ok;
    CLONE admin foo;        ok; /empty/; /cloned/
    cd foo
    tc a1;                  ok; /ee47f8b/
    PUSH admin master;      ok; /new.*master -. master/
                                /hooks/post-receive.h00-first/
                                !/post-receive.*has args:/
                                /post-receive.h00-first has stdin: 0000000000000000000000000000000000000000 ee47f8b6be2160ad1a3f69c97a0cb3d488e6657e refs/heads/master/

    cd ..

    # Multiple hooks fired
    [ -d bar ];            !ok;
    CLONE admin bar;        ok; /empty/; /cloned/
    cd bar
    tc a2;                  ok; /cfc8561/
    PUSH admin master;      ok; /new.*master -. master/
                                /hooks/pre-receive.h00-first/
                                !/hooks/pre-recieve.*has args:/
                                /hooks/pre-receive.h00-first has stdin: 0000000000000000000000000000000000000000 cfc8561c7827a8b94df6c5dad156383d4cb210f5 refs/heads/master/
                                /hooks/pre-receive.h01-second/
                                !/hooks/pre-receive.h01.*has args:/
                                /hooks/pre-receive.h01-second has stdin: 0000000000000000000000000000000000000000 cfc8561c7827a8b94df6c5dad156383d4cb210f5 refs/heads/master/

    cd ..

    # Post-update has stdin instead of arguments
    [ -d baz ];            !ok;
    CLONE admin baz;        ok; /empty/; /cloned/
    cd baz
    tc a3;                  ok; /2863617/
    PUSH admin master;      ok; /new.*master -. master/
                                /hooks/post-receive.h00-first/
                                !/hooks/post-receive.h00.*has args:/
                                /hooks/post-receive.h00-first has stdin: 0000000000000000000000000000000000000000 28636171ae703f42fb17c312c6b6a078ed07a2cd refs/heads/master/
                                /hooks/post-update.h00-first/
                                /hooks/post-update.h00-first has args: refs/heads/master/
                                !/hooks/post-update.h00.*has stdin:/
                                /hooks/post-update.h01-second/
                                /hooks/post-update.h01-second has args: refs/heads/master/
                                !/hooks/post-update.h01.*has stdin:/
";

# Verify hooks are removed properly

confreset;confadd '
    repo foo
            RW+                 =   @all
            option hook.post-receive =

    repo bar
            RW+                 =   @all
            option hook.pre-receive =  second

    repo baz
            RW+                 =   @all
            option hook.post-receive =
            option hook.post-update =  second
';

try "ADMIN_PUSH repo-specific-hooks-02; !/FATAL/" or die text();

try "
    ls $rb/foo.git/hooks/*;  ok;    !/post-receive/
    ls $rb/bar.git/hooks/*;  ok;    !/pre-receive.*first/
                                     /pre-receive.h00-second/
    ls $rb/baz.git/hooks/*;  ok;    !/post-receive/
                                    !/post-update.*first/
                                     /post-update.h00-second/
";

try "
    cd ..

    # Foo has no hooks
    cd foo
    tc b1;                  ok; /7ef69de/
    PUSH admin master;      ok; /master -. master/
                                !/hooks/post-receive/

    cd ..

    # Bar only has the second hook
    cd bar
    tc b2;                  ok; /cc7808f/
    PUSH admin master;      ok; /master -. master/
                                /hooks/pre-receive.h00-second/
                                !/hooks/pre-receive.*has args:/
                                /hooks/pre-receive.h00-second has stdin: 0000000000000000000000000000000000000000 cc7808f77c7c7d705f82dc54dc3152146175768f refs/heads/master/

    cd ..

    # Baz has no post-receive and keeps the second hook for post-update
    cd baz
    tc b3;                  ok; /8d20101/
    PUSH admin master;      ok; /master -. master/
                                !/hooks/post-receive.*/
                                /hooks/post-update.h00-second/
                                /hooks/post-update.h00-second has args: refs/heads/master/
                                !/hooks/post-update.*has stdin/
";
