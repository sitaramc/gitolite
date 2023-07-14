package Gitolite::Conf::Load;

# load conf data from stored files
# ----------------------------------------------------------------------

@EXPORT = qw(
  load

  access
  git_config
  env_options

  option
  repo_missing
  creator

  vrefs
  lister_dispatch
);

use Exporter 'import';
use Cwd;

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# ----------------------------------------------------------------------

# our variables, because they get loaded by a 'do'
our $data_version = '';
our %repos;
our %one_repo;
our %groups;
our %patterns;
our %configs;
our %one_config;
our %split_conf;

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

{
    my $loaded_repo = '';

    sub load {
        my $repo = shift or _die "load() needs a reponame";
        trace( 3, "$repo" );
        if ( $repo ne $loaded_repo ) {
            load_common();
            load_1($repo);
            $loaded_repo = $repo;
        }
    }
}

sub access {
    my ( $repo, $user, $aa, $ref ) = @_;
    trace( 2, $repo, $user, $aa, $ref );
    _die "invalid user '$user'" if not( $user and $user =~ $USERNAME_PATT );
    sanity($repo);
    return "$aa any $repo $user DENIED by fallthru" unless update_hook_present($repo);

    my @rules;
    my $deny_rules;

    load($repo);
    @rules = rules( $repo, $user );
    $deny_rules = option( $repo, 'deny-rules' );

    # sanity check the only piece the user can control
    _die "invalid characters in ref or filename: '$ref'\n" unless $ref =~ m(^VREF/NAME/) or $ref =~ $REF_OR_FILENAME_PATT;
    # apparently we can't always force sanity; at least what we *return*
    # should be sane/safe.  This pattern is based on REF_OR_FILENAME_PATT.
    ( my $safe_ref = $ref ) =~ s([^-0-9a-zA-Z._\@/+ :,])(.)g;
    trace( 3, "safe_ref", $safe_ref ) if $ref ne $safe_ref;

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
        return "$aa $safe_ref $repo $user DENIED by existence";
    }

    trace( 3, scalar(@rules) . " rules found" );

    $rc{RULE_TRACE} = '';
    for my $r (@rules) {
        $rc{RULE_TRACE} .= " " . $r->[0] . " ";

        my $perm = $r->[1];
        my $refex = $r->[2]; $refex =~ s(/USER/)(/$user/);
        trace( 3, "perm=$perm, refex=$refex" );

        $rc{RULE_TRACE} .= "d";
        # skip 'deny' rules if the ref is not (yet) known
        next if $perm eq '-' and $ref eq 'any' and not $deny_rules;

        $rc{RULE_TRACE} .= "r";
        # rule matches if ref matches or ref is any (see gitolite-shell)
        next unless $ref =~ /^$refex/ or $ref eq 'any';

        $rc{RULE_TRACE} .= "D";
        trace( 2, "DENIED by $refex" ) if $perm eq '-';
        return "$aa $safe_ref $repo $user DENIED by $refex" if $perm eq '-';

        # For repo creation, perm will be C and aa will be "^C".  For branch
        # access, $perm can be RW\+?(C|D|CD|DC)?M?, and $aa can be W, +, C or
        # D, or any of these followed by "M".

        # We need to turn $aa into a regex that can match a suitable $perm.
        # This is trivially true for "^C", "W" and "D", but the others (+, C,
        # M) need some tweaking.

        # first, quote the '+':
        ( my $aaq = $aa ) =~ s/\+/\\+/;
        # if aa is just "C", the user is trying to create a *branch* (not a
        # *repo*), so let's make the pattern clearer to reflect that.
        $aaq = "RW.*C" if $aaq eq "C";
        # if the aa is, say "WM", make this "W.*M" because the perm could be
        # 'RW+M', 'RW+CDM' etc, and they are all valid:
        $aaq =~ s/M/.*M/;

        $rc{RULE_TRACE} .= "A";

        # as far as *this* ref is concerned we're ok
        return $refex if ( $perm =~ /$aaq/ );

        $rc{RULE_TRACE} .= "p";
    }
    $rc{RULE_TRACE} .= " F";

    trace( 2, "DENIED by fallthru" );
    return "$aa $safe_ref $repo $user DENIED by fallthru";
}

