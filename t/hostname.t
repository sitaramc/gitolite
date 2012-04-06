#!/usr/bin/perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

# %HOSTNAME tests
# ----------------------------------------------------------------------

try "plan 60";

try "pwd";
my $od = text();
chomp($od);

# without setting HOSTNAME in rc
confreset;confadd '

    repo foo
        RW  dev/%HOSTNAME   =   u1
';

try "ADMIN_PUSH set1; /FATAL/";
try "/bad ref 'refs/heads/dev/%HOSTNAME'/";

# make a hostname entry
$ENV{G3T_RC} = "$ENV{HOME}/g3trc";
put "$ENV{G3T_RC}", "\$rc{HOSTNAME} = 'frodo';\n";

confreset;confadd '

    repo bar
        RW  %HOSTNAME_baz   =   u1
';

try "ADMIN_PUSH set1; /FATAL/";
try "/bad ref 'refs/heads/%HOSTNAME_baz'/";

confreset;confadd '

    repo bar
        RW  %HOSTNAME/      =   u1
        RW  %HOSTNAME-baz   =   u1
';

try "ADMIN_PUSH set1; !/FATAL/";
try "
    gitolite access bar u2 R any;                   /R any bar u2 DENIED by fallthru/
    gitolite access bar u2 W any;                   /W any bar u2 DENIED by fallthru/
    gitolite access bar u1 W any;                   !/DENIED/; /refs/heads/frodo/; !/baz/
    gitolite access bar u1 R any;                   !/DENIED/; /refs/heads/frodo/; !/baz/
    gitolite access bar u1 R refs/heads/frodo;      /R refs/heads/frodo bar u1 DENIED by fallthru/
    gitolite access bar u1 W refs/heads/frodo;      /W refs/heads/frodo bar u1 DENIED by fallthru/
    gitolite access bar u1 R refs/heads/frodo/1;    !/DENIED/; /refs/heads/frodo/; !/baz/
    gitolite access bar u1 W refs/heads/frodo/1;    !/DENIED/; /refs/heads/frodo/; !/baz/
    gitolite access bar u1 R refs/heads/sam;        /R refs/heads/sam bar u1 DENIED by fallthru/
    gitolite access bar u1 W refs/heads/sam;        /W refs/heads/sam bar u1 DENIED by fallthru/
    gitolite access bar u1 R refs/heads/master;     /R refs/heads/master bar u1 DENIED by fallthru/
    gitolite access bar u1 W refs/heads/master;     /W refs/heads/master bar u1 DENIED by fallthru/

    gitolite access bar u1 R refs/heads/frodo-baz;  !/DENIED/; /refs/heads/frodo-baz/
    gitolite access bar u1 W refs/heads/frodo-baz;  !/DENIED/; /refs/heads/frodo-baz/
";

confreset;confadd '

    repo foo-%HOSTNAME
        RW  =   u1
';

try "ADMIN_PUSH set1; !/FATAL/";
try "
    gitolite list-repos;            /foo-frodo/
    gitolite list-phy-repos;        /foo-frodo/
";
