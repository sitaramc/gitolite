package Gitolite::Triggers::Mirroring;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
my $hn           = $rc{HOSTNAME};

my ( $mode, $master, %slaves, %trusted_slaves );

# ----------------------------------------------------------------------

sub input {
    unless ( $ARGV[0] =~ /^server-(\S+)$/ ) {
        _die "'$ARGV[0]' is not a valid server name" if $ENV{SSH_ORIGINAL_COMMAND} =~ /^USER=(\S+) SOC=(git-receive-pack '(\S+)')$/;
        return;
    }

    # note: we treat %rc as our own internal "poor man's %ENV"
    $rc{FROM_SERVER} = $1;
    trace( 3, "from_server: $1" );
    my $sender = $rc{FROM_SERVER} || '';

    # custom peer-to-peer commands.  At present the only one is 'perms -c',
    # sent from a mirror command
    if ( $ENV{SSH_ORIGINAL_COMMAND} =~ /^CREATOR=(\S+) perms -c '(\S+)'$/ ) {
        $ENV{GL_USER} = $1;

        my $repo = $2;
        details($repo);
        _die "$hn: '$repo' is local"                        if $mode eq 'local';
        _die "$hn: '$repo' is native"                       if $mode eq 'master';
        _die "$hn: '$sender' is not the master for '$repo'" if $master ne $sender;

        # this expects valid perms content on STDIN
        _system("gitolite perms -c $repo");

        # we're done.  Yes, really...
        exit 0;
    }

    if ( $ENV{SSH_ORIGINAL_COMMAND} =~ /^USER=(\S+) SOC=(git-receive-pack '(\S+)')$/ ) {
        # my ($user, $newsoc, $repo) = ($1, $2, $3);
        $ENV{SSH_ORIGINAL_COMMAND} = $2;
        @ARGV                      = ($1);
        $rc{REDIRECTED_PUSH}       = 1;
        trace( 3, "redirected_push for user $1" );
    } else {
        # master -> slave push, no access checks needed
        $ENV{GL_BYPASS_ACCESS_CHECKS} = 1;
    }
}

# ----------------------------------------------------------------------

sub pre_git {
    return unless $hn;
    # nothing, and I mean NOTHING, happens if HOSTNAME is not set
    trace( 3, "pre_git() on $hn" );

    my ( $repo, $user, $aa ) = @_[ 1, 2, 3 ];

    my $sender = $rc{FROM_SERVER} || '';
    $user = '' if $sender and not exists $rc{REDIRECTED_PUSH};

    # ------------------------------------------------------------------
    # now you know the repo, get its mirroring details
    details($repo);

    # print mirror status if at least one slave status file is present
    print_status( $repo ) if $mode ne 'local' and glob("$rc{GL_REPO_BASE}/$repo.git/gl-slave-*.status");

    # we don't deal with any reads.  Note that for pre-git this check must
    # happen *after* getting details, to give mode() a chance to die on "known
    # unknown" repos (repos that are in the config, but mirror settings
    # exclude this host from both the master and slave lists)
    return if $aa eq 'R';

    trace( 1, "mirror", "pre_git", $repo, "user=$user", "sender=$sender", "mode=$mode", ( $rc{REDIRECTED_PUSH} ? ("redirected") : () ) );

    # ------------------------------------------------------------------
    # case 1: we're master or slave, normal user pushing to us
    if ( $user and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 1, user push" );
        return if $mode eq 'local' or $mode eq 'master';
        if ( $trusted_slaves{$hn} ) {
            trace( 1, "redirect to $master" );
            exec( "ssh", $master, "USER=$user", "SOC=$ENV{SSH_ORIGINAL_COMMAND}" );
        } else {
            _die "$hn: pushing '$repo' to slave '$hn' not allowed";
        }
    }

    # ------------------------------------------------------------------
    # case 2: we're slave, master pushing to us
    if ( $sender and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, master push" );
        _die "$hn: '$repo' is local"                        if $mode eq 'local';
        _die "$hn: '$repo' is native"                       if $mode eq 'master';
        _die "$hn: '$sender' is not the master for '$repo'" if $master ne $sender;
        return;
    }

    # ------------------------------------------------------------------
    # case 3: we're master, slave sending a redirected push to us
    if ( $sender and $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, slave redirect" );
        _die "$hn: '$repo' is local"                           if $mode eq 'local';
        _die "$hn: '$repo' is not native"                      if $mode eq 'slave';
        _die "$hn: '$sender' is not a valid slave for '$repo'" if not $slaves{$sender};
        _die "$hn: redirection not allowed from '$sender'"     if not $trusted_slaves{$sender};
        return;
    }

    _die "$hn: should not reach this line";

}