# cache control
if ($rc{CACHE}) {
    require Gitolite::Cache;
    Gitolite::Cache::cache_wrap('Gitolite::Conf::Load::access');
}

sub git_config {
    my ( $repo, $key, $empty_values_OK ) = @_;
    $key ||= '.';

    if ( repo_missing($repo) ) {
        load_common();
    } else {
        load($repo);
    }

    # read comments bottom up
    my %ret =
      # and take the second and third elements to make up your new hash
      map { $_->[1] => $_->[2] }
      # keep only the ones where the second element matches your key
      grep { $_->[1] =~ qr($key) }
      # sort this list of listrefs by the first element in each list ref'd to
      sort { $a->[0] <=> $b->[0] }
      # dereference it (into a list of listrefs)
      map { @$_ }
      # take the value of that entry
      map { $configs{$_} }
      # if it has an entry in %configs
      grep { $configs{$_} }
      # for each "repo" that represents us
      memberships( 'repo', $repo );

    # %configs looks like this (for each 'foo' that is in memberships())
    # 'foo' => [ [ 6, 'foo.bar', 'repo' ], [ 7, 'foodbar', 'repoD' ], [ 8, 'foo.czar', 'jule' ] ],
    # the first map gets you the value
    #          [ [ 6, 'foo.bar', 'repo' ], [ 7, 'foodbar', 'repoD' ], [ 8, 'foo.czar', 'jule' ] ],
    # the deref gets you
    #            [ 6, 'foo.bar', 'repo' ], [ 7, 'foodbar', 'repoD' ], [ 8, 'foo.czar', 'jule' ]
    # the sort rearranges it (in this case it's already sorted but anyway...)
    # the grep gets you this, assuming the key is foo.bar (and "." is regex ".')
    #            [ 6, 'foo.bar', 'repo' ], [ 7, 'foodbar', 'repoD' ]
    # and the final map does this:
    #                 'foo.bar'=>'repo'  ,      'foodbar'=>'repoD'

    # now some of these will have an empty key; we need to delete them unless
    # we're told empty values are OK
    unless ($empty_values_OK) {
        my ( $k, $v );
        while ( ( $k, $v ) = each %ret ) {
            delete $ret{$k} if not $v;
        }
    }

    my ( $k, $v );
    my $creator = creator($repo);
    while ( ( $k, $v ) = each %ret ) {
        $v =~ s/%GL_REPO/$repo/g;
        $v =~ s/%GL_CREATOR/$creator/g if $creator;
        $ret{$k} = $v;
    }

    map { trace( 3, "$_", "$ret{$_}" ) } ( sort keys %ret ) if $ENV{D};
    return \%ret;
}

sub env_options {
    return unless -f "$rc{GL_ADMIN_BASE}/conf/gitolite.conf-compiled.pm";
    # prevent catch-22 during initial install

    my $cwd = getcwd();

    my $repo = shift;
    map { delete $ENV{$_} } grep { /^GL_OPTION_/ } keys %ENV;
    my $h = git_config( $repo, '^gitolite-options.ENV\.' );
    while ( my ( $k, $v ) = each %$h ) {
        next unless $k =~ /^gitolite-options.ENV\.(\w+)$/;
        $ENV{ "GL_OPTION_" . $1 } = $v;
    }

    chdir($cwd);
}

sub option {
    my ( $repo, $option ) = @_;
    $option = "gitolite-options.$option";
    my $ret = git_config( $repo, "^\Q$option\E\$" );
    return '' unless %$ret;
    return $ret->{$option};
}

sub sanity {
    my ($repo, $patt) = @_;
    $patt ||= $REPOPATT_PATT;

    _die "invalid repo '$repo'" if not( $repo and $repo =~ $patt );
    _die "'$repo' ends with a '/'"  if $repo =~ m(/$);
    _die "'$repo' contains '..'"    if $repo =~ $REPONAME_PATT and $repo =~ m(\.\.);
    _die "'$repo' contains '.git/'" if $repo =~ $REPONAME_PATT and $repo =~ m(\.git/);
    _die "'$repo' ends with '.git'" if $repo =~ m(\.git$);
}

