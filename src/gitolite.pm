# this file is commonly used using "require".  It is not required to use "use"
# (because it doesn't live in a different package)

# warning: preceding para requires 4th attribute of a programmer after
# laziness, impatience, and hubris: sense of humour :-)

# WARNING
# -------
# the name of this file will change as soon as its function/feature set
# stabilises enough ;-)

# right now all it does is
# - define a function that tells you where to find the rc file
# - define a function that creates a new repo and give it our update hook

# ----------------------------------------------------------------------------
#       common definitions
# ----------------------------------------------------------------------------

$ABRT = "\n\t\t***** ABORTING *****\n       ";
$WARN = "\n\t\t***** WARNING *****\n       ";

# commands we're expecting
$R_COMMANDS=qr/^(git[ -]upload-pack|git[ -]upload-archive)$/;
$W_COMMANDS=qr/^git[ -]receive-pack$/;

# note that REPONAME_PATT allows "/", while USERNAME_PATT does not
# also, the reason REPONAME_PATT is a superset of USERNAME_PATT is (duh!)
# because in this version, a repo can have "CREATER" in the name (see docs)
$REPONAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@/+-]*$); # very simple pattern
$USERNAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);  # very simple pattern
# same as REPONAME, plus some common regex metas
$REPOPATT_PATT=qr(^\@?[0-9a-zA-Z][\\^.$|()[\]*+?{}0-9a-zA-Z._\@/-]*$);

# ----------------------------------------------------------------------------
#       convenience subs
# ----------------------------------------------------------------------------

sub wrap_chdir {
    chdir($_[0]) or die "$ABRT chdir $_[0] failed: $! at ", (caller)[1], " line ", (caller)[2], "\n";
}

sub wrap_open {
    open (my $fh, $_[0], $_[1]) or die "$ABRT open $_[1] failed: $! at ", (caller)[1], " line ", (caller)[2], "\n" .
            ( $_[2] || '' );    # suffix custom error message if given
    return $fh;
}

# ----------------------------------------------------------------------------
#       where is the rc file hiding?
# ----------------------------------------------------------------------------

sub where_is_rc
{
    # till now, the rc file was in one fixed place: .gitolite.rc in $HOME of
    # the user hosting the gitolite repos.  This was fine, because gitolite is
    # all about empowering non-root users :-)

    # then we wanted to make a debian package out of it (thank you, Rhonda!)
    # which means (a) it's going to be installed by root anyway and (b) any
    # config files have to be in /etc/<something>

    # the only way to resolve this in a backward compat way is to look for the
    # $HOME one, and if you don't find it look for the /etc one

    # this common routine does that, setting an env var for the first one it
    # finds

    return if $ENV{GL_RC};

    for my $glrc ( $ENV{HOME} . "/.gitolite.rc", "/etc/gitolite/gitolite.rc" ) {
        if (-f $glrc) {
            $ENV{GL_RC} = $glrc;
            return;
        }
    }
}

# ----------------------------------------------------------------------------
#       create a new repository
# ----------------------------------------------------------------------------

# NOTE: this sub will change your cwd; caller beware!
sub new_repo
{
    my ($repo, $hooks_dir, $creater) = @_;

    umask($REPO_UMASK);

    system("mkdir", "-p", "$repo.git") and die "$ABRT mkdir $repo.git failed: $!\n";
        # erm, note that's "and die" not "or die" as is normal in perl
    wrap_chdir("$repo.git");
    system("git --bare init >&2");
    system("echo $creater > gl-creater") if $creater;
    # propagate our own, plus any local admin-defined, hooks
    system("cp $hooks_dir/* hooks/");
    chmod 0755, "hooks/update";
}

# ----------------------------------------------------------------------------
#       metaphysics (like, "is there a god?", "who created me?", etc)
# ----------------------------------------------------------------------------

# "who created this repo", "am I on the R list", and "am I on the RW list"?
sub repo_rights
{
    my ($repo_base_abs, $repo, $user) = @_;
    # creater
    my $c = '';
    if (                     -f "$repo_base_abs/$repo.git/gl-creater") {
        my $fh = wrap_open("<", "$repo_base_abs/$repo.git/gl-creater");
        chomp($c = <$fh>);
    }
    # $user's R and W rights
    my ($r, $w); $r = ''; $w = '';
    if ($user and            -f "$repo_base_abs/$repo.git/gl-perms") {
        my $fh = wrap_open("<", "$repo_base_abs/$repo.git/gl-perms");
        my $perms = join ("", <$fh>);
        if ($perms) {
            $r = $user if $perms =~ /^\s*R(?=\s).*\s$user(\s|$)/m;
            $w = $user if $perms =~ /^\s*RW(?=\s).*\s$user(\s|$)/m;
        }
    }

    return ($c, $r, $w);
}

