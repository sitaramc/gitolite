package Gitolite::Triggers::TProxy;

# ----------------------------------------------------------------------
# transparent proxy for git repos, hosted on a gitolite server

# ----------------------------------------------------------------------
# WHAT

#   1.  user runs a git command (clone, fetch, push) against a gitolite
#       server.
#   2.  if that server has the repo, it will serve it up.  Else it will
#       *transparently* forward the git operation to a designated upstream
#       server.  The user does not have to do anything, and in fact may not
#       even know this has happened.

# can be combined with, but does not *require*, gitolite mirroring.

# ----------------------------------------------------------------------
# SECURITY
#
#   1.  Most of the issues that apply to "redirected push" in mirroring.html
#       also apply here.  In particular, you had best make sure the two
#       servers use the same authentication data (i.e., "alice" here should be
#       "alice" there!)
#
#   2.  Also, do not add keys for servers you don't trust!

# ----------------------------------------------------------------------
# HOW

# on transparent proxy server (the one that is doing the redirect):
#   1.  add
#           INPUT => ['TProxy::input'],
#       just before the ENABLE list in the rc file
#   2.  add an RC variable to tell gitolite where to go; this is also just
#       before the ENABLE list:
#           TPROXY_FORWARDS_TO => 'git@upstream',

# on upstream server (the one redirected TO):
#   1.  add
#           INPUT => ['TProxy::input'],
#       just before the ENABLE list in the rc file
#   2.  add the pubkey of the proxy server (the one that will be redirecting
#       to us) to this server's gitolite-admin "keydir" as
#       "server-<something>.pub", and push the change.

# to use in combination with gitolite mirroring
#   1.  just follow the same instructions as above.  Server names and
#       corresponding pub keys would already be set ok so step 2 in the
#       upstream server setup (above) will not be needed.
#   2.  needless to say, **don't** declare the repos you want to be
#       transparently proxied in the gitolite.conf for the slave.

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
my $soc = $ENV{SSH_ORIGINAL_COMMAND};

# ----------------------------------------------------------------------

sub input {
    # are we the upstream, getting something from a tproxy server?
    my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
    if ( $ARGV[0] =~ /^server-/ and $soc =~ /^TPROXY_FOR=(\S+) SOC=(($git_commands) '\S+')$/ ) {
        @ARGV = ($1);
        # you better make sure you read the security warnings up there!

        $ENV{SSH_ORIGINAL_COMMAND} = $2;
        delete $ENV{GL_BYPASS_ACCESS_CHECKS};
        # just in case we somehow end up running before Mirroring::input!

        return;
    }

    # well we're not upstream; are we a tproxy?
    return unless $rc{TPROXY_FORWARDS_TO};

    # is it a normal git command?
    return unless $ENV{SSH_ORIGINAL_COMMAND} =~ m(^($git_commands) '/?(.*?)(?:\.git(\d)?)?'$);

    # ...get the repo name from $ENV{SSH_ORIGINAL_COMMAND}
    my ( $verb, $repo, $trace_level ) = ( $1, $2, $3 );
    $ENV{D} = $trace_level if $trace_level;
    _die "invalid repo name: '$repo'" if $repo !~ $REPONAME_PATT;

    # nothing to do if the repo exists locally
    return if -d "$ENV{GL_REPO_BASE}/$repo.git";

    my $user = shift @ARGV;
    # redirect to upstream
    exec( "ssh", $rc{TPROXY_FORWARDS_TO}, "TPROXY_FOR=$user", "SOC=$ENV{SSH_ORIGINAL_COMMAND}" );
}

1;
