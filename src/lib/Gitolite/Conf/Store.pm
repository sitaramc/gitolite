package Gitolite::Conf::Store;

# receive parsed conf data and store it
# ----------------------------------------------------------------------

@EXPORT = qw(
  add_to_group
  set_repolist
  parse_refs
  parse_users
  add_rule
  add_config
  set_subconf

  expand_list
  new_repos
  new_repo
  new_wild_repo
  hook_repos
  store
  parse_done
);

use Exporter 'import';
use Data::Dumper;
$Data::Dumper::Indent   = 1;
$Data::Dumper::Sortkeys = 1;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Hooks::Update;
use Gitolite::Hooks::PostUpdate;

use strict;
use warnings;

# ----------------------------------------------------------------------

my %repos;
my %groups;
my %configs;
my %split_conf;

my @repolist;    # current repo list; reset on each 'repo ...' line
my $subconf = 'master';
my $nextseq = 0;
my %ignored;

# ----------------------------------------------------------------------

sub add_to_group {
    my ( $lhs, @rhs ) = @_;
    _die "bad group '$lhs'" unless $lhs =~ $REPONAME_PATT;
    map { _die "bad expansion '$_'" unless $_ =~ $REPOPATT_PATT } @rhs;

    # store the group association, but overload it to keep track of when
    # the group was *first* created by using $subconf as the *value*
    do { $groups{$lhs}{$_} ||= $subconf }
      for ( expand_list(@rhs) );

    # create the group hash even if empty
    $groups{$lhs} = {} unless $groups{$lhs};
}

sub set_repolist {
    my @in = @_;
    @repolist = ();
    # ...sanity checks
    while (@in) {
        $_ = shift @in;
        if ( check_subconf_repo_disallowed( $subconf, $_ ) ) {
            if ( exists $groups{$_} ) {
                # groupname disallowed; try individual members now
                ( my $g = $_ ) =~ s/^\@$subconf\./\@/;
                _warn "expanding '$g'; this *may* slow down compilation";
                unshift @in, keys %{ $groups{$_} };
                next;
            }
            $ignored{$subconf}{$_} = 1;
            next;
        }

        _warn "explicit '.git' extension ignored for $_.git" if s/\.git$//;
        _die "bad reponame '$_'" if $_ !~ $REPOPATT_PATT;

        push @repolist, $_;
    }
}

sub parse_refs {
    my $refs = shift;
    my @refs; @refs = split( ' ', $refs ) if $refs;
    @refs = expand_list(@refs);

    # if no ref is given, this PERM applies to all refs
    @refs = qw(refs/.*) unless @refs;

    # fully qualify refs that dont start with "refs/" or "VREF/";
    # prefix them with "refs/heads/"
    @refs = map { m(^(refs|VREF)/) or s(^)(refs/heads/); $_ } @refs;

    return @refs;
}

sub parse_users {
    my $users = shift;
    my @users = split ' ', $users;
    do { _die "bad username '$_'" unless $_ =~ $USERNAME_PATT }
      for @users;

    return @users;
}

sub add_rule {
    my ( $perm, $ref, $user, $fname, $lnum ) = @_;
    _warn "doesn't make sense to supply a ref ('$ref') for 'R' rule"
      if $perm eq 'R' and $ref ne 'refs/.*';
    _warn "possible undeclared group '$user'"
      if $user =~ /^@/
      and not $groups{$user}
      and not $rc{GROUPLIST_PGM}
      and not special_group($user);
    _die "bad ref '$ref'"   unless $ref =~ $REPOPATT_PATT;
    _die "bad user '$user'" unless $user =~ $USERNAME_PATT;

    $nextseq++;
    store_rule_info( $nextseq, $fname, $lnum );
    for my $repo (@repolist) {
        push @{ $repos{$repo}{$user} }, [ $nextseq, $perm, $ref ];
    }

    sub special_group {
        # ok perl doesn't really have lexical subs (at least not the older
        # perls I want to support) but let's pretend...
        my $g = shift;
        $g =~ s/^\@//;
        return 1 if $g eq 'all' or $g eq 'CREATOR';
        return 1 if $rc{ROLES}{$g};
        return 0;
    }

}

sub add_config {
    my ( $n, $key, $value ) = @_;

    $nextseq++;
    for my $repo (@repolist) {
        push @{ $configs{$repo} }, [ $nextseq, $key, $value ];
    }
}

