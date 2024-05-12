package Gitolite::Triggers::Mirroring;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

my $hn           = $rc{HOSTNAME};

my ( $mode, $master, %copies, %trusted_copies );

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

        $ENV{GL_BYPASS_CREATOR_CHECK} = option($repo, "bypass-creator-check");
        # this expects valid perms content on STDIN
        _system("gitolite perms -c $repo");
        delete $ENV{GL_BYPASS_CREATOR_CHECK};

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
        # master -> copy push, no access checks needed
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

    # print mirror status if at least one copy status file is present
    print_status( $repo ) if not $rc{HUSH_MIRROR_STATUS} and $mode ne 'local' and glob("$rc{GL_REPO_BASE}/$repo.git/gl-copy-*.status");

    # we don't deal with any reads.  Note that for pre-git this check must
    # happen *after* getting details, to give mode() a chance to die on "known
    # unknown" repos (repos that are in the config, but mirror settings
    # exclude this host from both the master and copy lists)
    return if $aa eq 'R';

    trace( 1, "mirror", "pre_git", $repo, "user=$user", "sender=$sender", "mode=$mode", ( $rc{REDIRECTED_PUSH} ? ("redirected") : () ) );

    # ------------------------------------------------------------------
    # case 1: we're master or copy, normal user pushing to us
    if ( $user and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 1, user push" );
        return if $mode eq 'local' or $mode eq 'master';
        if ( $trusted_copies{$hn} ) {
            trace( 1, "redirect to $master" );
            exec( "ssh", $master, "USER=$user", "SOC=$ENV{SSH_ORIGINAL_COMMAND}" );
        } else {
            _die "$hn: pushing '$repo' to copy '$hn' not allowed";
        }
    }

    # ------------------------------------------------------------------
    # case 2: we're copy, master pushing to us
    if ( $sender and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, master push" );
        _die "$hn: '$repo' is local"                        if $mode eq 'local';
        _die "$hn: '$repo' is native"                       if $mode eq 'master';
        _die "$hn: '$sender' is not the master for '$repo'" if $master ne $sender;
        return;
    }

    # ------------------------------------------------------------------
    # case 3: we're master, copy sending a redirected push to us
    if ( $sender and $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, copy redirect" );
        _die "$hn: '$repo' is local"                           if $mode eq 'local';
        _die "$hn: '$repo' is not native"                      if $mode eq 'copy';
        _die "$hn: '$sender' is not a valid copy for '$repo'"  if not $copies{$sender};
        _die "$hn: redirection not allowed from '$sender'"     if not $trusted_copies{$sender};
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
    # case 1: we're master or copy, normal user pushing to us
    if ( $user and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 1, user push" );
        return if $mode eq 'local';
        # copy was eliminated earlier anyway, so that leaves 'master'

        # find all copies and push to each of them
        push_to_copies($repo);

        return;
    }

    # ------------------------------------------------------------------
    # case 2: we're copy, master pushing to us
    if ( $sender and not $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, master push" );
        # nothing to do
        return;
    }

    # ------------------------------------------------------------------
    # case 3: we're master, copy sending a redirected push to us
    if ( $sender and $rc{REDIRECTED_PUSH} ) {
        trace( 3, "case 2, copy redirect" );

        # find all copies and push to each of them
        push_to_copies($repo);

        return;
    }
}

{
    my $lastrepo = '';

    sub details {
        my $repo = shift;
        return if $lastrepo eq $repo;

        $master         = master($repo);
        %copies         = copies($repo);
        $mode           = mode($repo);
        %trusted_copies = trusted_copies($repo);
        trace( 3, $master, $mode, join( ",", sort keys %copies ), join( ",", sort keys %trusted_copies ) );
    }

    sub master {
        return option( +shift, 'mirror.master' );
    }

    sub copies {
        my $repo = shift;
        my %out;

        my $ref = git_config( $repo, "^gitolite-options\\.mirror\\.copies.*" );
        map { $out{$_} = 'async' } map { split } values %$ref;

        my @sync_types = qw(sync async nosync nosync-quiet);
        foreach my $sync_type ( @sync_types ) {
            $ref = git_config( $repo, "^gitolite-options\\.mirror\\.copies\\.${sync_type}.*" );
            map { $out{$_} = $sync_type } map { split } values %$ref;
        }

        return %out;
    }

    sub trusted_copies {
        my $ref = git_config( +shift, "^gitolite-options\\.mirror\\.redirectOK.*" );
        # the list of trusted copies (where we accept redirected pushes from)
        # is either explicitly given...
        my @out = map { split } values %$ref;
        my %out = map { $_ => 1 } @out;
        # ...or it's all the copies mentioned if the list is just a "all"
        %out = %copies if ( @out == 1 and $out[0] eq 'all' );
        return %out;
    }

    sub mode {
        my $repo = shift;
        return 'local'  if not $hn;
        return 'master' if $master eq $hn;
        return 'copy'   if $copies{$hn};
        return 'local'  if not $master and not %copies;
        _die "$hn: '$repo' is mirrored but not here";
    }
}

sub push_to_copies {
    my $repo = shift;

    my $u = $ENV{GL_USER};
    delete $ENV{GL_USER};    # why?  see src/commands/mirror

    my $lb = "$ENV{GL_REPO_BASE}/$repo.git/.gl-mirror-lock";
    for my $s ( sort keys %copies ) {
        trace( 1, "push_to_copies skipping self" ), next if $s eq $hn;
        my $mirror_command = "gitolite 1plus1 $lb.$s gitolite mirror push $s $repo </dev/null >/dev/null 2>&1";
        if ($copies{$s} eq 'async') {
            system($mirror_command . " &");
        } elsif ($copies{$s} eq 'sync') {
            system($mirror_command);
        } elsif ($copies{$s} eq 'nosync') {
            _warn "manual mirror push pending for '$s'";
        } elsif ($copies{$s} eq 'nosync-quiet') {
            1;
        } else {
            _warn "unknown mirror copy type $copies{$s} for '$s'";
        }
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
