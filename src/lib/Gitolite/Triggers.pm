package Gitolite::Triggers;

# load and run triggered modules
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
);
#>>>
use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub run {
    my ( $module, $sub, @args ) = @_;
    $module = "Gitolite::Triggers::$module" if $module !~ /^Gitolite::/;

    eval "require $module";
    _die "$@" if $@;
    my $subref;
    eval "\$subref = \\\&$module" . "::" . "$sub";
    _die "module '$module' does not exist or does not have sub '$sub'" unless ref($subref) eq 'CODE';

    $subref->(@args);
}

1;