sub repo_missing {
    my $repo = shift;
    sanity($repo);

    return not -d "$rc{GL_REPO_BASE}/$repo.git";
}

# ----------------------------------------------------------------------

sub load_common {

    _chdir( $rc{GL_ADMIN_BASE} );

    # we take an unusual approach to caching this function!
    # (requires that first call to load_common is before first call to load_1)
    if ( $last_repo and $split_conf{$last_repo} ) {
        delete $repos{$last_repo};
        delete $configs{$last_repo};
        return;
    }

    my $cc = "./conf/gitolite.conf-compiled.pm";

    _die "parse '$cc' failed: " . ( $! or $@ ) unless do $cc;

    if ( data_version_mismatch() ) {
        _system("gitolite setup");
        _die "parse '$cc' failed: " . ( $! or $@ ) unless do $cc;
        _die "data version update failed; this is serious" if data_version_mismatch();
    }
}

sub load_1 {
    my $repo = shift;
    return if $repo =~ /^\@/;
    trace( 3, $repo );

    if ( repo_missing($repo) ) {
        trace( 1, "repo '$repo' missing" ) if $repo =~ $REPONAME_PATT;
        return;
    }
    _chdir("$rc{GL_REPO_BASE}/$repo.git");

    if ( $repo eq $last_repo ) {
        $repos{$repo} = $one_repo{$repo};
        $configs{$repo} = $one_config{$repo} if $one_config{$repo};
        return;
    }

    if ( -f "gl-conf" ) {
        return if not $split_conf{$repo} and not $rc{ALLOW_ORPHAN_GL_CONF};

        my $cc = "./gl-conf";
        _die "parse '$cc' failed: " . ( $@ or $! ) unless do $cc;

        $last_repo = $repo;
        $repos{$repo} = $one_repo{$repo};
        $configs{$repo} = $one_config{$repo} if $one_config{$repo};
    } else {
        _die "split conf set, gl-conf not present for '$repo'" if $split_conf{$repo};
    }
}

