package Gitolite::Triggers::Alias;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

# aliasing a repo to another
# ----------------------------------------------------------------------

=for usage

Why:

    We had an existing repo "foo" that lots of people use.  We wanted to
    rename it to "foo/code", so that related repos "foo/upstream" and
    "foo/docs" (both containing stuff we did not want to put in "foo") could
    also be made and then the whole thing would be structured nicely.

    At the same time we did not want to *force* all the users to change the
    name.  At least git operations should still work with the old name,
    although it is OK for "info" and other "commands" to display/require the
    proper name (i.e., the new name).

How:

  * add a new variable REPO_ALIASES to the rc file, with entries like:

        REPO_ALIASES                =>
            {
                'foo'               =>  'foo/code',
            }

  * add the following line to the INPUT section in the rc file:

        'Alias::input',

Notes:

  * only git operations (clone/fetch/push) are alias aware.  Nothing else in
    gitolite, such as all the gitolite commands etc., are alias-aware and will
    always use/require the proper repo name.

  * http mode has not been tested and will not be.  If someone has the time to
    test it and make it work please let me know.

  * funnily enough, this even works with mirroring!  That is, a master can
    push a repo "foo" to a slave per its configuration, while the slave thinks
    it is getting repo "bar" from the master per its configuration.

    Just make sure to put the Alias::input line *before* the Mirroring::input
    line in the rc file on the slave.

    However, it will probably not work with redirected pushes unless you setup
    the opposite alias ("bar" -> "foo") on master.
=cut

sub input {
    my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
    my $user = $ARGV[0] || '@all';    # user name is undocumented for now

    if ( $ENV{SSH_ORIGINAL_COMMAND} =~ /(?:$git_commands) '(\S+)'$/ ) {
        my $repo = $1;
        ( my $norm = $repo ) =~ s/\.git$//;    # normalised repo name

        my $target;

        return unless $target = $rc{REPO_ALIASES}{$norm};
        $target = $target->{$user} if ref($target) eq 'HASH';
        return unless $target;

        _warn "'$norm' is an alias for '$target'";

        $ENV{SSH_ORIGINAL_COMMAND} =~ s/'$repo'/'$target'/;
    }

}

1;
