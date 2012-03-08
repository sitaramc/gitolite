package Gitolite::Test;

# functions for the test code to use
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
  try
  put
);
#>>>
use Exporter 'import';
use File::Path qw(mkpath);
use Carp qw(carp cluck croak confess);

BEGIN {
    require Gitolite::Test::Tsh;
    *{'try'} = \&Tsh::try;
    *{'put'} = \&Tsh::put;
}

use strict;
use warnings;

# ----------------------------------------------------------------------

# required preamble for all tests
try "
    DEF gsh = /TRACE: gsh.SOC=/
    ./g3-install -c admin
    cd tsh_tempdir;
";

1;