{
    my $lastrepo = '';
    my $lastuser = '';
    my @cached   = ();

    sub rules {
        my ( $repo, $user ) = @_;
        trace( 3, $repo, $user );

        return @cached if ( $lastrepo eq $repo and $lastuser eq $user and @cached );

        my @rules = ();

        my @repos = memberships( 'repo', $repo );
        my @users = memberships( 'user', $user, $repo );
        trace( 3, "memberships: " . scalar(@repos) . " repos and " . scalar(@users) . " users found" );

        for my $r (@repos) {
            for my $u (@users) {
                push @rules, @{ $repos{$r}{$u} } if exists $repos{$r} and exists $repos{$r}{$u};
            }
        }

        @rules = sort { $a->[0] <=> $b->[0] } @rules;

        $lastrepo = $repo;
        $lastuser = $user;
        @cached   = @rules;

        # however if the repo was missing, invalidate the cache
        $lastrepo = '' if repo_missing($repo);

        return @rules;
    }

    sub vrefs {
        my ( $repo, $user ) = @_;
        # fill the cache if needed
        rules( $repo, $user ) unless ( $lastrepo eq $repo and $lastuser eq $user and @cached );

        my %seen;
        my @vrefs = grep { /^VREF\// and not $seen{$_}++ } map { $_->[2] } @cached;
        return @vrefs;
    }
}

sub memberships {
    trace( 3, @_ );
    my ( $type, $base, $repo ) = @_;
    $repo ||= '';
    my @ret;
    my $base2 = '';

    @ret = ( $base, '@all' );

    if ( $type eq 'repo' ) {
        # first, if a repo, say, pub/sitaram/project, has a gl-creator file
        # that says "sitaram", find memberships for pub/CREATOR/project also
        $base2 = generic_name($base);

        # second, you need to check in %repos also
        for my $i ( keys %repos, keys %configs ) {
            if ( $base eq $i or $base =~ /^$i$/ or $base2 and ( $base2 eq $i or $base2 =~ /^$i$/ ) ) {
                push @ret, $i;
            }
        }

        # add in any group names explicitly given in (GIT_DIR)/gl-repo-groups
        push @ret,
            map { s/^\@?/\@/; $_ }
            grep { ! /[^\w@-]/ }
            split (' ', slurp("$ENV{GL_REPO_BASE}/$base.git/gl-repo-groups"))
                if -f         "$ENV{GL_REPO_BASE}/$base.git/gl-repo-groups";
    }

    push @ret, @{ $groups{$base} } if exists $groups{$base};
    push @ret, @{ $groups{$base2} } if $base2 and exists $groups{$base2};
    if ($type eq 'repo') {
        # regexes can only be used for repos, not for users
        for my $i ( keys %{ $patterns{groups} } ) {
            if ( $base =~ /^$i$/ or $base2 and ( $base2 =~ /^$i$/ ) ) {
                push @ret, @{ $groups{$i} };
            }
        }
    }

    push @ret, @{ ext_grouplist($base) } if $type eq 'user' and $rc{GROUPLIST_PGM};

    if ( $type eq 'user' and $repo and not repo_missing($repo) ) {
        # find the roles this user has when accessing this repo and add those
        # in as groupnames he is a member of.  You need the already existing
        # memberships for this; see below this function for an example
        push @ret, user_roles( $base, $repo, @ret );
    }

    @ret = @{ sort_u( \@ret ) };
    trace( 3, sort @ret );
    return @ret;
}

=for example

conf/gitolite.conf:
    @g1 = u1
    @g2 = u1
    # now user is a member of both g1 and g2

gl-perms for repo being accessed:
    READERS @g1

This should result in @READERS being added to the memberships that u1 has
(when accessing this repo).  So we send the current list (@g1, @g2) to
user_roles(), otherwise it has to redo that logic.

=cut

sub data_version_mismatch {
    return $data_version ne glrc('current-data-version');
}

sub user_roles {
    my ( $user, $repo, @eg ) = @_;

    # eg == existing groups (that user is already known to be a member of)
    my %eg = map { $_ => 1 } @eg;

    my %ret   = ();
    my $f     = "$rc{GL_REPO_BASE}/$repo.git/gl-perms";
    my @roles = ();
    if ( -f $f ) {
        my $fh = _open( "<", $f );
        chomp( @roles = <$fh> );
    }
    push @roles, "CREATOR = " . creator($repo);
    for (@roles) {
        # READERS u3 u4 @g1
        s/^\s+//; s/ +$//; s/=/ /; s/\s+/ /g; s/^\@//;
        next if /^#/;
        next unless /\S/;
        my ( $role, @members ) = split;
        # role = READERS, members = u3, u4, @g1
        if ( $role ne 'CREATOR' and not $rc{ROLES}{$role} ) {
            _warn "role '$role' not allowed, ignoring";
            next;
        }
        for my $m (@members) {
            if ( $m !~ $USERNAME_PATT ) {
                _warn "ignoring '$m' in perms line";
                next;
            }
            # if user eq u3/u4, or is a member of @g1, he has role READERS
            $ret{ '@' . $role } = 1 if $m eq $user or $eg{$m};
        }
    }

    return keys %ret;
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
    $base2 =~ s(\b$creator\b)(CREATOR) if $creator;
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

{
    my %cache = ();

    sub ext_grouplist {
        my $user = shift;
        my $pgm  = $rc{GROUPLIST_PGM};
        return [] if not $pgm;

        return $cache{$user} if $cache{$user};
        my @extgroups = map { s/^@?/@/; $_; } split ' ', `$rc{GROUPLIST_PGM} $user`;
        return ( $cache{$user} = \@extgroups );
    }
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

    load_common();

    my @g = ();
    while ( my ( $k, $v ) = each(%groups) ) {
        push @g, @{$v};
    }
    return ( sort_u( \@g ) );
}

=for list_users
Usage:  gitolite list-users [<repo name pattern>]

List all users and groups explicitly named in a rule.

-   you will have to run 'list-members' on each group name to expand it -- for
    details and caveats on that please see its help message.
-   User names not mentioned in an access rule will not show up at all (for
    example, if you have users who only have access via an '@all' rule).

WARNING: may be slow if you have thousands of repos.  The optional repo name
pattern is an unanchored regex; it can speed things up if you're interested
only in users of a matching set of repos.  This is only an optimisation, not
an actual access list; you will still have to pipe it to 'gitolite access'
with appropriate arguments to get an actual access list.

NOTE: If you're running in ssh mode, it may be simpler to parse the authorized
keys file in ~/.ssh, like so:
    perl -lne '/ ([a-z0-9]+)"/; print $1 if $1' < ~/.ssh/authorized_keys | sort -u
If you're running in http mode, only your web server knows all the potential
user names.
=cut

sub list_users {
    my $patt = shift || '.';
    usage() if $patt eq '-h' or @_;
    my $count = 0;
    my $total = 0;

    load_common();

    my @u = map { keys %{$_} } values %repos;
    $total = scalar( grep { /$patt/ } keys %split_conf );
    warn "WARNING: you have $total repos to check; this could take some time!\n" if $total > 100;
    for my $one ( grep { /$patt/ } keys %split_conf ) {
        load_1($one);
        $count++; print STDERR "$count / $total\r" if not( $count % 100 ) and timer(5);
        push @u, map { keys %{$_} } values %one_repo;
    }
    print STDERR "\n" if $count >= 100;
    return ( sort_u( \@u ) );
}

=for list_repos
Usage:  gitolite list-repos

  - lists all repos/repo groups in conf
  - no options, no flags
=cut

sub list_repos {
    usage() if @_;

    load_common();

    my @r = keys %repos;
    push @r, keys %split_conf;

    return ( sort_u( \@r ) );
}

=for list_memberships
Usage:  gitolite list-memberships -u|-r <name>

List all groups a name is a member of.  One of the flags '-u' or '-r' is
mandatory, to specify if the name is a user or a repo.

For users, the output includes the result from GROUPLIST_PGM, if it is
defined.  For repos, the output includes any repo patterns that the repo name
matches, as well as any groups that contain those patterns.
=cut

sub list_memberships {
    require Getopt::Long;

    my ( $user, $repo, $help );

    Getopt::Long::GetOptionsFromArray(
        \@_,
        'user|u=s' => \$user,
        'repo|r=s' => \$repo,
        'help|h'   => \$help,
    );
    usage() if $help or ( not $user and not $repo );

    load_common();
    my @m;

    if ( $user and $repo ) {
        # unsupported/undocumented except via "in_role()" in Easy.pm
        @m = memberships( 'user', $user, $repo );
    } elsif ($user) {
        @m = memberships( 'user', $user );
    } elsif ($repo) {
        @m = memberships( 'repo', $repo );
    }

    @m = grep { $_ ne '@all' and $_ ne ( $user || $repo ) } @m;
    return ( sort_u( \@m ) );
}

=for list_members
Usage:  gitolite list-members <group name>

  - list all members of a group
  - takes one group name

'@all' is not expandable in this context.  Also, if you have GROUPLIST_PGM set
in your rc file[1], gitolite cannot expand group names completely; only your
external database can.

[1]: http://gitolite.com/gitolite/conf.html#getting-user-group-info-from-ldap

=cut

sub list_members {
    usage() if @_ and $_[0] eq '-h' or not @_;

    my $name = shift;

    load_common();

    my @m = ();
    while ( my ( $k, $v ) = each(%groups) ) {
        for my $g ( @{$v} ) {
            push @m, $k if $g eq $name;
        }
    }

    return ( sort_u( \@m ) );
}

# ----------------------------------------------------------------------

{
    my $start_time = 0;

    sub timer {
        unless ($start_time) {
            $start_time = time();
            return 0;
        }
        my $elapsed = shift;
        return 0 if time() - $start_time < $elapsed;
        $start_time = time();
        return 1;
    }
}

1;

