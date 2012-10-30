package Gitolite::Conf::Load;

# load conf data from stored files
# ----------------------------------------------------------------------

@EXPORT = qw(
  access
  git_config

  option
  repo_missing
  creator

  vrefs
  lister_dispatch
);

use Exporter 'import';

use Gitolite::Redis;
use Gitolite::Common;
use Gitolite::Rc;

use strict;
use warnings;

# ----------------------------------------------------------------------

# our variables, because they get loaded by a 'do'
our $data_version = '';

my $subconf = 'master';

my %listers = (
    'list-groups'      => \&list_groups,
    'list-users'       => \&list_users,
    'list-repos'       => \&list_repos,
    'list-memberships' => \&list_memberships,
    'list-members'     => \&list_members,
);

# helps maintain the "cache" in both "load_common" and "load_1"
my $last_repo = '';

# ----------------------------------------------------------------------

sub access {
    my ( $repo, $user, $aa, $ref ) = @_;
    _die "invalid user '$user'" if not( $user and $user =~ $USERNAME_PATT );
    sanity($repo);

    my $deny_rules = option( $repo, 'deny-rules' );

    # sanity check the only piece the user can control
    _die "invalid characters in ref or filename: '$ref'\n" unless $ref =~ $REF_OR_FILENAME_PATT;

    # when a real repo doesn't exist, ^C is a pre-requisite for any other
    # check to give valid results.
    if ( $aa ne '^C' and $repo !~ /^\@/ and $repo =~ $REPONAME_PATT and repo_missing($repo) ) {
        my $iret = access( $repo, $user, '^C', $ref );
        $iret =~ s/\^C/$aa/;
        return $iret if $iret =~ /DENIED/;
    }
    # similarly, ^C must be denied if the repo exists
    if ( $aa eq '^C' and not repo_missing($repo) ) {
        trace( 2, "DENIED by existence" );
        return "$aa $ref $repo $user DENIED by existence";
    }

    my @rules = db_rules($repo, generic_name($repo), $user);
    trace( 2, scalar(@rules) . " rules found" );
    for my $r (@rules) {
        my $perm = $r->[0];
        my $refex = $r->[1]; $refex =~ s(/USER/)(/$user/);
        trace( 3, "perm=$perm, refex=$refex" );

        # skip 'deny' rules if the ref is not (yet) known
        next if $perm eq '-' and $ref eq 'any' and not $deny_rules;

        # rule matches if ref matches or ref is any (see gitolite-shell)
        next unless $ref =~ /^$refex/ or $ref eq 'any';

        trace( 2, "DENIED by $refex" ) if $perm eq '-';
        return "$aa $ref $repo $user DENIED by $refex" if $perm eq '-';

        # $perm can be RW\+?(C|D|CD|DC)?M?.  $aa can be W, +, C or D, or
        # any of these followed by "M".
        ( my $aaq = $aa ) =~ s/\+/\\+/;
        $aaq =~ s/M/.*M/;
        # as far as *this* ref is concerned we're ok
        return $refex if ( $perm =~ /$aaq/ );
    }
    trace( 2, "DENIED by fallthru" );
    return "$aa $ref $repo $user DENIED by fallthru";
}

sub git_config {
    my ( $repo, $key, $empty_values_OK ) = @_;
    $key ||= '.';

    # read comments bottom up
    my %ret =
      # and make up your new hash with matching keys and their values
      map { $_->[0] => $_->[1] }
      # match the first element against the wanted key expression
      grep { $_->[0] =~ qr($key) }
      # get the list of 2-element lists containing configs for this repo
      db_configs($repo, generic_name($repo));

    # now some of these will have an empty key; we need to delete them unless
    # we're told empty values are OK
    unless ($empty_values_OK) {
        my($k, $v);
        while (($k, $v) = each %ret) {
            delete $ret{$k} if not $v;
        }
    }

    trace( 3, map { ( "$_" => "-> $ret{$_}" ) } ( sort keys %ret ) );
    return \%ret;
}

