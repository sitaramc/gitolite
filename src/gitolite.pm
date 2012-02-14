# lots of common routines

package gitolite;
use Exporter 'import';
@EXPORT = qw(
    can_read
    check_access
    check_ref
    check_repo_write_enabled
    cli_repo_rights
    cli_grouplist
    dbg
    dos2unix
    list_phy_repos
    ln_sf
    log_it
    new_repo
    new_wild_repo
    repo_rights
    run_custom_command
    setup_authkeys
    setup_daemon_access
    setup_git_configs
    setup_gitweb_access
    setup_web_access
    shell_out
    slurp
    special_cmd
    try_adc
    wrap_mkdir
    wrap_chdir
    wrap_open
    wrap_print

    mirror_mode
    mirror_listslaves
    mirror_redirectOK
);
@EXPORT_OK = qw(
    %repos
    %groups
    %git_configs
    %split_conf
);

use strict;
use warnings;

use Data::Dumper;
$Data::Dumper::Deepcopy = 1;
$|++;

# ----------------------------------------------------------------------------
#       find the rc file, then pull the libraries
# ----------------------------------------------------------------------------

BEGIN {
    die "ENV GL_RC not set\n" unless $ENV{GL_RC};
    die "ENV GL_BINDIR not set\n" unless $ENV{GL_BINDIR};
}

# ----------------------------------------------------------------------------
#       register signal handlers to log any problems
# ----------------------------------------------------------------------------
BEGIN {
    $SIG{__DIE__} = sub {
        my $msg = join(' ', "Die generated at line", (caller)[2], "in", (caller)[1], ":", @_, "\n");
        $msg =~ s/[\n\r]+/<<newline>>/g;
        log_it($msg) if $ENV{GL_LOG};
    };

    $SIG{__WARN__} = sub {
        my $msg = join(' ', "Warn generated at line", (caller)[2], "in", (caller)[1], ":", @_, "\n");
        $msg =~ s/[\n\r]+/<<newline>>/g;
        log_it($msg) if $ENV{GL_LOG};
        warn @_;
    };
}

use lib $ENV{GL_BINDIR};
use gitolite_rc;

# silently disable URI escaping if the module is not found
$GITWEB_URI_ESCAPE &&= eval "use CGI::Util qw(escape); 1";

# ----------------------------------------------------------------------------
#       the big data structures we care about
# ----------------------------------------------------------------------------

our %repos;
our %groups;
our %git_configs;
our %split_conf;
our $data_version;

# the following are read in from individual repo's gl-conf files, if present
our %one_repo;          # corresponds to what goes into %repos
our %one_git_config;    # ditto for %git_configs

# ----------------------------------------------------------------------------
#       convenience subs
# ----------------------------------------------------------------------------

sub wrap_mkdir
{
    # it's not an error if the directory exists, but it is an error if it
    # doesn't exist and we can't create it
    my $dir = shift;
    my $perm = shift;       # optional
    return if -d $dir;
    mkdir($dir) or die "mkdir $dir failed: $!\n";
    chmod $perm, $dir if $perm;
}

sub wrap_chdir {
    chdir($_[0]) or die "$ABRT chdir $_[0] failed: $! at ", (caller)[1], " line ", (caller)[2], "\n";
}

sub wrap_open {
    open (my $fh, $_[0], $_[1]) or die "$ABRT open $_[1] failed: $! at ", (caller)[1], " line ", (caller)[2], "\n" .
            ( $_[2] || '' );    # suffix custom error message if given
    return $fh;
}

sub wrap_print {
    my ($file, @text) = @_;
    my $fh = wrap_open(">", "$file.$$");
    print $fh @text;
    close($fh) or die "$ABRT close $file failed: $! at ", (caller)[1], " line ", (caller)[2], "\n";
    my $oldmode = ( (stat $file)[2] );
    rename "$file.$$", $file;
    chmod $oldmode, $file if $oldmode;
}

sub slurp {
    local $/ = undef;
    my $fh = wrap_open("<", $_[0]);
    return <$fh>;
}

sub add_del_line {
    my ($line, $file, $op, $escape) = @_;
        # $op is true for add operation, false for delete
        # $escape is true if the lines needs to be URI escaped
    my $contents;
    $line = escape($line) if $escape;

    local $/ = undef;
    my $fh = wrap_open("<", $file);
    $contents = <$fh>;
    $contents =~ s/\s+$/\n/;

    if ($op and $contents !~ /^\Q$line\E$/m) {
        # add line if it doesn't exist
        $contents .= "$line\n";
        wrap_print($file, $contents);
    }
    if (not $op and $contents =~ /^\Q$line\E$/m) {
        $contents =~ s/^\Q$line\E(\n|$)//m;
        wrap_print($file, $contents);
    }
}

sub dbg {
    use Data::Dumper;
    for my $i (@_) {
        print STDERR "DBG: " .  Dumper($i);
    }
}

sub dos2unix {
    # WARNING: when calling this, make sure you supply a list context
    s/\r\n/\n/g for @_;
    return @_;
}

sub log_it {
    my ($ip, $logmsg);
    open my $log_fh, ">>", $ENV{GL_LOG} or die
        "open log failed: $!\n" .
        "attempting to log: " . ( $_[0] || '(nothing)' ) . "\n";
    # first space sep field is client ip, per "man ssh"
    ($ip = $ENV{SSH_CONNECTION} || '(no-IP)') =~ s/ .*//;
    # the first part of logmsg is the actual command used; it's either passed
    # in via arg1, or picked up from SSH_ORIGINAL_COMMAND
    $logmsg = $_[0] || $ENV{SSH_ORIGINAL_COMMAND}; shift;
    # the rest of it upto the caller; we just dump it into the logfile
    $logmsg .= "\t@_" if @_;
    # erm... this is hard to explain so just see the commit message ok?
    $logmsg =~ s/([\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\xFF]+)/sprintf "<<hex(%*v02X)>>","",$1/ge;
    my $user = $ENV{GL_USER} || "(no user)";
    print $log_fh "$ENV{GL_TS}\t$user\t$ip\t$logmsg\n";
    close $log_fh or die "close log failed: $!\n";
}

# ln -sf :-)
sub ln_sf
{
    my($srcdir, $glob, $dstdir) = @_;
    for my $hook ( glob("$srcdir/$glob") ) {
        $hook =~ s/$srcdir\///;
        unlink                   "$dstdir/$hook";
        symlink "$srcdir/$hook", "$dstdir/$hook" or die "could not symlink $srcdir/$hook to $dstdir\n";
    }
}