# ----------------------------------------------------------------------

sub post_git {
    return unless $hn;
    # nothing, and I mean NOTHING, happens if HOSTNAME is not set
    trace( 1, "post_git() on $hn" );

    my ( $repo, $user, $aa ) = @_[ 1, 2, 3 ];
    # we don't deal with any reads
    return if $aa eq 'R';

    my $sender = $rc{FROM_SERVER} || '';
    $user = '' if $sender;

    # ------------------------------------------------------------------
    # now you know the repo, get its mirroring details
    details($repo);

    trace( 1, "mirror", "post_git", $repo, "user=$user", "sender=$sender", "mode=$mode", ( $rc{REDIRECTED_PUSH} ? ("redirected") : () ) );

    # ------------------------------------------------------------------
    # case 1: we're master or slave, normal user pushing to us
    if ( $user and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 1, user push" );
        return if $mode eq 'local';
        # slave was eliminated earlier anyway, so that leaves 'master'

        # find all slaves and push to each of them
        push_to_slaves($repo);

        return;
    }

    # ------------------------------------------------------------------
    # case 2: we're slave, master pushing to us
    if ( $sender and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, master push" );
        # nothing to do
        return;
    }

    # ------------------------------------------------------------------
    # case 3: we're master, slave sending a redirected push to us
    if ( $sender and $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, slave redirect" );

        # find all slaves and push to each of them
        push_to_slaves($repo);

        return;
    }
}

{
    my $lastrepo = '';

    sub details {
        my $repo = shift;
        return if $lastrepo eq $repo;

        $master         = master($repo);
        %slaves         = slaves($repo);
        $mode           = mode($repo);
        %trusted_slaves = trusted_slaves($repo);
        trace( 3, $master, $mode, join( ",", sort keys %slaves ), join( ",", sort keys %trusted_slaves ) );
    }

    sub master {
        return option( +shift, 'mirror.master' );
    }

    sub slaves {
        my $repo = shift;

        my $ref = git_config( $repo, "^gitolite-options\\.mirror\\.slaves.*" );
        my %out = map { $_ => 'async' } map { split } values %$ref;

        $ref = git_config( $repo, "^gitolite-options\\.mirror\\.slaves\\.sync.*" );
        map { $out{$_} = 'sync' } map { split } values %$ref;

        $ref = git_config( $repo, "^gitolite-options\\.mirror\\.slaves\\.nosync.*" );
        map { $out{$_} = 'nosync' } map { split } values %$ref;

        return %out;
    }

    sub trusted_slaves {
        my $ref = git_config( +shift, "^gitolite-options\\.mirror\\.redirectOK.*" );
        # the list of trusted slaves (where we accept redirected pushes from)
        # is either explicitly given...
        my @out = map { split } values %$ref;
        my %out = map { $_ => 1 } @out;
        # ...or it's all the slaves mentioned if the list is just a "all"
        %out = %slaves if ( @out == 1 and $out[0] eq 'all' );
        return %out;
    }

    sub mode {
        my $repo = shift;
        return 'local'  if not $hn;
        return 'master' if $master eq $hn;
        return 'slave'  if $slaves{$hn};
        return 'local'  if not $master and not %slaves;
        _die "$hn: '$repo' is mirrored but not here";
    }
}

sub push_to_slaves {
    my $repo = shift;

    my $u = $ENV{GL_USER};
    delete $ENV{GL_USER};    # why?  see src/commands/mirror

    for my $s ( sort keys %slaves ) {
        system("gitolite mirror push $s $repo </dev/null >/dev/null 2>&1 &") if $slaves{$s} eq 'async';
        system("gitolite mirror push $s $repo </dev/null >/dev/null 2>&1")   if $slaves{$s} eq 'sync';
        _warn "manual mirror push pending for '$s'"                          if $slaves{$s} eq 'nosync';
    }

    $ENV{GL_USER} = $u;
}

sub print_status {
    my $repo = shift;
    my $u = $ENV{GL_USER};
    delete $ENV{GL_USER};
    system("gitolite mirror status all $repo >&2");
    $ENV{GL_USER} = $u;
}

1;