sub option {
    my ( $repo, $option ) = @_;
    $option = "gitolite-options.$option";
    my $ret = git_config( $repo, "^\Q$option\E\$" );
    return '' unless %$ret;
    return $ret->{$option};
}

sub sanity {
    my $repo = shift;

    _die "invalid repo '$repo'" if not( $repo and $repo =~ $REPOPATT_PATT );
    _die "'$repo' ends with a '/'" if $repo =~ m(/$);
    _die "'$repo' contains '..'" if $repo =~ $REPONAME_PATT and $repo =~ m(\.\.);
}

sub repo_missing {
    my $repo = shift;
    sanity($repo);

    return not -d "$rc{GL_REPO_BASE}/$repo.git";
}

# ----------------------------------------------------------------------

sub vrefs {
    my ( $repo, $user ) = @_;
    # fill the cache if needed
    my @rules = db_rules($repo, generic_name($repo), $user);

    my %seen;
    my @vrefs = grep { /^VREF\// and not $seen{$_}++ } map { $_->[1] } @rules;
    return @vrefs;
}

sub data_version_mismatch {
    return $data_version ne glrc('current-data-version');
}

sub generic_name {
    my $base  = shift;
    my $base2 = '';
    my $creator;

    # get the creator name.  For not-yet-born repos this is $ENV{GL_USER},
    # which should be set in all cases that we care about, viz., where we are
    # checking ^C permissions before new_wild_repo(), and the info command.
    # In particular, 'gitolite access' can't be used to check ^C perms on wild
    # repos that contain "CREATOR" if GL_USER is not set.
    $creator = creator($base);

    $base2 = $base;
    $base2 =~ s(/$creator/)(/CREATOR/) if $creator;
    $base2 =~ s(^$creator/)(CREATOR/)  if $creator;
    $base2 = '' if $base2 eq $base;    # if there was no change

    return $base2;
}

sub creator {
    my $repo = shift;
    sanity($repo);

    return ( $ENV{GL_USER} || '' ) if repo_missing($repo);
    my $f       = "$rc{GL_REPO_BASE}/$repo.git/gl-creator";
    my $creator = '';
    chomp( $creator = slurp($f) ) if -f $f;
    return $creator;
}

# ----------------------------------------------------------------------
# api functions
# ----------------------------------------------------------------------

sub lister_dispatch {
    my $command = shift;

    my $fn = $listers{$command} or _die "unknown gitolite sub-command";
    return $fn;
}

=for list_groups
Usage:  gitolite list-groups

  - lists all group names in conf
  - no options, no flags
=cut

sub list_groups {
    usage() if @_;

    my @g = db_get_groups();
    return ( sort_u( \@g ) );
}

=for list_users
Usage:  gitolite list-users

List all users and groups explicitly named in a rule.  User names not
mentioned in an access rule will not show up; you have to run 'list-members'
on each group name yourself to see them.
=cut

sub list_users {
    my $patt = shift || '.';
    usage() if $patt eq '-h' or @_;

    my @u = db_get_userlist();
    return ( sort_u( \@u ) );
}

=for list_repos
Usage:  gitolite list-repos

  - lists all repos/repo groups in conf
  - no options, no flags
=cut

sub list_repos {
    usage() if @_;

    my @r = db_get_repolist();
    return ( sort_u( \@r ) );
}

=for list_memberships
Usage:  gitolite list-memberships <name>

  - list all groups a name is a member of
  - takes one user/repo name
=cut

sub list_memberships {
    usage() if @_ and $_[0] eq '-h' or not @_;

    my $name = shift;
    my @m = db_get_memberships($name);
    return ( sort_u( \@m ) );
}

=for list_members
Usage:  gitolite list-members <group name>

  - list all members of a group
  - takes one group name
=cut

sub list_members {
    usage() if @_ and $_[0] eq '-h' or not @_;

    my $name = shift;
    my @m = db_get_members($name);
    return ( sort_u( \@m ) );
}

1;