# list physical repos
sub list_phy_repos
{
    my @phy_repos;

    wrap_chdir($REPO_BASE);
    for my $repo (`find . -type d -name "*.git" -prune`) {
        chomp ($repo);
        $repo =~ s(\./(.*)\.git$)($1);
        push @phy_repos, $repo;
    }

    return @phy_repos;
}

# ----------------------------------------------------------------------------
#       serious logic subs (as opposed to just "convenience" subs)
# ----------------------------------------------------------------------------

# check one ref
sub check_ref {

    # normally, the $ref will be whatever ref the commit is trying to update
    # (like refs/heads/master or whatever).  At least one of the refexes that
    # pertain to this user must match this ref **and** the corresponding
    # permission must also match the action (W/+, or C/D if used) being
    # attempted.  If none of them match, the access is denied.

    # NOTE: the function DIES when access is denied, unless arg 5 is true

    my ($allowed_refs, $repo, $ref, $perm, $dry_run) = @_;

    # sanity check the ref
    die "invalid characters in ref or filename: $ref\n" unless $ref =~ $GL_REF_OR_FILENAME_PATT;

    my @allowed_refs = sort { $a->[0] <=> $b->[0] } @{$allowed_refs};
    for my $ar (@allowed_refs) {
        my $refex = $ar->[1];
        # refex?  sure -- a regex to match a ref against :)
        next unless $ref =~ /^$refex/ or $ref eq 'joker';
            # joker matches any refex; it will only ever be sent internally
        return "$perm $ref $repo $ENV{GL_USER} DENIED by $refex" if $ar->[2] eq '-' and $dry_run;
        die    "$perm $ref $repo $ENV{GL_USER} DENIED by $refex\n" if $ar->[2] eq '-';

        # $ar->[2] can be RW\+?(C|D|CD|DC)?M?.  $perm can be W, +, C or
        # D, or any of these followed by "M".
        ( my $permq = $perm ) =~ s/\+/\\+/;
        $permq =~ s/M/.*M/;
        # as far as *this* ref is concerned we're ok
        return $refex if ($ar->[2] =~ /$permq/);
    }
    return "$perm $ref $repo $ENV{GL_USER} DENIED by fallthru" if $dry_run;
    die    "$perm $ref $repo $ENV{GL_USER} DENIED by fallthru\n";
}

# ----------------------------------------------------------------------------
#       create a new repository
# ----------------------------------------------------------------------------

# NOTE: this sub will change your cwd; caller beware!
sub new_repo
{
    my ($repo, $hooks_dir, $creator) = @_;

    umask($REPO_UMASK);
    die "wildrepos disabled, can't set creator $creator on new repo $repo\n"
        if $creator and not $GL_WILDREPOS;

    system("mkdir", "-p", "$repo.git") and die "$ABRT mkdir $repo.git failed: $!\n";
        # erm, note that's "and die" not "or die" as is normal in perl
    wrap_chdir("$repo.git");
    system("git --bare init >&2");
    if ($creator) {
        wrap_print("gl-creater", $creator);
        system("git", "config", "gitweb.owner", $creator);
    }
    # propagate our own, plus any local admin-defined, hooks
    ln_sf($hooks_dir, "*", "hooks");
    # in case of package install, GL_ADMINDIR is no longer the top cop;
    # override with the package hooks
    ln_sf("$GL_PACKAGE_HOOKS/common", "*", "hooks") if $GL_PACKAGE_HOOKS;
    chmod 0755, "hooks/update";

    # run gitolite's post-init hook if you can.  GL_REPO will be correct on a
    # wildcard create but on a normal (config file) create it will actually be
    # set to "gitolite-admin", so we need to make sure that for the duration
    # of the hook it is set correctly.
    system("env", "GL_REPO=$repo", "hooks/gl-post-init") if -x "hooks/gl-post-init";
}

sub new_wild_repo {
    my ($repo, $user) = @_;

    wrap_chdir($REPO_BASE);
    new_repo($repo, "$GL_ADMINDIR/hooks/common", $user);
        # note pwd is now the bare "repo.git"; new_repo does that...
    wrap_print("gl-perms", "$GL_WILDREPOS_DEFPERMS\n") if $GL_WILDREPOS_DEFPERMS;
    setup_git_configs($repo, \%git_configs);
    setup_daemon_access($repo);
    add_del_web_access($repo);
    wrap_chdir($ENV{HOME});
}

# ----------------------------------------------------------------------------
#       wild_repo_rights
# ----------------------------------------------------------------------------

{
    # the following subs need some persistent data, so we make a closure
    my $cache_filled = 0;
    my %cached_groups;
    sub fill_cache {
        # pull in basic group info
        unless ($cache_filled) {
            local(%repos, %groups);
            local $^W = 0;
            # read group info from compiled config.  At the time we're called
            # this info has not yet been pulled in by the rest of the code, so
            # we need to do this specially here.  However, the info we're
            # looking for is not subject to variable substitutions so we don't
            # really care; we just pull it in once and save it for the rest of
            # the run
            do $GL_CONF_COMPILED;
            %cached_groups = %groups;
            $cache_filled++;
        }
    }

    # "who created this repo", "am I on the R list", and "am I on the RW list"?
    sub wild_repo_rights
    {
        # set default categories
        $GL_WILDREPOS_PERM_CATS ||= "READERS WRITERS";
        my ($repo, $user) = @_;

        # creator
        my $c = '';
        if (                     -f "$REPO_BASE/$repo.git/gl-creater") {
            my $fh = wrap_open("<", "$REPO_BASE/$repo.git/gl-creater");
            chomp($c = <$fh>);
        }

        # now get the permission categories (used to be just R and RW.  Now
        # there can be any others that the admin defines in the RC file via
        # $GL_WILDREPOS_PERM_CATS variable (space separated list)

        # For instance, if the user is "foo", and gl-perms has "R bar", "RW
        # foo baz", and "TESTERS frob @all", this hash will then contain
        # "WRITERS=>foo" and "TESTERS=>@all"
        my %perm_cats;

        if ($user and            -f "$REPO_BASE/$repo.git/gl-perms") {
            my ($perms) = dos2unix(slurp("$REPO_BASE/$repo.git/gl-perms"));
            # discard comments
            $perms =~ s/#.*//g;
            # convert R and RW to the actual category names in the config file
            $perms =~ s/^\s*R /READERS /mg;
            $perms =~ s/^\s*RW /WRITERS /mg;
            # $perms is say "READERS alice @foo @bar\nRW bob @baz" (the entire gl-perms
            # file).  We replace each @foo with $user if $cached_groups{'@foo'}{$user}
            # exists (i.e., $user is a member of @foo)
            for my $g ($perms =~ /\s(\@\S+)/g) {
                fill_cache();   # get %cached_groups
                $perms =~ s/ $g(?!\S)/ $user/ if $cached_groups{$g}{$user};
            }
            # now setup the perm_cats hash to be returned
            if ($perms) {
                # let's say our user is "foo".  gl-perms has "CAT bar @all",
                # you add CAT => @all to the hash.  similarly, if gl-perms has
                # "DOG bar foo baz", you add DOG => foo to the hash.  And
                # since specific perms must override @all, we do @all first.
                $perm_cats{$1} = '@all' while ($perms =~ /^[ \t]*(\S+)(?=[ \t]).*[ \t]\@all([ \t]|$)/mg);
                $perm_cats{$1} = $user  while ($perms =~ /^[ \t]*(\S+)(?=[ \t]).*[ \t]$user([ \t]|$)/mg);
                # validate the categories being sent back
                for (sort keys %perm_cats) {
                    die "invalid permission category $_\n" unless $GL_WILDREPOS_PERM_CATS =~ /(^|\s)$_(\s|$)/;
                }
            }
        }

        return ($c, %perm_cats);
    }
}

