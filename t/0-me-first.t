#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

my $rb = `gitolite query-rc -n GL_REPO_BASE`;

# initial smoke tests
# ----------------------------------------------------------------------

try "plan 71";

# basic push admin repo
confreset;confadd '
    repo aa
        RW+     =   u1
        RW      =   u2 u3

    repo cc/..*
        C       =   u4
        RW+     =   CREATOR u5
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "
                                            /Initialized empty Git repository in .*/aa.git//

    # basic clone
    cd ..
    glt clone u1 file:///aa u1aa;    ok;     /Cloning into 'u1aa'.../
                                            /warning: You appear to have cloned an empty repository/
    [ -d u1aa ];                    ok

    # basic clone deny
    glt clone u4 file:///aa u4aa;    !ok;    /R any aa u4 DENIED by fallthru/
    [ -d u4aa ];                    !ok

    # basic push
    cd u1aa;                        ok
    tc z-507;                       ok;     /master .root-commit. 7cf7624. z-507/
    glt push u1 origin HEAD;        ok;     /To file:///aa/
                                            /\\[new branch\\] *HEAD -> master/

    # basic rewind
    tc o-866 o-867 o-868;           ok;     /master 2d066fb. o-868/
    glt push u1 origin HEAD;        ok;     /7cf7624..2d066fb  HEAD -> master/
    git reset --hard HEAD^;         ok;     /HEAD is now at 8b1456b o-867/
    tc x-967;                       ok;     /master 284951d. x-967/
    glt push u1 -f origin HEAD;     ok;     /\\+ 2d066fb...284951d HEAD -> master \\(forced update\\)/

    # log file
    cat \$(gitolite query-rc GL_LOGFILE);
                                    ok;     /\tupdate\t/
                                            /aa\tu1\t\\+\trefs/heads/master/
                                            /2d066fb4860c29cf321170c17695c6883f3d50e8/
                                            /284951dfa11d58f99ab76b9f4e4c1ad2f2461236/

    # basic rewind deny
    cd ..
    glt clone u2 file:///aa u2aa;    ok;     /Cloning into 'u2aa'.../
    cd u2aa;                        ok
    tc g-776 g-777 g-778;           ok;     /master 9cbc181. g-778/
    glt push u2 origin HEAD;        ok;     /284951d..9cbc181  HEAD -> master/
    git reset --hard HEAD^;         ok;     /HEAD is now at 2edf7fc g-777/
    tc d-485;                       ok;     /master 1c01d32. d-485/
    glt push u2 -f origin HEAD;     !ok;    reject
                                            /\\+ refs/heads/master aa u2 DENIED by fallthru/

    # non-existent repos etc
    glt ls-remote u4 file:///bb;    !ok;    /DENIED by fallthru/
    glt ls-remote u4 file:///cc/1;  ok;     /Initialized empty/
    glt ls-remote u5 file:///cc/1;  ok;     perl s/TRACE.*//g; !/\\S/
    glt ls-remote u5 file:///cc/2;  !ok;    /DENIED by fallthru/
    glt ls-remote u6 file:///cc/2;  !ok;    /DENIED by fallthru/

    # command
    glt perms u4 -c cc/bar/baz/frob + READERS u2;
                                    ok;     /Initialized empty .*cc/bar/baz/frob.git/

    # path traversal
    glt ls-remote u4 file:///cc/dd/../ee
                                    !ok;    /FATAL: 'cc/dd/\\.\\./ee' contains '\\.\\.'/
    glt ls-remote u5 file:///cc/../../../../../..$rb/gitolite-admin
                                    !ok;    /FATAL: 'cc/../../../../../..$rb/gitolite-admin' contains '\\.\\.'/

    glt perms u4 -c cc/bar/baz/../frob + READERS u2
                                    !ok;    /FATAL: no relative paths allowed anywhere!/

";
