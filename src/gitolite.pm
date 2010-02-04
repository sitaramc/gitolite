use strict;
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

# note that REPONAME_PATT allows "/", while USERNAME_PATT allows "@"
our $REPONAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._/+-]*$);    # very simple pattern
our $USERNAME_PATT=qr(^\@?[0-9a-zA-Z][0-9a-zA-Z._\@+-]*$);   # very simple pattern

our $REPO_UMASK;
our %repos;

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

sub log_it {
    open my $log_fh, ">>", $ENV{GL_LOG} or die "open log failed: $!\n";
    print $log_fh @_;
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
    for my $ar (@{$allowed_refs}) {
        my $refex = (keys %$ar)[0];
        # refex?  sure -- a regex to match a ref against :)
        next unless $ref =~ /^$refex/;
        die "$perm $ref $ENV{GL_USER} DENIED by $refex\n" if $ar->{$refex} eq '-';

        # as far as *this* ref is concerned we're ok
        return $refex if ($ar->{$refex} =~ /\Q$perm/);
    }
    die "$perm $ref $repo $ENV{GL_USER} DENIED by fallthru\n";
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
    my ($repo, $hooks_dir) = @_;

    umask($REPO_UMASK);

    system("mkdir", "-p", "$repo.git") and die "$ABRT mkdir $repo.git failed: $!\n";
        # erm, note that's "and die" not "or die" as is normal in perl
    wrap_chdir("$repo.git");
    system("git --bare init >&2");
    # propagate our own, plus any local admin-defined, hooks
    system("cp $hooks_dir/* hooks/");
    chmod 0755, "hooks/update";
}

# ----------------------------------------------------------------------------
#       parse the compiled acl
# ----------------------------------------------------------------------------

sub parse_acl
{
    my $GL_CONF_COMPILED = shift;
    die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;
}

# ----------------------------------------------------------------------------
#       print a report of $user's basic permissions
# ----------------------------------------------------------------------------

# basic means wildcards will be shown as wildcards; this is pretty much what
# got parsed by the compile script
sub report_basic
{
    my($GL_ADMINDIR, $GL_CONF_COMPILED, $user) = @_;

    &parse_acl($GL_CONF_COMPILED);

    # send back some useful info if no command was given
    print "hello $user, the gitolite version here is ";
    system("cat", "$GL_ADMINDIR/src/VERSION");
    print "\ryou have the following permissions:\n\r";
    for my $r (sort keys %repos) {
        my $perm .= ( $repos{$r}{R}{'@all'} ? '  @' : ( $repos{$r}{R}{$user} ? '  R' : '' ) );
        $perm    .= ( $repos{$r}{W}{'@all'} ? '  @' : ( $repos{$r}{W}{$user} ? '  W' : '' ) );
        print "$perm\t$r\n\r" if $perm;
    }
}

# ----------------------------------------------------------------------------
#       S P E C I A L   C O M M A N D S
# ----------------------------------------------------------------------------

sub special_cmd
{
    my ($GL_ADMINDIR, $GL_CONF_COMPILED, $shell_allowed, $RSYNC_BASE, $HTPASSWD_FILE) = @_;

    my $cmd = $ENV{SSH_ORIGINAL_COMMAND};
    my $user = $ENV{GL_USER};

    # check each special command we know about and call it if enabled
    if ($cmd eq 'info') {
        &report_basic($GL_ADMINDIR, $GL_CONF_COMPILED, $user);
        print "you also have shell access\n\r" if $shell_allowed;
    } elsif ($HTPASSWD_FILE and $cmd eq 'htpasswd') {
        &ext_cmd_htpasswd($HTPASSWD_FILE);
    } elsif ($RSYNC_BASE and $cmd =~ /^rsync /) {
        &ext_cmd_rsync($GL_CONF_COMPILED, $RSYNC_BASE, $cmd);
    } else {
        # if the user is allowed a shell, just run the command
        exec $ENV{SHELL}, "-c", $cmd if $shell_allowed;

        die "bad command: $cmd\n";
    }
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
    # we want specific perms to override @all, so they come first
    push @allowed_refs, @ { $repos{$repo}{$ENV{GL_USER}} || [] };
    push @allowed_refs, @ { $repos{$repo}{'@all'} || [] };

    for my $ar (@allowed_refs) {
        my $refex = (keys %$ar)[0];
        next unless $ref =~ /^$refex/;
        die "$perm $ref $ENV{GL_USER} DENIED by $refex\n" if $ar->{$refex} eq '-';
        return if ($ar->{$refex} =~ /\Q$perm/);
    }
    die "$perm $ref $ENV{GL_REPO} $ENV{GL_USER} DENIED by fallthru\n";
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
    die "I dont like absolute paths in $cmd\n" if $path =~ /^\//;
    die "I dont like '..' paths in $cmd\n" if $path =~ /\.\./;

    # ok now check if we're permitted to execute a $perm action on $path
    # (taken as a refex) using rsync.

    &check_access($GL_CONF_COMPILED, 'EXTCMD/rsync', $path, $perm);
        # that should "die" if there's a problem

    wrap_chdir($RSYNC_BASE);
    &log_it("$ENV{GL_TS}\t$ENV{SSH_ORIGINAL_COMMAND}\t$ENV{USER}\n");
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
    my $rc = system("htpasswd", "-b", $HTPASSWD_FILE, $ENV{GL_USER}, $password);
    die "htpasswd command seems to have failed with $rc return code...\n" if $rc;
}

1;
