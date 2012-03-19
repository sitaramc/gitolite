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

use Gitolite::Common;
use Gitolite::Rc;
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
# XXX you still have to "warn" if this has any entries

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
    @repolist = @_;

    # ...sanity checks
    for (@repolist) {
        _warn "explicit '.git' extension ignored for $_.git" if s/\.git$//;
        _die "bad reponame '$_'" if $_ !~ $REPOPATT_PATT;
    }
    # XXX -- how do we deal with this? s/\bCREAT[EO]R\b/\$creator/g for @{ $repos_p };
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
    # XXX what do we do? @refs = map { s(/USER/)(/\$gl_user/); $_ } @refs;

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
    my ( $perm, $ref, $user ) = @_;
    _die "bad ref '$ref'"   unless $ref  =~ $REPOPATT_PATT;
    _die "bad user '$user'" unless $user =~ $USERNAME_PATT;

    $nextseq++;
    for my $repo (@repolist) {
        if ( check_subconf_repo_disallowed( $subconf, $repo ) ) {
            my $repo = $repo;
            $repo =~ s/^\@$subconf\./locally modified \@/;
            $ignored{$subconf}{$repo} = 1;
            next;
        }

        push @{ $repos{$repo}{$user} }, [ $nextseq, $perm, $ref ];

        # XXX g2 diff: we're not doing a lint check for usernames versus pubkeys;
        # maybe we can add that later

        # XXX to do: C/R/W, then CREATE_IS_C, etc
        # XXX to do: also NAME_LIMITS
        # XXX and hacks like $creator -> "$creatror - wild"

        # XXX consider if you want to use rurp_seen; initially no
    }
}

sub add_config {
    my ( $n, $key, $value ) = @_;

    $nextseq++;
    for my $repo (@repolist) {
        # XXX should we check_subconf_repo_disallowed here?
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
            _die "undefined group $item" unless $groups{$item};
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
    my @repos = grep { $_ =~ $REPONAME_PATT and not /^@/ } sort keys %repos;
    # add in members of repo groups
    map { push @repos, keys %{ $groups{$_} } } grep { /^@/ } keys %repos;

    for my $repo ( @{ sort_u( \@repos ) } ) {
        next unless $repo =~ $REPONAME_PATT;    # skip repo patterns
        next if $repo =~ m(^\@|EXTCMD/);        # skip groups and fake repos

        # XXX how do we deal with GL_NO_CREATE_REPOS?
        new_repo($repo) if not -d "$repo.git";
    }
}

sub new_repo {
    my $repo = shift;
    trace( 3, $repo );

    # XXX ignoring UMASK for now

    _mkdir("$repo.git");
    _chdir("$repo.git");
    _system("git init --bare >&2");
    _chdir( $rc{GL_REPO_BASE} );
    hook_1($repo);

    # XXX ignoring creator for now
    # XXX ignoring gl-post-init for now
}

sub new_wild_repo {
    my ( $repo, $user ) = @_;
    _chdir( $rc{GL_REPO_BASE} );

    trigger( 'PRE_CREATE', $repo, $user );
    new_repo($repo);
    _print( "$repo.git/gl-creator", $user );
    _print( "$repo.git/gl-perms", "$rc{DEFAULT_ROLE_PERMS}\n" ) if $rc{DEFAULT_ROLE_PERMS};
    # XXX git config, daemon, web...
    # XXX pre-create, post-create
    trigger( 'POST_CREATE', $repo, $user );

    _chdir( $rc{GL_ADMIN_BASE} );
}

sub hook_repos {
    trace(3);
    # all repos, all hooks
    _chdir( $rc{GL_REPO_BASE} );

    # XXX g2 diff: we now don't care if it's a symlink -- it's upto the admin
    # on the server to make sure things are kosher
    for my $repo (`find . -name "*.git" -prune`) {
        chomp($repo);
        $repo =~ s/\.git$//;
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
        _warn "$ig.conf attempting to set access for " . join( ", ", sort keys %{ $ignored{$ig} } );
    }
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
    return unless $repos{$repo} and -d "$repo.git";

    my ( %one_repo, %one_config );

    open( my $compiled_fh, ">", "$repo.git/gl-conf" ) or return;

    $one_repo{$repo} = $repos{$repo};
    delete $repos{$repo};
    my $dumped_data = Data::Dumper->Dump( [ \%one_repo ], [qw(*one_repo)] );

    if ( $configs{$repo} ) {
        $one_config{$repo} = $configs{$repo};
        delete $configs{$repo};
        $dumped_data .= Data::Dumper->Dump( [ \%one_config ], [qw(*one_config)] );
    }

    # XXX deal with this better now
    # $dumped_data =~ s/'(?=[^']*\$(?:creator|gl_user))~?(.*?)'/"$1"/g;
    print $compiled_fh $dumped_data;
    close $compiled_fh;

    $split_conf{$repo} = 1;
}

sub store_common {
    trace(3);
    my $cc = "conf/gitolite.conf-compiled.pm";
    my $compiled_fh = _open( ">", "$cc.new" );

    my $data_version = glrc('current-data-version');
    trace( 1, "data_version = $data_version" );
    print $compiled_fh Data::Dumper->Dump( [$data_version], [qw(*data_version)] );

    my $dumped_data = Data::Dumper->Dump( [ \%repos ], [qw(*repos)] );
    $dumped_data .= Data::Dumper->Dump( [ \%configs ], [qw(*configs)] ) if %configs;

    # XXX and again...
    # XXX $dumped_data =~ s/'(?=[^']*\$(?:creator|gl_user))~?(.*?)'/"$1"/g;

    print $compiled_fh $dumped_data;

    if (%groups) {
        my %groups = %{ inside_out( \%groups ) };
        $dumped_data = Data::Dumper->Dump( [ \%groups ], [qw(*groups)] );
        # XXX $dumped_data =~ s/\bCREAT[EO]R\b/\$creator/g;
        # XXX $dumped_data =~ s/'(?=[^']*\$(?:creator|gl_user))~?(.*?)'/"$1"/g;
        print $compiled_fh $dumped_data;
    }
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

        # propagate user hooks
        ln_sf( "$rc{GL_ADMIN_BASE}/hooks/common", "*", "$repo.git/hooks" );

        # propagate admin hook
        ln_sf( "$rc{GL_ADMIN_BASE}/hooks/gitolite-admin", "*", "$repo.git/hooks" ) if $repo eq 'gitolite-admin';

        # g2 diff: no "site-wide" hooks (the stuff in between gitolite hooks
        # and user hooks) anymore.  I don't think anyone used them anyway...
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

1;

