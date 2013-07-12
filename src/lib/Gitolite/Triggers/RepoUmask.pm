package Gitolite::Triggers::RepoUmask;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

# setting a repo specific umask
# ----------------------------------------------------------------------
# this is for people who are too paranoid to trust e.g., gitweb's repo
# exclusion logic, but not paranoid enough to put it on a different server

=for usage

  * In the rc file, add the line
        'RepoUmask',
    somewhere in the ENABLE list

  * For each repo that is to get a different umask than the default, add a
    line like this:

        option umask = 0027

=cut

# sadly option/config values are not available at pre_create time for normal
# repos.  So we have to do a one-time fixup in a post_create trigger.
sub post_create {
    my $repo = $_[1];

    my $umask = option($repo, 'umask');
    _chdir($rc{GL_REPO_BASE});  # because using option() moves us to ADMIN_BASE!

    return unless $umask;

    # unlike the one in the rc file, this is a string
    $umask = oct($umask);
    my $mode = "0" . sprintf("%o", $umask ^ 0777);

    system("chmod -R $mode $repo.git >&2");
    system("find $repo.git -type f -exec chmod a-x '{}' \\;");
}

sub pre_git {
    my $repo = $_[1];

    my $umask = option($repo, 'umask');
    _chdir($rc{GL_REPO_BASE});  # because using option() moves us to ADMIN_BASE!

    return unless $umask;

    # unlike the one in the rc file, this is a string
    umask oct($umask);
}

1;