sub set_subconf {
    $subconf = shift;
    _die "bad subconf '$subconf'" unless $subconf =~ /^[-\w.]+$/;
}

# ----------------------------------------------------------------------

sub expand_list {
    my @list     = @_;
    my @new_list = ();

    for my $item (@list) {
        if ( $item =~ /^@/ and $item ne '@all' )    # nested group
        {
            _die "undefined group '$item'" unless $groups{$item};
            # add those names to the list
            push @new_list, sort keys %{ $groups{$item} };
        } else {
            push @new_list, $item;
        }
    }

    return @new_list;
}

sub new_repos {
    trace(3);
    _chdir( $rc{GL_REPO_BASE} );

    # normal repos
    my @repos = grep { $_ =~ $REPONAME_PATT and not /^@/ } ( sort keys %repos, sort keys %configs );
    # add in members of repo groups
    map { push @repos, keys %{ $groups{$_} } } grep { /^@/ and $_ ne '@all' } keys %repos;

    for my $repo ( @{ sort_u( \@repos ) } ) {
        next unless $repo =~ $REPONAME_PATT;    # skip repo patterns
        next if $repo =~ m(^\@|EXTCMD/);        # skip groups and fake repos

        # use gl-conf as a sentinel
        hook_1($repo) if -d "$repo.git" and not -f "$repo.git/gl-conf";

        if ( not -d "$repo.git" ) {
            push @{ $rc{NEW_REPOS_CREATED} }, $repo;
            trigger( 'PRE_CREATE', $repo );
            new_repo($repo);
        }
    }
}

sub new_repo {
    my $repo = shift;
    trace( 3, $repo );

    _mkdir("$repo.git");
    _chdir("$repo.git");
    _system("git init --bare >&2");
    _chdir( $rc{GL_REPO_BASE} );
    hook_1($repo);
}

sub new_wild_repo {
    my ( $repo, $user, $aa ) = @_;
    _chdir( $rc{GL_REPO_BASE} );

    trigger( 'PRE_CREATE', $repo, $user, $aa );
    new_repo($repo);
    _print( "$repo.git/gl-creator", $user );
    trigger( 'POST_CREATE', $repo, $user, $aa );

    _chdir( $rc{GL_ADMIN_BASE} );
}

sub hook_repos {
    trace(3);

    # all repos, all hooks
    _chdir( $rc{GL_REPO_BASE} );
    my $phy_repos = list_phy_repos(1);

    for my $repo ( @{$phy_repos} ) {
        hook_1($repo);
    }
}

sub store {
    trace(3);

    # first write out the ones for the physical repos
    _chdir( $rc{GL_REPO_BASE} );
    my $phy_repos = list_phy_repos(1);

    for my $repo ( @{$phy_repos} ) {
        store_1($repo);
    }

    _chdir( $rc{GL_ADMIN_BASE} );
    store_common();
}

sub parse_done {
    for my $ig ( sort keys %ignored ) {
        _warn "subconf '$ig' attempting to set access for " . join( ", ", sort keys %{ $ignored{$ig} } );
    }

    close_rule_info();
}

# ----------------------------------------------------------------------

sub check_subconf_repo_disallowed {
    # trying to set access for $repo (='foo')...
    my ( $subconf, $repo ) = @_;
    trace( 2, $subconf, $repo );

    # processing the master config, not a subconf
    return 0 if $subconf eq 'master';
    # subconf is also called 'foo' (you're allowed to have a
    # subconf that is only concerned with one repo)
    return 0 if $subconf eq $repo;
    # same thing in big-config-land; foo is just @foo now
    return 0 if ( "\@$subconf" eq $repo );
    my @matched = grep { $repo =~ /^$_$/ }
      grep { $groups{"\@$subconf"}{$_} eq 'master' }
      sort keys %{ $groups{"\@$subconf"} };
    return 0 if @matched > 0;

    trace( 2, "-> disallowed" );
    return 1;
}

sub store_1 {
    # warning: writes and *deletes* it from %repos and %configs
    my ($repo) = shift;
    trace( 3, $repo );
    return unless ( $repos{$repo} or $configs{$repo} ) and -d "$repo.git";

    my ( %one_repo, %one_config );

    my $dumped_data = '';
    if ( $repos{$repo} ) {
        $one_repo{$repo} = $repos{$repo};
        delete $repos{$repo};
        $dumped_data = Data::Dumper->Dump( [ \%one_repo ], [qw(*one_repo)] );
    }

    if ( $configs{$repo} ) {
        $one_config{$repo} = $configs{$repo};
        delete $configs{$repo};
        $dumped_data .= Data::Dumper->Dump( [ \%one_config ], [qw(*one_config)] );
    }

    _print( "$repo.git/gl-conf", $dumped_data );

    $split_conf{$repo} = 1;
}

