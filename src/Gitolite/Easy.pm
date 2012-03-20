package Gitolite::Easy;

# easy access to gitolite from external perl programs
# ----------------------------------------------------------------------
# most/all functions in this module test $ENV{GL_USER}'s rights and
# permissions so it needs to be set.

#<<<
@EXPORT = qw(
  is_admin
  is_super_admin
  in_group
  owns
  can_read
  can_write

  %rc
  say
  say2
  _print
  usage
);
#>>>
use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

my $user;

# ----------------------------------------------------------------------

# shell equivalent
#   if gitolite access -q gitolite-admin $GL_USER W; then ...
sub is_admin {
    valid_user();
    return not( access( 'gitolite-admin', $user, 'W', 'any' ) =~ /DENIED/ );
}

# shell equivalent
#   if gitolite access -q gitolite-admin $GL_USER W VREF/NAME/; then ...
sub is_super_admin {
    valid_user();
    return not( access( 'gitolite-admin', $user, 'W', 'VREF/NAME/' ) =~ /DENIED/ );
}

# shell equivalent
#   if gitolite list-memberships $GL_USER | grep -x $GROUPNAME >/dev/null; then ...
sub in_group {
    valid_user();
    my $g = shift;

    return grep { $_ eq $g } @{ list_memberships($user) };
}

# shell equivalent
#   if gitolite creator $REPONAME $GL_USER; then ...
sub owns {
    valid_user();
    my $r = shift;

    # prevent unnecessary disclosure of repo existence info
    return 0 if repo_missing($r);

    return ( creator($r) eq $user );
}

# shell equivalent
#   if gitolite access -q $REPONAME $GL_USER R; then ...
sub can_read {
    valid_user();
    my $r = shift;
    return not( access( $r, $user, 'R', 'any' ) =~ /DENIED/ );
}

# shell equivalent
#   if gitolite access -q $REPONAME $GL_USER W; then ...
sub can_write {
    valid_user();
    my $r = shift;
    return not( access( $r, $user, 'W', 'any' ) =~ /DENIED/ );
}

# ----------------------------------------------------------------------

sub valid_user {
    _die "GL_USER not set" unless exists $ENV{GL_USER};
    $user = $ENV{GL_USER};
}

1;