# ----------------------------------------------------------------------------
#       getperms and setperms
# ----------------------------------------------------------------------------

sub get_set_perms
{
    my($repo, $verb, $user) = @_;
    # set default categories
    $GL_WILDREPOS_PERM_CATS ||= "READERS WRITERS";
    my ($creator, $dummy, $dummy2) = wild_repo_rights($repo, "");
    die "$repo doesnt exist or is not yours\n" unless $user eq $creator;
    wrap_chdir($REPO_BASE);
    wrap_chdir("$repo.git");
    if ($verb eq 'getperms') {
        return unless -f "gl-perms";
        my $perms = slurp("gl-perms");
        # convert R and RW to the actual category names in the config file
        $perms =~ s/^\s*R /READERS /mg;
        $perms =~ s/^\s*RW /WRITERS /mg;
        print $perms;
    } else {
        wrap_print("gl-perms", <>);     # eqvt to: system("cat > gl-perms");
        my $perms = slurp("gl-perms");
        # convert R and RW to the actual category names in the config file
        $perms =~ s/^\s*R /READERS /mg;
        $perms =~ s/^\s*RW /WRITERS /mg;
        for my $g ($perms =~ /^\s*(\S+)/gm) {
            die "invalid permission category $g\n" unless $g =~ /^#/ or $GL_WILDREPOS_PERM_CATS =~ /(^|\s)$g(\s|$)/;
        }
        print "New perms are:\n";
        print $perms;

        # gitweb and daemon
        setup_daemon_access($repo);
        # add or delete line (arg1) from file (arg2) depending on arg3
        add_del_web_access($repo);
    }
}

# ----------------------------------------------------------------------------
#       getdesc and setdesc
# ----------------------------------------------------------------------------

sub get_set_desc
{
    my($repo, $verb, $user) = @_;
    my ($creator, $dummy, $dummy2) = wild_repo_rights($repo, "");
    die "$repo doesnt exist or is not yours\n" unless $user eq $creator;
    wrap_chdir($REPO_BASE);
    wrap_chdir("$repo.git");
    if ($verb eq 'getdesc') {
        print slurp("description") if -f "description";
    } else {
        wrap_print("description", <>);
        print "New description is:\n";
        print slurp("description");
    }
}

# ----------------------------------------------------------------------------
#       IMPORTANT NOTE: next 3 subs (setup_*) assume $PWD is the bare repo itself
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
#       set/unset git configs
# ----------------------------------------------------------------------------

sub setup_git_configs
{
    return if $GL_NO_DAEMON_NO_GITWEB;

    my ($repo, $git_configs_p) = @_;

    # new_wild calls us without checking!
    return unless $git_configs_p->{$repo};

    # git_configs_p is a ref to a hash whose elements look like
    # {"reponame"}{sequence_number}{"key"} = "value";

    my %rch = %{ $git_configs_p->{$repo} };
    # %rch has elements that look like {sequence_number}{"key"} = "value"
    for my $seq (sort { $a <=> $b } keys %rch) {
        # and the final step is the repo config: {"key"} = "value"
        my $rc = $rch{$seq};
        while ( my ($key, $value) = each(%{ $rc }) ) {
            next if $key =~ /^gitolite-options\./;
            if ($value ne "") {
                $value =~ s/^['"](.*)["']$/$1/;
                system("git", "config", $key, $value);
            } else {
                system("git", "config", "--unset-all", $key);
            }
        }
    }
}

# ----------------------------------------------------------------------------
#       set/unset daemon access
# ----------------------------------------------------------------------------

# does not return anything; just touch/unlink the appropriate file
my $export_ok = "git-daemon-export-ok";
sub setup_daemon_access
{
    return if $GL_NO_DAEMON_NO_GITWEB;

    my $repo = shift;

    if (can_read($repo, 'daemon')) {
        wrap_print($export_ok, "");
    } else {
        unlink($export_ok);
    }
}

# ----------------------------------------------------------------------------
#       set/unset gitweb access
# ----------------------------------------------------------------------------

sub setup_web_access {
    # input is a hashref; keys are project names
    if ($WEB_INTERFACE eq 'gitweb') {

        my $projlist = shift;
        my $projlist_fh = wrap_open( ">", "$PROJECTS_LIST.$$");
        for my $proj (sort keys %{ $projlist }) {
            print $projlist_fh "" . ( $GITWEB_URI_ESCAPE ? escape($proj) : $proj ) . "\n";
        }
        close $projlist_fh;
        rename "$PROJECTS_LIST.$$", $PROJECTS_LIST;

    } else {
        warn "sorry, unknown web interface $WEB_INTERFACE\n";
    }
}

sub add_del_web_access {
    return if $GL_NO_DAEMON_NO_GITWEB;

    # input is a repo name.  Code could simply use `can_read($repo, 'gitweb')`
    # to determine whether to add or delete the repo from web access.
    # However, "desc" also factors into this so we have think about this.
    if ($WEB_INTERFACE eq 'gitweb') {

        my $repo = shift;
        add_del_line ("$repo.git", $PROJECTS_LIST, setup_gitweb_access($repo, '', '') || 0, $GITWEB_URI_ESCAPE || 0);

    } else {
        warn "sorry, unknown web interface $WEB_INTERFACE\n";
    }
}

