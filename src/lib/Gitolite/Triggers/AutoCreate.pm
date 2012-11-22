package Gitolite::Triggers::AutoCreate;

use strict;
use warnings;

# perl trigger set for stuff to do with auto-creating repos
# ----------------------------------------------------------------------

# to deny auto-create on read access, add 'AutoCreate::deny_R' to the
# PRE_CREATE trigger list
sub deny_R {
    die "autocreate denied\n" if $_[3] and $_[3] eq 'R';
    return;
}

# to deny auto-create on read *and* write access, add 'AutoCreate::deny_RW' to
# the PRE_CREATE trigger list.  This means you can only create repos using the
# 'create' command, (which needs to be enabled in the COMMANDS list).
sub deny_RW {
    die "autocreate denied\n" if $_[3] and ( $_[3] eq 'R' or $_[3] eq 'W' );
    return;
}

1;
