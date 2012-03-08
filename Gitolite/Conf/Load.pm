package Gitolite::Conf::Load;

# load conf data from stored files
# ----------------------------------------------------------------------

@EXPORT = qw(
  load
  access

  list_groups
  list_users
  list_repos
  list_memberships
  list_members
);

use Exporter 'import';

use lib $ENV{GL_BINDIR};
use Gitolite::Common;
use Gitolite::Rc;

use strict;
use warnings;

# ----------------------------------------------------------------------

my $subconf = 'master';

# our variables, because they get loaded by a 'do'
our $data_version = '';
our %repos;
our %one_repo;
our %groups;
our %configs;
our %one_config;
our %split_conf;

# helps maintain the "cache" in both "load_common" and "load_1"
my $last_repo = '';

# ----------------------------------------------------------------------

{
    my $loaded_repo = '';

    sub load {
        my $repo = shift or _die "load() needs a reponame";
        trace( 4, "$repo" );
        if ( $repo ne $loaded_repo ) {
            trace( 3, "loading $repo..." );
            load_common();
            load_1($repo);
            $loaded_repo = $repo;
        }
    }
}

sub access {
    my ( $repo, $user, $aa, $ref ) = @_;
    trace( 3, "repo=$repo, user=$user, aa=$aa, ref=$ref" );
    load($repo);

    my @rules = rules( $repo, $user );
    trace( 3, scalar(@rules) . " rules found" );
    for my $r (@rules) {
        my $perm  = $r->[1];
        my $refex = $r->[2];
        trace( 4, "perm=$perm, refex=$refex" );

        # skip 'deny' rules if the ref is not (yet) known
        next if $perm eq '-' and $ref eq 'unknown';

        # rule matches if ref matches or ref is unknown (see gitolite-shell)
        next unless $ref =~ /^$refex/ or $ref eq 'unknown';

        trace( 3, "DENIED by $refex" ) if $perm eq '-';
        return "DENIED: $aa access to $repo by $user (rule: $refex)" if $perm eq '-';

        # $perm can be RW\+?(C|D|CD|DC)?M?.  $aa can be W, +, C or D, or
        # any of these followed by "M".
        ( my $aaq = $aa ) =~ s/\+/\\+/;
        $aaq =~ s/M/.*M/;
        # as far as *this* ref is concerned we're ok
        return $refex if ( $perm =~ /$aaq/ );
    }
    trace( 3, "DENIED by fallthru" );
    return "DENIED: $aa access to $repo by $user (fallthru)";
}

# ----------------------------------------------------------------------

sub load_common {

    _chdir("$GL_ADMIN_BASE");

    # we take an unusual approach to caching this function!
    # (requires that first call to load_common is before first call to load_1)
    if ( $last_repo and $split_conf{$last_repo} ) {
        delete $repos{$last_repo};
        delete $configs{$last_repo};
        return;
    }

    trace(4);
    my $cc = "conf/gitolite.conf-compiled.pm";

    _die "parse $cc failed: " . ( $! or $@ ) unless do $cc;

    if ( data_version_mismatch() ) {
        system("gitolite setup");
        _die "parse $cc failed: " . ( $! or $@ ) unless do $cc;
        _die "data version update failed; this is serious" if data_version_mismatch();
    }
}

sub load_1 {
    my $repo = shift;
    trace( 4, $repo );

    _chdir("$GL_REPO_BASE");

    if ( $repo eq $last_repo ) {
        $repos{$repo} = $one_repo{$repo};
        $configs{$repo} = $one_config{$repo} if $one_config{$repo};
        return;
    }

    if ( -f "$repo.git/gl-conf" ) {
        _die "split conf not set, gl-conf present for $repo" if not $split_conf{$repo};

        my $cc = "$repo.git/gl-conf";
        _die "parse $cc failed: " . ( $! or $@ ) unless do $cc;

        $last_repo = $repo;
        $repos{$repo} = $one_repo{$repo};
        $configs{$repo} = $one_config{$repo} if $one_config{$repo};
    } else {
        _die "split conf set, gl-conf not present for $repo" if $split_conf{$repo};
    }
}

sub rules {
    my ( $repo, $user ) = @_;
    trace( 4, "repo=$repo, user=$user" );
    my @rules = ();

    my @repos = memberships($repo);
    my @users = memberships($user);
    trace( 4, "memberships: " . scalar(@repos) . " repos and " . scalar(@users) . " users found" );

    for my $r (@repos) {
        for my $u (@users) {
            push @rules, @{ $repos{$r}{$u} } if exists $repos{$r}{$u};
        }
    }

    # dbg("before sorting rules:", \@rules);
    @rules = sort { $a->[0] <=> $b->[0] } @rules;
    # dbg("after sorting rules:", \@rules);

    return @rules;
}

sub memberships {
    my $item = shift;

    my @ret = ( $item, '@all' );
    push @ret, @{ $groups{$item} } if $groups{$item};

    return @ret;
}

sub data_version_mismatch {
    return $data_version ne $current_data_version;
}

# ----------------------------------------------------------------------
# api functions
# ----------------------------------------------------------------------

# list all groups
sub list_groups {
    die "
Usage:  gitolite list-groups

  - lists all group names in conf
  - no options, no flags

" if @ARGV;

    load_common();

    my @g = ();
    while (my ($k, $v) = each ( %groups )) {
        push @g, @{ $v };
    }
    return (sort_u(\@g));
}

sub list_users {
    my $count = 0;
    my $total = 0;

    die "
Usage:  gitolite list-users

  - lists all users/user groups in conf
  - no options, no flags
  - WARNING: may be slow if you have thousands of repos

" if @ARGV;

    load_common();

    my @u = map { keys %{ $_ } } values %repos;
    $total = scalar(keys %split_conf);
    warn "WARNING: you have $total repos to check; this could take some time!\n" if $total > 100;
    for my $one ( keys %split_conf ) {
        load_1($one);
        $count++; print STDERR "$count / $total\r" if not ( $count % 100 ) and timer(5);
        push @u, map { keys %{ $_ } } values %one_repo;
    }
    print STDERR "\n";
    return (sort_u(\@u));
}


sub list_repos {

    die "
Usage:  gitolite list-repos

  - lists all repos/repo groups in conf
  - no options, no flags

" if @ARGV;

    load_common();

    my @r = keys %repos;
    push @r, keys %split_conf;

    return (sort_u(\@r));
}

sub list_memberships {

    die "
Usage:  gitolite list-memberships <name>

  - list all groups a name is a member of
  - takes one user/repo name

" if @ARGV and $ARGV[0] eq '-h' or not @ARGV and not @_;

    my $name = ( @_ ? shift @_ : shift @ARGV );

    load_common();
    my @m = memberships($name);
    return (sort_u(\@m));
}

sub list_members {

    die "
Usage:  gitolite list-members <group name>

  - list all members of a group
  - takes one group name

" if @ARGV and $ARGV[0] eq '-h' or not @ARGV and not @_;

    my $name = ( @_ ? shift @_ : shift @ARGV );

    load_common();

    my @m = ();
    while (my ($k, $v) = each ( %groups )) {
        for my $g ( @{ $v } ) {
            push @m, $k if $g eq $name;
        }
    }

    return (sort_u(\@m));
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

