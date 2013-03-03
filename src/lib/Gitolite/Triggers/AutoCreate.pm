package Gitolite::Triggers::AutoCreate;

use strict;
use warnings;

# perl trigger set for stuff to do with auto-creating repos
# ----------------------------------------------------------------------

# to deny auto-create on read access, uncomment 'no-create-on-read' in the
# ENABLE list in the rc file
sub deny_R {
    die "autocreate denied\n" if $_[3] and $_[3] eq 'R';
    return;
}

# to deny auto-create on read *and* write, uncomment 'no-auto-create' in the
# ENABLE list in the rc file.  This means you can only create wild repos using
# the 'create' command, (which needs to be enabled in the ENABLE list).
sub deny_RW {
    die "autocreate denied\n" if $_[3] and ( $_[3] eq 'R' or $_[3] eq 'W' );
    return;
}

1;