# ----------------------------------------------------------------------------
#       getperms and setperms
# ----------------------------------------------------------------------------

sub get_set_perms
{
    my($repo_base_abs, $repo, $verb, $user) = @_;
    my ($creater, $dummy, $dummy2) = &repo_rights($repo_base_abs, $repo, "");
    die "$repo doesnt exist or is not yours\n" unless $user eq $creater;
    wrap_chdir("$repo_base_abs");
    wrap_chdir("$repo.git");
    if ($verb eq 'getperms') {
        print STDERR `cat gl-perms 2>/dev/null`;
    } else {
        system("cat > gl-perms");
        print STDERR "New perms are:\n";
        print STDERR `cat gl-perms`;
    }
}

# ----------------------------------------------------------------------------
#       parse the compiled acl
# ----------------------------------------------------------------------------

sub parse_acl
{
    # IMPLEMENTATION NOTE: a wee bit of this is duplicated in the update hook;
    # please update that also if the interface or the env vars change

    my ($GL_CONF_COMPILED, $repo, $c, $r, $w) = @_;

    # void $r if same as $w (otherwise "readers" overrides "writers"; this is
    # the same problem that needed a sort sub for the Dumper in the compile
    # script, but in this case it's limited to just $readers and $writers)
    $r = "NOBODY" if $r eq $w;

    # set up the variables for a parse to interpolate stuff from the dumped
    # hash (remember the selective conversion of single to double quotes?).

    # if they're not passed in, then we look for an env var of that name, else
    # we default to "NOBODY" (we hope there isn't a real user called NOBODY!)
    # And in any case, we set those env vars so level 2 can redo the last
    # parse without any special code

    our $creater = $ENV{GL_CREATER} = $c || $ENV{GL_CREATER} || "NOBODY";
    our $readers = $ENV{GL_READERS} = $r || $ENV{GL_READERS} || "NOBODY";
    our $writers = $ENV{GL_WRITERS} = $w || $ENV{GL_WRITERS} || "NOBODY";

    die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;

    # access reporting doesn't send $repo, and doesn't need to
    return unless $repo;

    return $ENV{GL_REPOPATT} = "" if $repos{$repo};

    # didn't find $repo in %repos, so it must be a wildcard-match case
    my @matched = grep { $repo =~ /^$_$/ } sort keys %repos;
    die "$repo has no matches\n" unless @matched;
    die "$repo has multiple matches\n@matched\n" if @matched > 1;
    # found exactly one pattern that matched, copy its ACL
    $repos{$repo} = $repos{$matched[0]};
    # and return the pattern
    return $ENV{GL_REPOPATT} = $matched[0];
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

# basic means wildcards will be shown as wildcards; this is pretty much what
# got parsed by the compile script
sub report_basic
{
    my($GL_ADMINDIR, $GL_CONF_COMPILED, $user) = @_;

    &parse_acl($GL_CONF_COMPILED, "", "CREATER", "READERS", "WRITERS");

    # send back some useful info if no command was given
    print "hello $user, the gitolite version here is ";
    system("cat", "$GL_ADMINDIR/src/VERSION");
    print "\ryou have the following permissions:\n\r";
    for my $r (sort keys %repos) {
        my $perm .= ( $repos{$r}{C}{'@all'} ? ' @' : ( $repos{$r}{C}{$user} ? ' C' : '  ' ) );
        $perm    .= ( $repos{$r}{R}{'@all'} ? ' @' : ( $repos{$r}{R}{$user} ? ' R' : '  ' ) );
        $perm    .= ( $repos{$r}{W}{'@all'} ? ' @' : ( $repos{$r}{W}{$user} ? ' W' : '  ' ) );
        print "$perm\t$r\n\r" if $perm =~ /\S/;
    }
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

sub expand_wild
{
    my($GL_CONF_COMPILED, $repo_base_abs, $repo, $user) = @_;

    # display matching repos (from *all* the repos in the system) that $user
    # has at least "R" access to

    chdir("$repo_base_abs") or die "chdir $repo_base_abs failed: $!\n";
    for my $actual_repo (`find . -type d -name "*.git"|sort`) {
        chomp ($actual_repo);
        $actual_repo =~ s/^\.\///;
        $actual_repo =~ s/\.git$//;
        # it has to match the pattern being expanded
        next unless $actual_repo =~ /^$repo$/;

        # find the creater and subsitute in repos
        my ($creater, $read, $write) = &repo_rights($repo_base_abs, $actual_repo, $user);
        # get access list with this
        &parse_acl($GL_CONF_COMPILED, "", $creater, $read || "NOBODY", $write || "NOBODY");

        # you need a minimum of "R" access to the regex we're talking about
        next unless $repos{$repo}{R}{'@all'} or $repos{$repo}{R}{$user};
        print STDERR "($creater)\t$actual_repo\n";
    }
}

1;