sub store_common {
    trace(3);
    my $cc = "conf/gitolite.conf-compiled.pm";
    my $compiled_fh = _open( ">", "$cc.new" );

    my %patterns = ();

    my $data_version = glrc('current-data-version');
    trace( 3, "data_version = $data_version" );
    print $compiled_fh Data::Dumper->Dump( [$data_version], [qw(*data_version)] );

    my $dumped_data = Data::Dumper->Dump( [ \%repos ], [qw(*repos)] );
    $dumped_data .= Data::Dumper->Dump( [ \%configs ], [qw(*configs)] ) if %configs;

    print $compiled_fh $dumped_data;

    if (%groups) {
        my %groups = %{ inside_out( \%groups ) };
        $dumped_data = Data::Dumper->Dump( [ \%groups ], [qw(*groups)] );
        print $compiled_fh $dumped_data;

        # save patterns in %groups for faster handling of multiple repos, such
        # as happens in the various POST_COMPILE scripts
        for my $k ( keys %groups ) {
            $patterns{groups}{$k} = 1 unless $k =~ $REPONAME_PATT;
        }
    }

    print $compiled_fh Data::Dumper->Dump( [ \%patterns ], [qw(*patterns)] ) if %patterns;

    print $compiled_fh Data::Dumper->Dump( [ \%split_conf ], [qw(*split_conf)] ) if %split_conf;

    close $compiled_fh or _die "close compiled-conf failed: $!\n";
    rename "$cc.new", $cc;
}

{
    my $hook_reset = 0;

    sub hook_1 {
        my $repo = shift;
        trace( 3, $repo );

        # reset the gitolite supplied hooks, in case someone fiddled with
        # them, but only once per run
        if ( not $hook_reset ) {
            _mkdir("$rc{GL_ADMIN_BASE}/hooks/common");
            _mkdir("$rc{GL_ADMIN_BASE}/hooks/gitolite-admin");
            _print( "$rc{GL_ADMIN_BASE}/hooks/common/update",              update_hook() );
            _print( "$rc{GL_ADMIN_BASE}/hooks/gitolite-admin/post-update", post_update_hook() );
            chmod 0755, "$rc{GL_ADMIN_BASE}/hooks/common/update";
            chmod 0755, "$rc{GL_ADMIN_BASE}/hooks/gitolite-admin/post-update";
            $hook_reset++;
        }

        # propagate user-defined (custom) hooks to all repos
        ln_sf( "$rc{LOCAL_CODE}/hooks/common", "*", "$repo.git/hooks" ) if $rc{LOCAL_CODE};

        # override/propagate gitolite defined hooks for all repos
        ln_sf( "$rc{GL_ADMIN_BASE}/hooks/common", "*", "$repo.git/hooks" );
        # override/propagate gitolite defined hooks for the admin repo
        ln_sf( "$rc{GL_ADMIN_BASE}/hooks/gitolite-admin", "*", "$repo.git/hooks" ) if $repo eq 'gitolite-admin';
    }
}

sub inside_out {
    my $href = shift;
    # input conf: @aa = bb cc <newline> @bb = @aa dd

    my %ret = ();
    while ( my ( $k, $v ) = each( %{$href} ) ) {
        # $k is '@aa', $v is a href
        for my $k2 ( keys %{$v} ) {
            # $k2 is bb, then cc
            push @{ $ret{$k2} }, $k;
        }
    }
    return \%ret;
    # %groups = ( 'bb' => [ '@bb', '@aa' ], 'cc' => [ '@bb', '@aa' ], 'dd' => [ '@bb' ]);
}

{
    my $ri_fh = '';

    sub store_rule_info {
        $ri_fh = _open( ">", $rc{GL_ADMIN_BASE} . "/conf/rule_info" ) unless $ri_fh;
        # $nextseq, $fname, $lnum
        print $ri_fh join( "\t", @_ ) . "\n";
    }

    sub close_rule_info {
        close $ri_fh or die "close rule_info file failed: $!";
    }
}

1;

