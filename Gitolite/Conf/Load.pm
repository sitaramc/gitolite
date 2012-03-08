package Gitolite::Conf::Load;

# load conf data from stored files
# ----------------------------------------------------------------------

@EXPORT = qw(
  load
  access
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
            _chdir("$GL_ADMIN_BASE"); load_common();
            _chdir("$GL_REPO_BASE");  load_1($repo);
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

1;

