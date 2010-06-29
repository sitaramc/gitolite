use strict;
use Data::Dumper;
$Data::Dumper::Deepcopy = 1;

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

our $ABRT = "\n\t\t***** ABORTING *****\n       ";
our $WARN = "\n\t\t***** WARNING *****\n       ";

# commands we're expecting
our $R_COMMANDS=qr/^(git[ -]upload-pack|git[ -]upload-archive)$/;
our $W_COMMANDS=qr/^git[ -]receive-pack$/;

# note that REPONAME_PATT allows "/", while USERNAME_PATT does not
# also, the reason REPONAME_PATT is a superset of USERNAME_PATT is (duh!)
# because in this version, a repo can have "CREATOR" in the name (see docs)
our $REPONAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@/+-]*$); # very simple pattern
our $USERNAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);  # very simple pattern
# same as REPONAME, but used for wildcard repos, allows some common regex metas
our $REPOPATT_PATT=qr(^\@?[0-9a-zA-Z[][\\^.$|()[\]*+?{}0-9a-zA-Z._\@/-]*$);

# these come from the RC file
our ($REPO_UMASK, $GL_WILDREPOS, $GL_PACKAGE_CONF, $GL_PACKAGE_HOOKS, $REPO_BASE, $GL_CONF_COMPILED, $GL_BIG_CONFIG);
our %repos;
our %groups;
our $data_version;
our $current_data_version = '1.5';

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

sub dbg {
    for my $i (@_) {
        print STDERR "DBG: $i\n";
    }
}

sub log_it {
    my ($ip, $logmsg);
    open my $log_fh, ">>", $ENV{GL_LOG} or die "open log failed: $!\n";
    # first space sep field is client ip, per "man ssh"
    ($ip = $ENV{SSH_CONNECTION}) =~ s/ .*//;
    # the first part of logmsg is the actual command used; it's either passed
    # in via arg1, or picked up from SSH_ORIGINAL_COMMAND
    $logmsg = $_[0] || $ENV{SSH_ORIGINAL_COMMAND}; shift;
    # the rest of it upto the caller; we just dump it into the logfile
    $logmsg .= "\t@_" if @_;
    print $log_fh "$ENV{GL_TS}\t$ENV{GL_USER}\t$ip\t$logmsg\n";
    close $log_fh or die "close log failed: $!\n";
}

# check one ref
sub check_ref {

    # normally, the $ref will be whatever ref the commit is trying to update
    # (like refs/heads/master or whatever).  At least one of the refexes that
    # pertain to this user must match this ref **and** the corresponding
    # permission must also match the action (W or +) being attempted.  If none
    # of them match, the access is denied.

    # Notice that the function DIES!!!  Any future changes that require more
    # work to be done *after* this, even on failure, can start using return
    # codes etc., but for now we're happy to just die.

    my ($allowed_refs, $repo, $ref, $perm) = @_;
    my @allowed_refs = sort { $a->[0] <=> $b->[0] } @{$allowed_refs};
    for my $ar (@allowed_refs) {
        my $refex = $ar->[1];
        # refex?  sure -- a regex to match a ref against :)
        next unless $ref =~ /^$refex/;
        die "$perm $ref $ENV{GL_USER} DENIED by $refex\n" if $ar->[2] eq '-';

        # as far as *this* ref is concerned we're ok
        return $refex if ($ar->[2] =~ /\Q$perm/);
    }
    die "$perm $ref $repo $ENV{GL_USER} DENIED by fallthru\n";
}

# ln -sf :-)
sub ln_sf
{
    my($srcdir, $glob, $dstdir) = @_;
    for my $hook ( glob("$srcdir/$glob") ) {
        $hook =~ s/$srcdir\///;
        unlink                   "$dstdir/$hook";
        symlink "$srcdir/$hook", "$dstdir/$hook" or die "could not symlink $hook\n";
    }
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
    my ($repo, $hooks_dir, $creator) = @_;

    umask($REPO_UMASK);
    die "wildrepos disabled, can't set creator $creator on new repo $repo\n"
        if $creator and not $GL_WILDREPOS;

    system("mkdir", "-p", "$repo.git") and die "$ABRT mkdir $repo.git failed: $!\n";
        # erm, note that's "and die" not "or die" as is normal in perl
    wrap_chdir("$repo.git");
    system("git --bare init >&2");
    if ($creator) {
        system("echo $creator > gl-creater");
        system("git", "config", "gitweb.owner", $creator);
    }
    # propagate our own, plus any local admin-defined, hooks
    ln_sf($hooks_dir, "*", "hooks");
    # in case of package install, GL_ADMINDIR is no longer the top cop;
    # override with the package hooks
    ln_sf("$GL_PACKAGE_HOOKS/common", "*", "hooks") if $GL_PACKAGE_HOOKS;
    chmod 0755, "hooks/update";
}

# ----------------------------------------------------------------------------
#       metaphysics (like, "is there a god?", "who created me?", etc)
# ----------------------------------------------------------------------------

# "who created this repo", "am I on the R list", and "am I on the RW list"?
sub wild_repo_rights
{
    my ($repo, $user) = @_;
    # creator
    my $c = '';
    if (                     -f "$ENV{GL_REPO_BASE_ABS}/$repo.git/gl-creater") {
        my $fh = wrap_open("<", "$ENV{GL_REPO_BASE_ABS}/$repo.git/gl-creater");
        chomp($c = <$fh>);
    }
    # $user's R and W rights
    my ($r, $w); $r = ''; $w = '';
    if ($user and            -f "$ENV{GL_REPO_BASE_ABS}/$repo.git/gl-perms") {
        my $fh = wrap_open("<", "$ENV{GL_REPO_BASE_ABS}/$repo.git/gl-perms");
        my $perms = join ("", <$fh>);
        if ($perms) {
            $r = $user if $perms =~ /^\s*R(?=\s).*\s(\@all|$user)(\s|$)/m;
            $w = $user if $perms =~ /^\s*RW(?=\s).*\s(\@all|$user)(\s|$)/m;
        }
    }

    return ($c, $r, $w);
}

# ----------------------------------------------------------------------------
#       getperms and setperms
# ----------------------------------------------------------------------------

sub get_set_perms
{
    my($repo, $verb, $user) = @_;
    my ($creator, $dummy, $dummy2) = &wild_repo_rights($repo, "");
    die "$repo doesnt exist or is not yours\n" unless $user eq $creator;
    wrap_chdir("$ENV{GL_REPO_BASE_ABS}");
    wrap_chdir("$repo.git");
    if ($verb eq 'getperms') {
        system("cat", "gl-perms") if -f "gl-perms";
    } else {
        system("cat > gl-perms");
        print "New perms are:\n";
        system("cat", "gl-perms");
    }
}

# ----------------------------------------------------------------------------
#       getdesc and setdesc
# ----------------------------------------------------------------------------

sub get_set_desc
{
    my($repo, $verb, $user) = @_;
    my ($creator, $dummy, $dummy2) = &wild_repo_rights($repo, "");
    die "$repo doesnt exist or is not yours\n" unless $user eq $creator;
    wrap_chdir("$ENV{GL_REPO_BASE_ABS}");
    wrap_chdir("$repo.git");
    if ($verb eq 'getdesc') {
        system("cat", "description") if -f "description";
    } else {
        system("cat > description");
        print "New description is:\n";
        system("cat", "description");
    }
}

# ----------------------------------------------------------------------------
#       set/unset repo configs
# ----------------------------------------------------------------------------

sub setup_repo_configs
{
    my ($repo_config_p, $repo, $wild) = @_;

    wrap_chdir("$ENV{GL_REPO_BASE_ABS}/$repo.git");

    # prep for wild and non-wild cases separately
    my $repo_patt = '';     # actually "repo or repo_pattern"
    if ($wild) {
        chomp (my $creator = `cat gl-creater`);

        # loop each key of %repo_config and make a copy
        for my $key (keys %$repo_config_p) {
            my $key2 = $key;
            # subst $creator in the copy with the creator name
            $key2 =~ s/\$creator/$creator/g;
            # match the new key against $repo
            if ($repo =~ /^$key2$/) {
                # if it matches, proceed
                $repo_patt = $key;
                last;
            }
        }
    } else {
        $repo_patt ||= $repo;   # just use the repo itself...
        # XXX TODO there is a remote possibility of errors if you have a
        # normal repo that fits a wild pattern; needs some digging into...
    }

    while ( my ($key, $value) = each(%{ $repo_config_p->{$repo_patt} }) ) {
        if ($value) {
            $value =~ s/^"(.*)"$/$1/;
            system("git", "config", $key, $value);
        } else {
            system("git", "config", "--unset-all", $key);
        }
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
    $c = $r = $w = "NOBODY" unless $GL_WILDREPOS;

    # set up the variables for a parse to interpolate stuff from the dumped
    # hash (remember the selective conversion of single to double quotes?).

    # if they're not passed in, then we look for an env var of that name, else
    # we default to "NOBODY" (we hope there isn't a real user called NOBODY!)
    # And in any case, we set those env vars so level 2 can redo the last
    # parse without any special code

    our $creator = $ENV{GL_CREATOR} = $c || $ENV{GL_CREATOR} || "NOBODY";
    our $readers = $ENV{GL_READERS} = $r || $ENV{GL_READERS} || "NOBODY";
    our $writers = $ENV{GL_WRITERS} = $w || $ENV{GL_WRITERS} || "NOBODY";
    our $gl_user = $ENV{GL_USER};

    die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;
    unless (defined($data_version) and $data_version eq $current_data_version) {
        # this cannot happen for 'easy-install' cases, by the way...
        print STDERR "(INTERNAL: $data_version -> $current_data_version; running gl-setup)\n";
        system("$ENV{SHELL} -l gl-setup >&2");

        die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;
    }

    # basic access reporting doesn't send $repo, and doesn't need to; you just
    # want the config dumped as is, really
    return unless $repo;

    my ($wild, @repo_plus, @user_plus);
    # expand $repo and $gl_user into all possible matching values
    ($wild, @repo_plus) = &get_memberships($repo,    1);
    (       @user_plus) = &get_memberships($gl_user, 0);
    # XXX testing notes: the above should return just one entry during
    # non-BC usage, whether wild or not
    die "assert 1 failed" if (@repo_plus > 1 and $repo_plus[-1] ne '@all'
                          or  @repo_plus > 2) and not $GL_BIG_CONFIG;

    # the old "convenience copy" thing.  Now on steroids :)

    # note that when copying the @all entry, we retain the destination name as
    # @all; we dont change it to $repo or $gl_user
    for my $r ('@all', @repo_plus) {
        my $dr = $repo; $dr = '@all' if $r eq '@all';
        $repos{$dr}{DELETE_IS_D} = 1 if $repos{$r}{DELETE_IS_D};
        $repos{$dr}{CREATE_IS_C} = 1 if $repos{$r}{CREATE_IS_C};
        $repos{$dr}{NAME_LIMITS} = 1 if $repos{$r}{NAME_LIMITS};

        for my $u ('@all', "$gl_user - wild", @user_plus) {
            my $du = $gl_user; $du = '@all' if $u eq '@all';
            $repos{$dr}{C}{$du} = 1 if $repos{$r}{C}{$u};
            $repos{$dr}{R}{$du} = 1 if $repos{$r}{R}{$u};
            $repos{$dr}{W}{$du} = 1 if $repos{$r}{W}{$u};

            next if $r eq $dr and $u eq $du;    # no point duplicating those refexes
            push @{ $repos{$dr}{$du} }, @{ $repos{$r}{$u} }
                if exists $repos{$r}{$u} and ref($repos{$r}{$u}) eq 'ARRAY';
        }
    }

    $ENV{GL_REPOPATT} = "";
    $ENV{GL_REPOPATT} = $wild if $wild and $GL_WILDREPOS;
    return ($wild);
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

sub report_version {
    my($GL_ADMINDIR, $user) = @_;
    print "hello $user, the gitolite version here is ";
    system("cat", ($GL_PACKAGE_CONF || "$GL_ADMINDIR/conf") . "/VERSION");
}

# basic means wildcards will be shown as wildcards; this is pretty much what
# got parsed by the compile script
sub report_basic
{
    my($GL_ADMINDIR, $GL_CONF_COMPILED, $repo, $user) = @_;

    # XXX The correct way is actually to give parse_acl another argument
    # (defaulting to $ENV{GL_USER}, the value being used now).  But for now
    # this will do, even though it's a bit of a kludge to get the basic access
    # rights for some other user this way
    local $ENV{GL_USER} = $user;

    &parse_acl($GL_CONF_COMPILED, "", "CREATOR", "READERS", "WRITERS");

    # send back some useful info if no command was given
    &report_version($GL_ADMINDIR, $user);
    print "\rthe gitolite config gives you the following access:\r\n";
    my $count = 0;
    for my $r (sort keys %repos) {
        next unless $r =~ /$repo/i;
        # if $GL_BIG_CONFIG is on, limit the number of output lines to 5
        next if $GL_BIG_CONFIG and $count++ >= 5;
        if ($r =~ $REPONAME_PATT and $r !~ /\bCREAT[EO]R\b/) {
            &parse_acl($GL_CONF_COMPILED, $r, "NOBODY",      "NOBODY", "NOBODY");
        } else {
            $r =~ s/\bCREAT[EO]R\b/$user/g;
            &parse_acl($GL_CONF_COMPILED, $r, $ENV{GL_USER}, "NOBODY", "NOBODY");
        }
        # @all repos; meaning of read/write flags:
        # @R => @all users are allowed access to this repo
        # #R => you're a super user and can see @all repos
        #  R => normal access
        my $perm .= ( $repos{$r}{C}{'@all'} ? ' @C' :                                      ( $repos{$r}{C}{$user} ? '  C' : '   ' ) );
        $perm    .= ( $repos{$r}{R}{'@all'} ? ' @R' : ( $repos{'@all'}{R}{$user} ? ' #R' : ( $repos{$r}{R}{$user} ? '  R' : '   ' )));
        $perm    .= ( $repos{$r}{W}{'@all'} ? ' @W' : ( $repos{'@all'}{W}{$user} ? ' #W' : ( $repos{$r}{W}{$user} ? '  W' : '   ' )));
        print "$perm\t$r\r\n" if $perm =~ /\S/;
    }
    print "only 5 out of $count candidate repos examined\r\nplease use a partial reponame or regex pattern to limit output\r\n" if $GL_BIG_CONFIG and $count > 5;
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

sub expand_wild
{
    my($GL_ADMINDIR, $GL_CONF_COMPILED, $repo, $user) = @_;

    &report_version($GL_ADMINDIR, $user);
    print "\ryou have access to the following repos on the server:\r\n";
    # this is for convenience; he can copy-paste the output of the basic
    # access report instead of having to manually change CREATOR to his name
    $repo =~ s/\bCREAT[EO]R\b/$user/g;

    # display matching repos (from *all* the repos in the system) that $user
    # has at least "R" access to

    chdir("$ENV{GL_REPO_BASE_ABS}") or die "chdir $ENV{GL_REPO_BASE_ABS} failed: $!\n";
    my $count = 0;
    for my $actual_repo (`find . -type d -name "*.git"|sort`) {
        chomp ($actual_repo);
        $actual_repo =~ s/^\.\///;
        $actual_repo =~ s/\.git$//;
        # actual_repo has to match the pattern being expanded
        next unless $actual_repo =~ /$repo/i;
        next if $GL_BIG_CONFIG and $count++ >= 5;

        my($perm, $creator, $wild) = &repo_rights($actual_repo);
        next unless $perm =~ /\S/;
        print "$perm\t$creator\t$actual_repo\n";
    }
    print "only 5 out of $count candidate repos examined\nplease use a partial reponame or regex pattern to limit output\n" if $GL_BIG_CONFIG and $count > 5;
}

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

        return if $last_repo eq $repo;      # a wee bit o' caching, though not yet needed

        # we get passed an actual repo name.  It may be a normal
        # (non-wildcard) repo, in which case it is assumed to exist.  If it's
        # a wildrepo, it may or may not exist.  If it doesn't exist, the "C"
        # perms are also filled in, else that column is left blank

        unless ($REPO_BASE) {
            # means we've been called from outside; see doc/admin-defined-commands.mkd
            &where_is_rc();
            die "parse $ENV{GL_RC} failed: "       . ($! or $@) unless do $ENV{GL_RC};
        }

        my $perm = '   ';
        my $creator;

        # get basic info about the repo and fill %repos
        my $wild = '';
        my $exists = -d "$ENV{GL_REPO_BASE_ABS}/$repo.git";
        if ($exists) {
            # these will be empty if it's not a wildcard repo anyway
            my ($read, $write);
            ($creator, $read, $write) = &wild_repo_rights($repo, $ENV{GL_USER});
            # get access list with these substitutions
            $wild = &parse_acl($GL_CONF_COMPILED, $repo, $creator || "NOBODY", $read || "NOBODY", $write || "NOBODY");
        } else {
            $wild = &parse_acl($GL_CONF_COMPILED, $repo, $ENV{GL_USER}, "NOBODY", "NOBODY");
        }

        if ($exists and not $wild) {
            $creator = '<gitolite>';
        } elsif ($exists) {
            # is a wildrepo, and it has already been created
            $creator = "($creator)";
        } else {
            # repo didn't exist; C perms need to be filled in
            $perm = ( $repos{$repo}{C}{'@all'} ? ' @C' : ( $repos{$repo}{C}{$ENV{GL_USER}} ? ' =C' : '   ' )) if $GL_WILDREPOS;
            # if you didn't have perms to create it, delete the "convenience"
            # copy of the ACL that parse_acl makes
            delete $repos{$repo} if $perm !~ /C/ and $wild;
            $creator = "<notfound>";
        }
        $perm .= ( $repos{$repo}{R}{'@all'} ? ' @R' : ( $repos{'@all'}{R}{$ENV{GL_USER}} ? ' #R' : ( $repos{$repo}{R}{$ENV{GL_USER}} ? '  R' : '   ' )));
        $perm .= ( $repos{$repo}{W}{'@all'} ? ' @W' : ( $repos{'@all'}{W}{$ENV{GL_USER}} ? ' #W' : ( $repos{$repo}{W}{$ENV{GL_USER}} ? '  W' : '   ' )));

        # set up for caching %repos
        $last_repo = $repo;

        return($perm, $creator, $wild);
    }
}

# helper/convenience routine to get rights and ownership from a shell command
sub cli_repo_rights {
    my ($perm, $creator, $wild) = &repo_rights($_[0]);
    $perm =~ s/ /_/g;
    $creator =~ s/^\(|\)$//g;
    print "$perm $creator\n";
}

# ----------------------------------------------------------------------------
#       setup the ~/.ssh/authorized_keys file
# ----------------------------------------------------------------------------

sub setup_authkeys
{
    # ARGUMENTS

    my($bindir, $GL_KEYDIR, $user_list_p) = @_;
    # calling from outside the normal compile script may mean that argument 2
    # may not be passed; so make sure it's a valid hashref, even if empty
    $user_list_p = {} unless $user_list_p;

    # CONSTANTS

    # command and options for authorized_keys
    my $AUTH_COMMAND="$bindir/gl-auth-command";
    my $AUTH_OPTIONS="no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty";

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
    for my $pubkey (`find . -type f`)
    {
        chomp($pubkey); $pubkey =~ s(^\./)();

        # security check (thanks to divVerent for catching this)
        unless ($pubkey =~ $REPONAME_PATT) {
            print STDERR "$pubkey contains some unsavoury characters; ignored...\n";
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
        }
        $pubkey_content =~ s/\s*$/\n/;
        # don't trust files with multiple lines (i.e., something after a newline)
        if ($pubkey_content =~ /\n./)
        {
            print STDERR "WARNING: a pubkey file can only have one line (key); ignoring $pubkey\n" .
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
        print STDERR "$WARN You have " . scalar(@not_in_config) . " pubkeys that do not appear to be used in the config\n";
    } elsif (@not_in_config) {
        print STDERR "$WARN the following users (pubkey files in parens) do not appear in the config file:\n", join(",", sort @not_in_config), "\n";
    }

    # lint check 3; a little more severe than the first two I guess...
    {
        my @no_pubkey =
            grep { $_ !~ /^(gitweb|daemon|\@.*|~\$creator|\$readers|\$writers)$/ }
                grep { $user_list_p->{$_} ne 'has pubkey' }
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
    my ($GL_ADMINDIR, $GL_CONF_COMPILED, $shell_allowed, $RSYNC_BASE, $HTPASSWD_FILE, $SVNSERVE) = @_;

    my $cmd = $ENV{SSH_ORIGINAL_COMMAND};
    my $user = $ENV{GL_USER};

    # check each special command we know about and call it if enabled
    if ($cmd eq 'info') {
        &report_basic($GL_ADMINDIR, $GL_CONF_COMPILED, '^', $user);
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
            my($perm, $creator, $wild) = &repo_rights('gitolite-admin');
            die "you can't ask for others' permissions\n" unless $perm =~ /W/;
        }
        push @otherusers, $user unless @otherusers;

        &parse_acl($GL_CONF_COMPILED);
        for my $otheruser (@otherusers) {
            warn("ignoring illegal username $otheruser\n"), next unless $otheruser =~ $USERNAME_PATT;
            &report_basic($GL_ADMINDIR, $GL_CONF_COMPILED, $repo, $otheruser);
        }
    } elsif ($HTPASSWD_FILE and $cmd eq 'htpasswd') {
        &ext_cmd_htpasswd($HTPASSWD_FILE);
    } elsif ($RSYNC_BASE and $cmd =~ /^rsync /) {
        &ext_cmd_rsync($GL_CONF_COMPILED, $RSYNC_BASE, $cmd);
    } elsif ($SVNSERVE and $cmd eq 'svnserve -t') {
        &ext_cmd_svnserve($SVNSERVE);
    } else {
        # if the user is allowed a shell, just run the command
        &log_it();
        exec $ENV{SHELL}, "-c", $cmd if $shell_allowed;

        die "bad command: $cmd\n";
    }
}

# ----------------------------------------------------------------------------
#       get memberships
# ----------------------------------------------------------------------------

# given a plain reponame or username, return:
# - the name itself, plus all the groups it belongs to if $GL_BIG_CONFIG is
#   set
# OR
# - (for repos) if the name itself doesn't exist in the config, a wildcard
#   matching it, plus all the groups that wildcard belongs to (again if
#   $GL_BIG_CONFIG is set)

# A name can normally appear (repo example) (user example)
# - directly (repo foo) (RW = bar)
# - (only for repos) as a direct wildcard (repo foo/.*)
# but if $GL_BIG_CONFIG is set, it can also appear:
# - indirectly (@g = foo; repo @g) (@ug = bar; RW = @ug))
# - (only for repos) as an indirect wildcard (@g = foo/.*; repo @g).
# things that may not be obvious from the above:
# - the wildcard stuff does not apply to username memberships
# - for repos, wildcard appearances are TOTALLY ignored if a non-wild
#   appearance (direct or indirect) exists

sub get_memberships {
    my $base = shift;   # reponame or username
    my $is_repo = shift;    # some true value means a repo name has been passed

    my $wild = '';
    my (@ret, @ret_w);      # maintain wild matches separately from non-wild

    # direct
    push @ret, $base if not $is_repo or exists $repos{$base};
    if ($is_repo and $GL_WILDREPOS and not @ret) {
        for my $i (sort keys %repos) {
            if ($base =~ /^$i$/) {
                die "$ABRT $base matches $wild AND $i\n" if $wild and $wild ne $i;
                $wild = $i;
                # direct wildcard
                push @ret_w, $i;
            }
        }
    }

    if ($GL_BIG_CONFIG) {
        for my $g (sort keys %groups) {
            for my $i (sort keys %{ $groups{$g} }) {
                if ($base eq $i) {
                    # indirect
                    push @ret, $g;
                } elsif ($is_repo and $GL_WILDREPOS and not @ret and $base =~ /^$i$/) {
                    die "$ABRT $base matches $wild AND $i\n" if $wild and $wild ne $i;
                    $wild = $i;
                    # indirect wildcard
                    push @ret_w, $g;
                }
            }
        }
    }

    # deal with returning user info first
    unless ($is_repo) {
        # add in group membership info sent in via second and subsequent
        # arguments to gl-auth-command; be sure to prefix the "@" sign to each
        # of them!
        push @ret, map { s/^/@/; $_; } split(' ', $ENV{GL_GROUP_LIST}) if $ENV{GL_GROUP_LIST};
        return (@ret);
    }

    # enforce the rule about ignoring all wildcard matches if a non-wild match
    # exists while returning.  (The @ret gating above does not adequately
    # ensure this, it is only an optimisation).
    #
    # Also note that there is an extra return value when called for repos
    # (compared to usernames)

    return ((@ret ? '' : $wild), (@ret ? @ret : @ret_w));
}

# ----------------------------------------------------------------------------
#       generic check access routine
# ----------------------------------------------------------------------------

sub check_access
{
    my ($GL_CONF_COMPILED, $repo, $path, $perm) = @_;
    my $ref = "NAME/$path";

    &parse_acl($GL_CONF_COMPILED);

    # until I do some major refactoring (which will bloat the update hook a
    # bit, sadly), this code duplicates stuff in the current update hook.

    my @allowed_refs;
    # user+repo specific perms override everything else, so they come first.
    # Then perms given to specific user for @all repos, and finally perms
    # given to @all users for specific repo
    push @allowed_refs, @ { $repos{$repo}{$ENV{GL_USER}} || [] };
    push @allowed_refs, @ { $repos{'@all'}{$ENV{GL_USER}} || [] };
    push @allowed_refs, @ { $repos{$repo}{'@all'} || [] };

    &check_ref(\@allowed_refs, $repo, $ref, $perm);
}

# ----------------------------------------------------------------------------
#       external command helper: rsync
# ----------------------------------------------------------------------------

sub ext_cmd_rsync
{
    my ($GL_CONF_COMPILED, $RSYNC_BASE, $cmd) = @_;

    # test the command patterns; reject if they don't fit.  Rsync sends
    # commands that looks like one of these to the server (the first one is
    # for a read, the second for a write)
    #   rsync --server --sender -some.flags . some/path
    #   rsync --server -some.flags . some/path

    die "bad rsync command: $cmd"
        unless $cmd =~ /^rsync --server( --sender)? -[\w.]+(?: --(?:delete|partial))* \. (\S+)$/;
    my $perm = "W";
    $perm = "R" if $1;
    my $path = $2;
    die "I dont like some of the characters in $path\n" unless $path =~ $REPOPATT_PATT;
        # XXX make a better pattern for this if people complain ;-)
    die "I dont like absolute paths in $cmd\n" if $path =~ /^\//;
    die "I dont like '..' paths in $cmd\n" if $path =~ /\.\./;

    # ok now check if we're permitted to execute a $perm action on $path
    # (taken as a refex) using rsync.

    &check_access($GL_CONF_COMPILED, 'EXTCMD/rsync', $path, $perm);
        # that should "die" if there's a problem

    wrap_chdir($RSYNC_BASE);
    &log_it();
    exec $ENV{SHELL}, "-c", $ENV{SSH_ORIGINAL_COMMAND};
}

# ----------------------------------------------------------------------------
#       external command helper: htpasswd
# ----------------------------------------------------------------------------

sub ext_cmd_htpasswd
{
    my $HTPASSWD_FILE = shift;

    die "$HTPASSWD_FILE doesn't exist or is not writable\n" unless -w $HTPASSWD_FILE;
    $|++;
    print <<EOFhtp;
Please type in your new htpasswd at the prompt.  You only have to type it once.

NOTE THAT THE PASSWORD WILL BE ECHOED, so please make sure no one is
shoulder-surfing, and make sure you clear your screen as well as scrollback
history after you're done (or close your terminal instance).

EOFhtp
    print "new htpasswd:";

    my $password = <>;
    $password =~ s/[\n\r]*$//;
    die "empty passwords are not allowed\n" unless $password;
    my $rc = system("htpasswd", "-b", $HTPASSWD_FILE, $ENV{GL_USER}, $password);
    die "htpasswd command seems to have failed with $rc return code...\n" if $rc;
}

# ----------------------------------------------------------------------------
#       external command helper: svnserve
# ----------------------------------------------------------------------------

sub ext_cmd_svnserve
{
    my $SVNSERVE = shift;

    $SVNSERVE =~ s/%u/$ENV{GL_USER}/g;
    exec $SVNSERVE;
    die "svnserve exec failed\n";
}

1;