# returns 1 if gitweb access has happened; this is to allow the caller to add
# an entry to the projects.list file
my $desc_file = "description";
sub setup_gitweb_access
# this also sets "owner" for gitweb, by the way
{
    my ($repo, $desc, $owner) = @_;
    my $is_wild = -f "gl-creater";
        # we may override but we do not remove gitweb.owner and description
        # for wild repos

    if ($desc) {
        open(DESC, ">", $desc_file);
        print DESC $desc . "\n";
        close DESC;
    } else {
        unlink $desc_file unless $is_wild;
    }

    if ($owner) {
        system("git", "config", "gitweb.owner", $owner);
    } else {
        system("git config --unset-all gitweb.owner 2>/dev/null") unless $is_wild;
    }

    # if there are no gitweb.* keys set, remove the section to keep the config file clean
    my $keys = `git config --get-regexp '^gitweb\\.' 2>/dev/null`;
    if (length($keys) == 0) {
        system("git config --remove-section gitweb 2>/dev/null");
    }

    return ($desc or can_read($repo, 'gitweb'));
        # this return value is used by the caller to write to projects.list
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

sub report_version {
    my($user) = @_;
    my $gl_version = slurp( ($GL_PACKAGE_CONF || "$GL_ADMINDIR/conf") . "/VERSION" );
    chomp($gl_version);
    my $git_version = `git --version`;
    $git_version =~ s/^git version //;
    print "hello $user, this is gitolite $gl_version running on git $git_version";
}

sub perm_code {
    # print the permission code
    my($all, $super, $user, $x) = @_;
    return "    " unless $all or $super or $user;
    return "  $x " unless $all or $super;   # only $user (explicit access) was given
    my $ret;
    $ret = " \@$x" if $all;                 # prefix @ if repo allows access for @all users
    $ret = " \#$x" if $super;               # prefix # if user has access to @all repos (sort of like a super user)
    $ret = " \&$x" if $all and $super;      # prefix & if both the above
    $ret .= ($user ? " " : "_" );           # suffix _ if no explicit access else <space>
    return $ret;
}

# basic means wildcards will be shown as wildcards; this is pretty much what
# got parsed by the compile script
sub report_basic
{
    my($repo, $user) = @_;

    # XXX The correct way is actually to give parse_acl another argument
    # (defaulting to $ENV{GL_USER}, the value being used now).  But for now
    # this will do, even though it's a bit of a kludge to get the basic access
    # rights for some other user this way
    local $ENV{GL_USER} = $user;

    parse_acl("", "CREATOR");
    # all we need is for 'keys %repos' to come up with all the names, so:
    @repos{ keys %split_conf } = values %split_conf if %split_conf;

    # send back some useful info if no command was given
    report_version($user);
    print "\rthe gitolite config gives you the following access:\r\n";
    my $count = 0;
    for my $r (sort keys %repos) {
        next unless $r =~ /$repo/i;
        # if $GL_BIG_CONFIG is on, limit the number of output lines
        next if $GL_BIG_CONFIG and $count++ >= $BIG_INFO_CAP;
        if ($r =~ $REPONAME_PATT and $r !~ /\bCREAT[EO]R\b/) {
            parse_acl($r, "NOBODY");
        } else {
            $r =~ s/\bCREAT[EO]R\b/$user/g;
            parse_acl($r, $ENV{GL_USER});
        }
        # @all repos; meaning of read/write flags:
        # @R => @all users are allowed access to this repo
        #   (Note: this now includes the rarely useful "@all users allowed
        #   access to @all repos" case)
        # #R => you're a super user and can see @all repos
        #  R => normal access
        my $perm .= ( $repos{$r}{C}{'@all'} ? ' @C' :                                      ( $repos{$r}{C}{$user} ? '  C' : '   ' ) );
        $perm .= perm_code( $repos{$r}{R}{'@all'} || $repos{'@all'}{R}{'@all'}, $repos{'@all'}{R}{$user}, $repos{$r}{R}{$user}, 'R');
        $perm .= perm_code( $repos{$r}{W}{'@all'} || $repos{'@all'}{W}{'@all'}, $repos{'@all'}{W}{$user}, $repos{$r}{W}{$user}, 'W');
        print "$perm\t$r\r\n" if $perm =~ /\S/ and not check_deny_repo($r);
    }
    print "only $BIG_INFO_CAP out of $count candidate repos examined\r\nplease use a partial reponame or regex pattern to limit output\r\n" if $GL_BIG_CONFIG and $count > $BIG_INFO_CAP;
    print "$GL_SITE_INFO\n" if $GL_SITE_INFO;
}

# ----------------------------------------------------------------------------
#       print a report of $user's expanded permissions
# ----------------------------------------------------------------------------

sub expand_wild
{
    my($repo, $user) = @_;

    report_version($user);
    print "\ryou have access to the following repos on the server:\r\n";
    # this is for convenience; he can copy-paste the output of the basic
    # access report instead of having to manually change CREATOR to his name
    $repo =~ s/\bCREAT[EO]R\b/$user/g;

    # display matching repos (from *all* the repos in the system) that $user
    # has at least "R" access to

    chdir($REPO_BASE) or die "chdir $REPO_BASE failed: $!\n";
    my $count = 0;
    for my $actual_repo (`find . -type d -name "*.git" -prune|sort`) {
        chomp ($actual_repo);
        $actual_repo =~ s/^\.\///;
        $actual_repo =~ s/\.git$//;
        # actual_repo has to match the pattern being expanded
        next unless $actual_repo =~ /$repo/i;
        next if $GL_BIG_CONFIG and $count++ >= $BIG_INFO_CAP;

        my($perm, $creator, $wild) = repo_rights($actual_repo);
        next unless $perm =~ /\S/;
        print "$perm\t$creator\t$actual_repo\n";
    }
    print "only $BIG_INFO_CAP out of $count candidate repos examined\nplease use a partial reponame or regex pattern to limit output\n" if $GL_BIG_CONFIG and $count > $BIG_INFO_CAP;
    print "$GL_SITE_INFO\n" if $GL_SITE_INFO;
}

# ----------------------------------------------------------------------------
#       parse the compiled acl
# ----------------------------------------------------------------------------

sub parse_acl
{
    # IMPLEMENTATION NOTE: a wee bit of this is duplicated in the update hook;
    # please update that also if the interface or the env vars change

    my ($repo, $c, %perm_cats) = @_;
    my $perm_cats_sig = '';     # a "signature" of the perm_cats hash
    map { $perm_cats_sig .= "$_.$perm_cats{$_}," } sort keys %perm_cats;
    $c = "NOBODY" unless $GL_WILDREPOS;

    # set up the variables for a parse to interpolate stuff from the dumped
    # hash (remember the selective conversion of single to double quotes?).

    # if they're not passed in, then we look for an env var of that name, else
    # we default to "NOBODY" (we hope there isn't a real user called NOBODY!)
    # And in any case, we set those env vars so level 2 can redo the last
    # parse without any special code

    our $creator = $ENV{GL_CREATOR} = $c || $ENV{GL_CREATOR} || "NOBODY";
    our $gl_user = $ENV{GL_USER};

    # these need to persist across calls to this function, so "our"
    our $saved_crwu;
    our (%saved_repos, %saved_groups);

    if ($saved_crwu and $saved_crwu eq "$creator,$perm_cats_sig,$gl_user") {
        %repos = %saved_repos; %groups = %saved_groups;
    } else {
        die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;
    }
    unless (defined($data_version) and $data_version eq $current_data_version) {
        warn "(INTERNAL: $data_version -> $current_data_version; running gl-setup)\n";
        system("$ENV{SHELL} -l -c gl-setup >&2");

        die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;
    }
    $saved_crwu = "$creator,$perm_cats_sig,$gl_user";
    %saved_repos = %repos; %saved_groups = %groups;
    add_repo_conf($repo) if $repo;

    # basic access reporting doesn't send $repo, and doesn't need to; you just
    # want the config dumped as is, really
    return unless $repo;

    my ($wild, @repo_plus, @user_plus);
    # expand $repo and $gl_user into all possible matching values
    ($wild, @repo_plus) = get_memberships($repo,    1);
    (       @user_plus) = get_memberships($gl_user, 0);

    # the old "convenience copy" thing.  Now on steroids :)

    # note that when copying the @all entry, we retain the destination name as
    # @all; we dont change it to $repo or $gl_user.  We need to maintain this
    # distinction to be able to print the @/#/& prefixes in the report output
    # (see doc/report-output.mkd)
    for my $r ('@all', @repo_plus) {
        my $dr = $repo; $dr = '@all' if $r eq '@all';
        $repos{$dr}{DELETE_IS_D} = 1 if $repos{$r}{DELETE_IS_D};
        $repos{$dr}{CREATE_IS_C} = 1 if $repos{$r}{CREATE_IS_C};
        $repos{$dr}{NAME_LIMITS} = 1 if $repos{$r}{NAME_LIMITS};
        $repos{$dr}{MERGE_CHECK} = 1 if $repos{$r}{MERGE_CHECK};
        # this needs to copy the key-value pairs from RHS to LHS, not just
        # assign RHS to LHS!  However, we want to roll in '@all' configs also
        # into the actual $repo; there's no need to preserve the distinction
        map { $git_configs{$repo}{$_} = $git_configs{$r}{$_} } keys %{$git_configs{$r}} if $git_configs{$r};

        for my $u ('@all', "$gl_user - wild", @user_plus, keys %perm_cats) {
            my $du = $gl_user; $du = '@all' if $u eq '@all' or ($perm_cats{$u} || '') eq '@all';
            $repos{$dr}{C}{$du} = 1 if $repos{$r}{C}{$u};
            $repos{$dr}{R}{$du} = 1 if $repos{$r}{R}{$u};
            $repos{$dr}{W}{$du} = 1 if $repos{$r}{W}{$u};

            next if $r eq $dr and $u eq $du;    # no point duplicating those refexes
            push @{ $repos{$dr}{$du} }, @{ $repos{$r}{$u} }
                if exists $repos{$r}{$u} and ref($repos{$r}{$u}) eq 'ARRAY';
        }
    }

    return ($wild);
}

# add repo conf from repo.git/gl-conf
sub add_repo_conf
{
    my ($repo) = shift;
    return unless $split_conf{$repo};
    do "$REPO_BASE/$repo.git/gl-conf" or return;
    $repos{$repo} = $one_repo{$repo};
    $git_configs{$repo} = $one_git_config{$repo};
}

# ----------------------------------------------------------------------------
#       repo_rights
# ----------------------------------------------------------------------------

# there will be multiple calls to repo_rights; better to use a closure.  We
# might even be called from outside (see the admin-defined-commands docs for
# how/why).  Regardless of how we're called, we assume $ENV{GL_USER} is
# already defined
{
    my $last_repo = '';
    sub repo_rights {
        my $repo = shift;
        $repo =~ s/^\.\///;
        $repo =~ s/\.git$//;

        # we get passed an actual repo name.  It may be a normal
        # (non-wildcard) repo, in which case it is assumed to exist.  If it's
        # a wildrepo, it may or may not exist.  If it doesn't exist, the "C"
        # perms are also filled in, else that column is left blank

        unless ($REPO_BASE) {
            # means we've been called from outside; see doc/admin-defined-commands.mkd
            where_is_rc();
            die "parse $ENV{GL_RC} failed: "       . ($! or $@) unless do $ENV{GL_RC};
            # fix up REPO_BASE
            $REPO_BASE = "$ENV{HOME}/$REPO_BASE" unless $REPO_BASE =~ m(^/);
        }

        my $perm = '   ';
        my $creator;

        # get basic info about the repo and fill %repos
        my $wild = '';
        my $exists = -d "$REPO_BASE/$repo.git";
        if ($exists) {
            # the list of permission categories within gl-perms that this user is a member
            # of, or that specify @all as a member.  See comments in
            # "wild_repo_rights" sub for nuances.
            my (%perm_cats);
            # these will be empty if it's not a wildcard repo anyway
            ($creator, %perm_cats) = wild_repo_rights($repo, $ENV{GL_USER});
            # get access list with these substitutions
            $wild = parse_acl($repo, $creator || "NOBODY", %perm_cats);
        } else {
            $wild = parse_acl($repo, $ENV{GL_USER});
        }

        if ($exists) {
            if ($creator and $wild) {
                $creator = "($creator)";
            } elsif ($creator and not $wild) {
                # was created wild but then someone (a) removed the pattern
                # from, and (b) added the actual reponame to, the config
                $creator = "<was_$creator>"
            } else {
                $creator = "<gitolite>";
            }
        } else {
            # repo didn't exist; C perms need to be filled in
            $perm = ( $repos{$repo}{C}{'@all'} ? ' @C' : ( $repos{$repo}{C}{$ENV{GL_USER}} ? ' =C' : '   ' )) if $GL_WILDREPOS;
            # if you didn't have perms to create it, delete the "convenience"
            # copy of the ACL that parse_acl makes
            delete $repos{$repo} if $perm !~ /C/ and $wild;
            $creator = "<notfound>";
        }
        $perm .= perm_code( $repos{$repo}{R}{'@all'} || $repos{'@all'}{R}{'@all'}, $repos{'@all'}{R}{$ENV{GL_USER}}, $repos{$repo}{R}{$ENV{GL_USER}}, 'R' );
        $perm .= perm_code( $repos{$repo}{W}{'@all'} || $repos{'@all'}{W}{'@all'}, $repos{'@all'}{W}{$ENV{GL_USER}}, $repos{$repo}{W}{$ENV{GL_USER}}, 'W' );
        $perm =~ s/./ /g if check_deny_repo($repo);

        # set up for caching %repos
        $last_repo = $repo;

        return($perm, $creator, $wild);
    }
}

# ----------------------------------------------------------------------------
#       helpers...
# ----------------------------------------------------------------------------

# helper/convenience routine to get rights and ownership from a shell command
sub cli_repo_rights {
    # check_access does a lot more, so just call it.  Since it returns perms
    # and creator separately, just space-join them and print it.
    print join(" ", check_access($_[0])), "\n";
}

# helper/convenience routine to get group membership info
sub cli_grouplist {
    die "GL_BIG_CONFIG needs to be set\n" unless $GL_BIG_CONFIG;
    # we may not have any data yet...
    parse_acl() unless (%repos);
    my @groups = grep { s/^@//; } get_memberships($ENV{GL_USER}, 0);
    print join(" ", @groups), "\n";
}

sub can_read {
    my $repo = shift;
    my $user = shift || $ENV{GL_USER};
    local $ENV{GL_USER} = $user;
    my ($perm, $creator, $wild) = repo_rights($repo);
    return ( ($GL_ALL_INCLUDES_SPECIAL || $user !~ /^(gitweb|daemon)$/)
        ? $perm =~ /R/
        : $perm =~ /R /
    );
}

# helper to manage "disabling" a repo or the whole site for "W" access
sub check_repo_write_enabled {
    my ($repo) = shift;
    for my $d ("$ENV{HOME}/.gitolite.down", "$REPO_BASE/$repo.git/.gitolite.down") {
        next unless -f $d;
        die $ABRT . slurp($d) if -s $d;
        die $ABRT . "writes are currently disabled\n";
    }
}

sub check_deny_repo {
    my $repo = shift;

    return 0 unless check_config_key($repo, "gitolite-options.deny-repo");
        # there are no 'gitolite-options.deny-repo' keys

    # the 'joker' ref matches any refex.  Think of it like a ".*" in reverse.
    # A pattern of ".*" matches any string.  Similarly a string called 'joker'
    # matches any pattern :-)  See check_ref() for implementation.
    return 1 if ( check_access($repo, 'joker', 'R', 1) ) =~ /DENIED by/;
    return 0;
}

sub check_config_key {
    my($repo, $key) = @_;
    my @ret = ();

    return () unless exists $git_configs{$repo};
    # otherwise it auto-vivifies if you call it from new_repo() and causes
    # harmless but annoying entries in the compiled config file.  They
    # disappear on the next compile of course, but still...

    # look through $git_configs{$repo} and return an array of the values of
    # all second level keys that match $key.  To understand "second level",
    # you need to remember that %git_configs has elements like this:
    #   $git_config{'reponame'}{sequence_number}{key} = value

    for my $s (sort { $a <=> $b } keys %{ $git_configs{$repo} }) {
        for my $k (keys %{ $git_configs{$repo}{$s} }) {
            push @ret,     $git_configs{$repo}{$s}{$k} if $k =~ /^$key$/;
        }
    }
    return @ret;
}

# ----------------------------------------------------------------------------
#       get memberships
# ----------------------------------------------------------------------------

# given a plain reponame or username, return:
# - the name itself if it's a user
# - the name itself if it's a repo and the repo exists in the config
# plus, if $GL_BIG_CONFIG is set:
# - all the groups the name belongs to
# plus, for repos:
# - all the wildcards matching it
# plus, if $GL_BIG_CONFIG is set:
# - all the groups those wildcards belong to

# A name can normally appear (repo example) (user example)
# - directly (repo foo) (RW = bob)
# - (only for repos) as a direct wildcard (repo foo/.*)
# but if $GL_BIG_CONFIG is set, it can also appear:
# - indirectly (@g = foo; repo @g) (@ug = bob; RW = @ug))
# - (only for repos) as an indirect wildcard (@g = foo/.*; repo @g).
# note: the wildcard stuff does not apply to username memberships

our %extgroups_cache;
sub get_memberships {
    my $base = shift;   # reponame or username
    my $is_repo = shift;    # some true value means a repo name has been passed

    my $wild = '';      # will be a space-sep list of matching patterns
    my @ret;            # list of matching groups/patterns

    # direct
    push @ret, $base if not $is_repo or exists $repos{$base};
    if ($is_repo and $GL_WILDREPOS) {
        for my $i (sort keys %repos) {
            next if $i eq $base;    # "direct" name already done; skip
            # direct wildcard
            if ($base =~ /^$i$/) {
                push @ret, $i;
                $wild = ($wild ? "$wild $i" : $i);
            }
        }
    }

    if ($GL_BIG_CONFIG) {
        for my $g (sort keys %groups) {
            for my $i (sort keys %{ $groups{$g} }) {
                if ($base eq $i) {
                    # indirect
                    push @ret, $g;
                } elsif ($is_repo and $GL_WILDREPOS and $base =~ /^$i$/) {
                    # indirect wildcard
                    push @ret, $g;
                    $wild = ($wild ? "$wild $i" : $i);
                }
            }
        }
    }

    # deal with returning user info first
    unless ($is_repo) {
        # bring in group membership info stored externally, by running
        # $GL_GET_MEMBERSHIPS_PGM if it is defined

        if ($extgroups_cache{$base}) {
            push @ret, @{ $extgroups_cache{$base} };
        } elsif ($GL_GET_MEMBERSHIPS_PGM) {
            my @extgroups = map { s/^/@/; $_; } split ' ', `$GL_GET_MEMBERSHIPS_PGM $base`;
            $extgroups_cache{$base} = \@extgroups;
            push @ret, @extgroups;
        }

        return (@ret);
    }

    # note that there is an extra return value when called for repos (as
    # opposed to being called for usernames)
    return ($wild, @ret);
}

# ----------------------------------------------------------------------------
#       generic check access routine
# ----------------------------------------------------------------------------

sub check_access
{
    my ($repo, $ref, $aa, $dry_run) = @_;
    # aa = attempted access

    my ($perm, $creator, $wild);
    unless ($ref) {
        ($perm, $creator, $wild) = repo_rights($repo);
        $perm =~ s/ /_/g;
        $creator =~ s/^\(|\)$//g;
        return ($perm, $creator);
    }

    ($perm, $creator, $wild) = repo_rights($repo) unless $ref eq 'joker';
        # calling it when ref eq joker is infinitely recursive!  check_access
        # will only be called with ref eq joker only when repo_rights has
        # already been called and %repos populated already.  (See comments
        # elsewhere for what 'joker' is and why it is called that).

    # until I do some major refactoring (which will bloat the update hook a
    # bit, sadly), this code duplicates stuff in the current update hook.

    my @allowed_refs;
    # user+repo specific perms override everything else, so they come first.
    # Then perms given to specific user for @all repos, and finally perms
    # given to @all users for specific repo
    push @allowed_refs, @ { $repos{$repo}{$ENV{GL_USER}} || [] };
    push @allowed_refs, @ { $repos{'@all'}{$ENV{GL_USER}} || [] };
    push @allowed_refs, @ { $repos{$repo}{'@all'} || [] };
    push @allowed_refs, @ { $repos{'@all'}{'@all'} || [] };

    if ($dry_run) {
        return check_ref(\@allowed_refs, $repo, $ref, $aa, $dry_run);
    } else {
        check_ref(\@allowed_refs, $repo, $ref, $aa);
    }
}

# ----------------------------------------------------------------------------
#       setup the ~/.ssh/authorized_keys file
# ----------------------------------------------------------------------------

sub setup_authkeys
{
    # ARGUMENTS

    my($GL_KEYDIR, $user_list_p) = @_;
    # calling from outside the normal compile script may mean that argument 2
    # may not be passed; so make sure it's a valid hashref, even if empty
    $user_list_p = {} unless $user_list_p;

    # LOCAL CONSTANTS

    # command and options for authorized_keys
    my $AUTH_COMMAND="$ENV{GL_BINDIR}/gl-auth-command";
    $AUTH_COMMAND="$ENV{GL_BINDIR}/gl-time $ENV{GL_BINDIR}/gl-auth-command" if $GL_PERFLOGT;
    # set default authentication options
    $AUTH_OPTIONS ||= "no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty";

    # START

    my $authkeys_fh = wrap_open( "<", $ENV{HOME} . "/.ssh/authorized_keys",
        "\tFor security reasons, gitolite will not *create* this file if it does\n" .
        "\tnot already exist.  Please see the \"admin\" document for details\n");
    my $newkeys_fh = wrap_open( ">", $ENV{HOME} . "/.ssh/new_authkeys" );
    # save existing authkeys minus the GL-added stuff
    while (<$authkeys_fh>)
    {
        print $newkeys_fh $_ unless (/^# gito(sis-)?lite start/../^# gito(sis-)?lite end/);
    }

    # add our "start" line, each key on its own line (prefixed by command and
    # options, in the standard ssh authorized_keys format), then the "end" line.
    print $newkeys_fh "# gitolite start\n";
    wrap_chdir($GL_KEYDIR);
    my @not_in_config;  # pubkeys exist but users don't appear in the config file
    for my $pubkey (`find . -type f | sort`)
    {
        chomp($pubkey); $pubkey =~ s(^\./)();

        # security check (thanks to divVerent for catching this)
        unless ($pubkey =~ $REPONAME_PATT) {
            warn "$pubkey contains some unsavoury characters; ignored...\n";
            next;
        }

        # lint check 1
        unless ($pubkey =~ /\.pub$/)
        {
            print STDERR "WARNING: pubkey files should end with \".pub\", ignoring $pubkey\n";
            next;
        }

        my $user = $pubkey;
        $user =~ s(.*/)();                  # foo/bar/baz.pub -> baz.pub
        $user =~ s/(\@[^.]+)?\.pub$//;      # baz.pub, baz@home.pub -> baz

        # lint check 2 -- don't print right now; just collect the messages
        push @not_in_config, "$user($pubkey)" if %$user_list_p and not $user_list_p->{$user};
        $user_list_p->{$user} = 'has pubkey'  if %$user_list_p;
        # apparently some pubkeys don't end in a newline...
        my $pubkey_content;
        {
            local $/ = undef;
            local @ARGV = ($pubkey);
            $pubkey_content = <>;
            $pubkey_content =~ s/^\s*#.*\n//gm;
        }
        $pubkey_content =~ s/\s*$/\n/;
        # don't trust files with multiple lines (i.e., something after a newline)
        if ($pubkey_content =~ /\n./)
        {
            warn "WARNING: a pubkey file can only have one line (key); ignoring $pubkey\n" .
                 "         Perhaps you're using a key in a different format (like putty/plink)?\n" .
                 "         If so, please convert it to openssh format using 'ssh-keygen -i'.\n" .
                 "         If you want to add multiple public keys for a single user, use\n" .
                 "         \"user\@host.pub\" file names.  See the \"one user, many keys\"\n" .
                 "         section in doc/3-faq-tips-etc.mkd for details.\n";
            next;
        }
        print $newkeys_fh "command=\"$AUTH_COMMAND $user\",$AUTH_OPTIONS ";
        print $newkeys_fh $pubkey_content;
    }

    # lint check 2 -- print less noisily
    if (@not_in_config > 10) {
        print STDERR "$WARN You have " . scalar(@not_in_config) . " pubkeys that do not appear to be used in any access rules\n";
    } elsif (@not_in_config) {
        print STDERR "$WARN the following users (pubkey files in parens) do not appear in any access rules:\n", join(",", sort @not_in_config), "\n";
    }

    # lint check 3; a little more severe than the first two I guess...
    {
        my @no_pubkey =
            grep { $_ !~ /^(gitweb|daemon|\@.*|~\$creator)$/ }
                grep { $user_list_p->{$_} ne 'has pubkey' }
                    grep { $GL_WILDREPOS_PERM_CATS !~ /(^|\s)$_(\s|$)/ }
                        keys %{$user_list_p};
        if (@no_pubkey > 10) {
            print STDERR "$WARN You have " . scalar(@no_pubkey) . " users WITHOUT pubkeys...!\n";
        } elsif (@no_pubkey) {
            print STDERR "$WARN the following users have no pubkeys:\n", join(",", sort @no_pubkey), "\n";
        }
    }

    print $newkeys_fh "# gitolite end\n";
    close $newkeys_fh or die "$ABRT close newkeys failed: $!\n";

    # all done; overwrite the file (use cat to avoid perm changes)
    system("cat $ENV{HOME}/.ssh/authorized_keys > $ENV{HOME}/.ssh/old_authkeys");
    system("cat $ENV{HOME}/.ssh/new_authkeys > $ENV{HOME}/.ssh/authorized_keys")
        and die "couldn't write authkeys file\n";
    system("rm  $ENV{HOME}/.ssh/new_authkeys");
}

# ----------------------------------------------------------------------------
#       S P E C I A L   C O M M A N D S
# ----------------------------------------------------------------------------

sub special_cmd
{
    my ($shell_allowed) = @_;

    my $cmd = $ENV{SSH_ORIGINAL_COMMAND};
    my $user = $ENV{GL_USER};

    # check each special command we know about and call it if enabled
    if ($cmd eq 'info') {
        report_basic('^', $user);
        print "you also have shell access\r\n" if $shell_allowed;
    } elsif ($cmd =~ /^info\s+(.+)$/) {
        my @otherusers = split ' ', $1;
        # the first argument is assumed to be a repo pattern, like in the
        # expand command
        my $repo = shift(@otherusers);
        die "$repo has invalid characters" unless "x$repo" =~ $REPOPATT_PATT;
        print STDERR "(treating $repo as pattern to limit output)\n";

        # set up the list of users being queried; it's either a list passed in
        # (allowed only for admin pushers) or just $user
        if (@otherusers) {
            my($perm, $creator, $wild) = repo_rights('gitolite-admin');
            die "you can't ask for others' permissions\n" unless $perm =~ /W/;
        }
        push @otherusers, $user unless @otherusers;

        parse_acl();
        for my $otheruser (@otherusers) {
            warn("ignoring illegal username $otheruser\n"), next unless $otheruser =~ $USERNAME_PATT;
            report_basic($repo, $otheruser);
        }
    } else {
        # if the user is allowed a shell, just run the command
        log_it();
        exec $ENV{SHELL}, "-c", $cmd if $shell_allowed;

        die "bad command: $cmd\n";
    }
}

sub run_custom_command {
    my $user = shift;

    my $cmd = $ENV{SSH_ORIGINAL_COMMAND};
    my ($verb, $repo) = ($cmd =~ /^\s*(\S+)(?:\s+'?\/?(.*?)(?:\.git)?'?)?$/);
    # deal with "no argument" cases
    $verb eq 'expand' ? $repo = '^' : die "$verb needs an argument\n" unless $repo;
    if ($repo =~ $REPONAME_PATT and $verb =~ /getperms|setperms/) {
        # with an actual reponame, you can "getperms" or "setperms"
        get_set_perms($repo, $verb, $user);
    }
    elsif ($repo =~ $REPONAME_PATT and $verb =~ /(get|set)desc/) {
        # with an actual reponame, you can "getdesc" or "setdesc"
        get_set_desc($repo, $verb, $user);
    }
    elsif ($verb eq 'expand') {
        # with a wildcard, you can "expand" it to see what repos actually match
        die "$repo has invalid characters" unless "x$repo" =~ $REPOPATT_PATT;
        expand_wild($repo, $user);
    } else {
        die "$cmd doesn't make sense to me\n";
    }
}

sub shell_out {
    my $shell = $ENV{SHELL};
    $shell =~ s/.*\//-/;    # change "/bin/bash" to "-bash"
    log_it($shell);
    exec { $ENV{SHELL} } $shell;
}

sub try_adc {
    my ($cmd, @args) = split ' ', $ENV{SSH_ORIGINAL_COMMAND};
    die "I don't like $cmd\n" if $cmd =~ /\.\./;

    # try the default (strict arguments) version first
    if (-x "$GL_ADC_PATH/$cmd") {
        # yes this is rather strict, sorry.
        do { die "I don't like $_\n" unless $_ =~ $ADC_CMD_ARGS_PATT and $_ !~ m(\.\./) } for ($cmd, @args);
        log_it("$GL_ADC_PATH/$ENV{SSH_ORIGINAL_COMMAND}");
        exec("$GL_ADC_PATH/$cmd", @args);
    }

    # now the "ua" (unrestricted/unchecked arguments) version
    if (-x "$GL_ADC_PATH/ua/$cmd") {
        log_it("$GL_ADC_PATH/ua/$ENV{SSH_ORIGINAL_COMMAND}");
        exec("$GL_ADC_PATH/ua/$cmd", @args);
    }
}

# ----------------------------------------------------------------------------
#       MIRRORING HELPERS
# ----------------------------------------------------------------------------

sub mirror_mode {
    my $repo = shift;

    # 'local' is the default if the config is empty or not set
    my $gmm = `git config --file $REPO_BASE/$repo.git/config --get gitolite.mirror.master` || 'local';
    chomp $gmm;
    return 'local' if $gmm eq 'local';
    return 'master' if $gmm eq ( $GL_HOSTNAME || '' );
    return "slave of $gmm";
}

sub mirror_listslaves {
    my $repo = shift;

    return ( `git config --file $REPO_BASE/$repo.git/config --get gitolite.mirror.slaves` || '' );
}

# is a redirect ok for this repo from this slave?
sub mirror_redirectOK {
    my $repo = shift;
    my $slave = shift || return 0;
        # if we don't know who's asking, the answer is "no"

    my $gmrOK = `git config --file $REPO_BASE/$repo.git/config --get gitolite.mirror.redirectOK` || '';
    chomp $gmrOK;
    my $slavelist = mirror_listslaves($repo);

    # if gmrOK is 'true', any valid slave can redirect
    return 1 if $gmrOK eq 'true' and $slavelist =~ /(^|\s)$slave(\s|$)/;
    # otherwise, gmrOK is a list of slaves who can redirect
    return 1 if $gmrOK =~ /(^|\s)$slave(\s|$)/;

    return 0;

    # LATER/NEVER: include a call to an external program to override a 'true',
    # based on, say, the time of day or network load etc.  Cons: shelling out,
    # deciding the name of the program (yet another rc var?)
}

# ------------------------------------------------------------------------------
# per perl rules, this should be the last line in such a file:
1;
