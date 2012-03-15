#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src";
use Gitolite::Test;

# basic tests
# ----------------------------------------------------------------------

try "plan 185";

confreset;confadd '
    @admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    repo testing
        RW+     =   @all

    @g1 = t1
    repo @g1
        R       =   u2
        RW      =   u3
        RW+     =   u4
';

try "ADMIN_PUSH set1; !/FATAL/" or die text();

try "

    gitolite access -q t1 u1;   !ok;    !/./
    gitolite access -q t1 u1 R; !ok;    !/./
    gitolite access -q t1 u1 W; !ok;    !/./
    gitolite access -q t1 u1 +; !ok;    !/./
    gitolite access -q t1 u2;   !ok;    !/./
    gitolite access -q t1 u2 R; ok;     !/./
    gitolite access -q t1 u2 W; !ok;    !/./
    gitolite access -q t1 u2 +; !ok;    !/./
    gitolite access -q t1 u3;   !ok;    !/./
    gitolite access -q t1 u3 R; ok;     !/./
    gitolite access -q t1 u3 W; ok;     !/./
    gitolite access -q t1 u3 +; !ok;    !/./
    gitolite access -q t1 u4;   ok;     !/./
    gitolite access -q t1 u4 R; ok;     !/./
    gitolite access -q t1 u4 W; ok;     !/./
    gitolite access -q t1 u4 +; ok;     !/./

    gitolite access t1 u1;      !ok;    /\\+ any t1 u1 DENIED by fallthru/
    gitolite access t1 u1 R;    !ok;    /R any t1 u1 DENIED by fallthru/
    gitolite access t1 u1 W;    !ok;    /W any t1 u1 DENIED by fallthru/
    gitolite access t1 u1 +;    !ok;    /\\+ any t1 u1 DENIED by fallthru/
    gitolite access t1 u2;      !ok;    /\\+ any t1 u2 DENIED by fallthru/
    gitolite access t1 u2 R;    ok;     /refs/\.\*/
    gitolite access t1 u2 W;    !ok;    /W any t1 u2 DENIED by fallthru/
    gitolite access t1 u2 +;    !ok;    /\\+ any t1 u2 DENIED by fallthru/
    gitolite access t1 u3;      !ok;    /\\+ any t1 u3 DENIED by fallthru/
    gitolite access t1 u3 R;    ok;     /refs/\.\*/
    gitolite access t1 u3 W;    ok;     /refs/\.\*/
    gitolite access t1 u3 +;    !ok;    /\\+ any t1 u3 DENIED by fallthru/
    gitolite access t1 u4;      ok;     /refs/\.\*/
    gitolite access t1 u4 R;    ok;     /refs/\.\*/
    gitolite access t1 u4 W;    ok;     /refs/\.\*/
    gitolite access t1 u4 +;    ok;     /refs/\.\*/

";

confreset;confadd '
    @admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    @g1 = u1
    @g2 = u2
    @g3 = u3
    @gaa = aa
    repo @gaa
        RW+                 =   @g1
        RW                  =   @g2
        RW+     master      =   @g3
        RW      master      =   u4
        -       master      =   u5
        RW+     dev         =   u5
        RW                  =   u5
';

try "ADMIN_PUSH set2; !/FATAL/" or die text();

