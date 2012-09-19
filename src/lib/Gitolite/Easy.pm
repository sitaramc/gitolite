package Gitolite::Easy;

# easy access to gitolite from external perl programs
# ----------------------------------------------------------------------
# most/all functions in this module test $ENV{GL_USER}'s rights and
# permissions so it needs to be set.

# "use"-ing this module
# ----------------------------------------------------------------------
# Using this module from within a gitolite trigger or command is easy; you
# just need 'use lib $ENV{GL_LIBDIR};' before the 'use Gitolite::Easy;'.
#
# Using it from something completely outside gitolite requires a bit more
# work.  First, run 'gitolite query-rc -a' to find the correct values for
# GL_BINDIR and GL_LIBDIR in your installation.  Then use this code in your
# external program, using the paths you just found:
#
#   BEGIN {
#       $ENV{GL_BINDIR} = "/full/path/to/gitolite/src";
#       $ENV{GL_LIBDIR} = "/full/path/to/gitolite/src/lib";
#   }
#   use lib $ENV{GL_LIBDIR};
#   use Gitolite::Easy;

# API documentation
# ----------------------------------------------------------------------
# documentation for each function is at the top of the function.
# Documentation is NOT in pod format; just read the source with a nice syntax
# coloring text editor and you'll be happy enough.  (I do not like POD; please
# don't send me patches for this aspect of the module).

#<<<
@EXPORT = qw(
  is_admin
  is_super_admin
  in_group

  owns
  can_read
  can_write

  config

  %rc
  say
  say2
  _die
  _warn
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

# is_admin()

# return true if $ENV{GL_USER} is set and has W perms to the admin repo

# shell equivalent
#   if gitolite access -q gitolite-admin $GL_USER W; then ...

sub is_admin {
    valid_user();
    return not( access( 'gitolite-admin', $user, 'W', 'any' ) =~ /DENIED/ );
}

# is_super_admin()

# (useful only if you are using delegation)

# return true if $ENV{GL_USER} is set and has W perms to any file in the admin
# repo

# shell equivalent
#   if gitolite access -q gitolite-admin $GL_USER W VREF/NAME/; then ...
sub is_super_admin {
    valid_user();
    return not( access( 'gitolite-admin', $user, 'W', 'VREF/NAME/' ) =~ /DENIED/ );
}

# in_group()

# return true if $ENV{GL_USER} is set and is in the given group

# shell equivalent
#   if gitolite list-memberships $GL_USER | grep -x $GROUPNAME >/dev/null; then ...
sub in_group {
    valid_user();
    my $g = shift;
    $g =~ s/^\@?/@/;

    return grep { $_ eq $g } @{ Gitolite::Conf::Load::list_memberships($user) };
}

# owns()

# return true if $ENV{GL_USER} is set and is the creator of the given repo

# shell equivalent
#   if gitolite creator $REPONAME $GL_USER; then ...
sub owns {
    valid_user();
    my $r = shift;

    # prevent unnecessary disclosure of repo existence info
    return 0 if repo_missing($r);

    return ( creator($r) eq $user );
}

# can_read()
# return true if $ENV{GL_USER} is set and can read the given repo

# shell equivalent
#   if gitolite access -q $REPONAME $GL_USER R; then ...
sub can_read {
    valid_user();
    my $r = shift;
    return not( access( $r, $user, 'R', 'any' ) =~ /DENIED/ );
}

# can_write()
# return true if $ENV{GL_USER} is set and can write to the given repo.
# Optional second argument can be '+' to check that instead of 'W'.  Optional
# third argument can be a full ref name instead of 'any'.

# shell equivalent
#   if gitolite access -q $REPONAME $GL_USER W; then ...
sub can_write {
    valid_user();
    my ($r, $aa, $ref) = @_;
    $aa ||= 'W';
    $ref ||= 'any';
    return not( access( $r, $user, $aa, $ref ) =~ /DENIED/ );
}

# config()
# given a repo and a key, return a hash containing all the git config
# variables for that repo where the section+key match the regex.  If none are
# found, return an empty hash.  If you don't want it as a regex, use \Q
# appropriately

# shell equivalent
#   foo=$(gitolite git-config -r $REPONAME foo\\.bar)
sub config {
    my $repo = shift;
    my $key  = shift;

    return () if repo_missing($repo);

    my $ret = git_config( $repo, $key );
    return %$ret;
}

# ----------------------------------------------------------------------

sub valid_user {
    _die "GL_USER not set" unless exists $ENV{GL_USER};
    $user = $ENV{GL_USER};
}

1;
