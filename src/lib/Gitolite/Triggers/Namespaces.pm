package Gitolite::Triggers::Namespaces;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

# allow the server to use namespaces without the users needing to know
# ----------------------------------------------------------------------

# see http://sitaramc.github.com/gitolite/namespaces.html for instructions and
# important warnings

sub pre_git {
    my $repo = $_[1];

    my ($ns, $rr) = repo_namespace($repo);
    return if not $ns;

    $ENV{GIT_NAMESPACE} = $ns;
    $rc{REALREPO} = $rr;
    trace( 1, "GIT_NAMESPACE = $ns, REALREPO = $rr");
}

sub post_git {
    delete $ENV{GIT_NAMESPACE};
}


1;