try "
    gitolite access \@gaa \@g1 + any ;                  ok;     /refs/.*/; !/DENIED/
    gitolite access aa \@g1 + refs/heads/master ;       ok;     /refs/.*/; !/DENIED/
    gitolite access \@gaa \@g1 + refs/heads/next ;      ok;     /refs/.*/; !/DENIED/
    gitolite access \@gaa \@g1 W refs/heads/next ;      ok;     /refs/.*/; !/DENIED/
    gitolite access \@gaa u1 + refs/heads/dev ;         ok;     /refs/.*/; !/DENIED/
    gitolite access \@gaa u1 + refs/heads/next ;        ok;     /refs/.*/; !/DENIED/
    gitolite access aa u1 W refs/heads/next ;           ok;     /refs/.*/; !/DENIED/
    gitolite access \@gaa \@g2 + refs/heads/master ;    !ok;    /\\+ refs/heads/master \@gaa \@g2 DENIED by fallthru/
    gitolite access \@gaa \@g2 + refs/heads/next ;      !ok;    /\\+ refs/heads/next \@gaa \@g2 DENIED by fallthru/
    gitolite access aa \@g2 W refs/heads/master ;       ok;     /refs/.*/; !/DENIED/
    gitolite access aa u2 + any ;                       !ok;    /\\+ any aa u2 DENIED by fallthru/
    gitolite access \@gaa u2 + refs/heads/master ;      !ok;    /\\+ refs/heads/master \@gaa u2 DENIED by fallthru/
    gitolite access \@gaa u2 W refs/heads/master ;      ok;     /refs/.*/; !/DENIED/
    gitolite access \@gaa \@g3 + refs/heads/master ;    ok;     /refs/heads/master/; !/DENIED/
    gitolite access \@gaa \@g3 W refs/heads/next ;      !ok;    /W refs/heads/next \@gaa \@g3 DENIED by fallthru/
    gitolite access \@gaa \@g3 W refs/heads/dev ;       !ok;    /W refs/heads/dev \@gaa \@g3 DENIED by fallthru/
    gitolite access aa u3 + refs/heads/dev ;            !ok;    /\\+ refs/heads/dev aa u3 DENIED by fallthru/
    gitolite access aa u3 + refs/heads/next ;           !ok;    /\\+ refs/heads/next aa u3 DENIED by fallthru/
    gitolite access \@gaa u4 + refs/heads/master ;      !ok;    /\\+ refs/heads/master \@gaa u4 DENIED by fallthru/
    gitolite access \@gaa u4 W refs/heads/master ;      ok;     /refs/heads/master/; !/DENIED/
    gitolite access aa u4 + refs/heads/next ;           !ok;    /\\+ refs/heads/next aa u4 DENIED by fallthru/
    gitolite access \@gaa u4 W refs/heads/next ;        !ok;    /W refs/heads/next \@gaa u4 DENIED by fallthru/
    gitolite access \@gaa u5 R any ;                    ok;     /refs/heads/dev/; !/DENIED/
    gitolite access aa u5 R any ;                       ok;     /refs/heads/dev/; !/DENIED/
    gitolite access \@gaa u5 + refs/heads/dev ;         ok;     /refs/heads/dev/; !/DENIED/
    gitolite access \@gaa u5 + refs/heads/master ;      !ok;    /\\+ refs/heads/master \@gaa u5 DENIED by refs/heads/master/
    gitolite access aa u5 + refs/heads/next ;           !ok;    /\\+ refs/heads/next aa u5 DENIED by fallthru/
    gitolite access \@gaa u5 R refs/heads/dev ;         ok;     /refs/heads/dev/; !/DENIED/
    gitolite access \@gaa u5 R refs/heads/master ;      !ok;    /R refs/heads/master \@gaa u5 DENIED by refs/heads/master/
    gitolite access \@gaa u5 R refs/heads/next ;        ok;     /refs/.*/; !/DENIED/
    gitolite access aa u5 W refs/heads/dev ;            ok;     /refs/heads/dev/; !/DENIED/
    gitolite access aa u5 W refs/heads/master ;         !ok;    /W refs/heads/master aa u5 DENIED by refs/heads/master/
    gitolite access \@gaa u5 W refs/heads/next ;        ok;     /refs/.*/; !/DENIED/
";

confreset;confadd '
    @admins     =   admin dev1
    repo gitolite-admin
        RW+     =   admin

    @gr1 = r1
    repo @gr1
        RW  refs/heads/v[0-9]   = u1
        RW  refs/heads          = tester

    @gr2 = r2
    repo @gr2
        RW  refs/heads/v[0-9]   = u1
        -   refs/heads/v[0-9]   = tester
        RW  refs/heads          = tester
';

try "ADMIN_PUSH set3; !/FATAL/" or die text();

try "
    gitolite access \@gr2 tester W refs/heads/v1;       !ok;    /W refs/heads/v1 \@gr2 tester DENIED by refs/heads/v\\[0-9\\]/
    gitolite access \@gr1 tester W refs/heads/v1;       ok;     /refs/heads/; !/DENIED/
    gitolite access r1 tester W refs/heads/v1;          ok;     /refs/heads/; !/DENIED/
    gitolite access r2 tester W refs/heads/v1;          !ok;    /W refs/heads/v1 r2 tester DENIED by refs/heads/v\\[0-9\\]/
    gitolite access r2 tester W refs/heads/va;          ok;     /refs/heads/; !/DENIED/
";

