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

  * uncomment the line "Alias" in the "user-visible behaviour" section in the
    rc file

  * add a new variable REPO_ALIASES to the rc file, with entries like:

        REPO_ALIASES                =>
            {
                # if you need a more aggressive warning message than the default
                WARNING             => "Please change your URLs to use '%new'; '%old' will not work after XXXX-XX-XX",

                # prefix mapping section
                PREFIX_MAPS         =>  {
                    # note: NO leading slash in keys or values below
                    'var/lib/git/'  =>  '',
                    'var/opt/git/'  =>  'opt/',
                },

                # individual repo mapping section
                'foo'               =>  'foo/code',

                # force users to change their URLs
                'bar'               =>  '301/bar/code',
                    # a target repo starting with "301/" won't actually work;
                    # it will just produce an error message pointing the user
                    # to the new name.  This allows admins to force users to
                    # fix their URLs.
            },

    If a prefix map is supplied, each key is checked (in *undefined* order),
    and the *first* key which matches the prefix of the repo will be applied.
    If more than one key matches (for example if you specify '/abc/def' as one
    key, and '/abc' as another), it is undefined which will get picked up.

    The result of this, (or the original repo name if no map was found), will
    then be subject to the individual repo mappings.  Since these are full
    repo names, there is no possibility of multiple matches.

Notes:

  * only git operations (clone/fetch/push) are alias aware.  Nothing else in
    gitolite, such as all the gitolite commands etc., are alias-aware and will
    always use/require the proper repo name.

  * http mode has not been tested and will not be.  If someone has the time to
    test it and make it work please let me know.

  * funnily enough, this even works with mirroring!  That is, a master can
    push a repo "foo" to a copy per its configuration, while the copy thinks
    it is getting repo "bar" from the master per its configuration.

    Just make sure to put the Alias::input line *before* the Mirroring::input
    line in the rc file on the copy.

    However, it will probably not work with redirected pushes unless you setup
    the opposite alias ("bar" -> "foo") on master.
=cut

sub input {
    my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
    my $user = $ARGV[0] || '@all';    # user name is undocumented for now

    if ( $ENV{SSH_ORIGINAL_COMMAND} =~ /(?:$git_commands) '\/?(\S+)'$/ ) {
        my $repo = $1;
        ( my $norm = $repo ) =~ s/\.git$//;    # normalised repo name

        my $target = $norm;

        # prefix maps first
        my $pm = $rc{REPO_ALIASES}{PREFIX_MAPS} || {};
        while (my($k, $v) = each %$pm) {
            last if $target =~ s/^$k/$v/;
            # no /i, /g, etc. by design
        }

        # individual repo map next
        $target = $rc{REPO_ALIASES}{$target} || $target;

        # undocumented; don't use without discussing on mailing list
        $target = $target->{$user} if ref($target) eq 'HASH';

        # if the repo name finally maps to empty, we bail, with no changes
        return unless $target;

        # we're done.  Did we actually change anything?
        return if $norm eq $target;

        # if the new name starts with "301/", inform and abort
        _die "please use '$target' instead of '$norm'" if $target =~ s(^301/)();
        # otherwise print a warning and continue with the new name
        my $wm = $rc{REPO_ALIASES}{WARNING} || "'%old' is an alias for '%new'";
        $wm =~ s/%new/$target/g;
        $wm =~ s/%old/$norm/g;
        _warn $wm;

        $ENV{SSH_ORIGINAL_COMMAND} =~ s/'\/?$repo'/'$target'/;
    }

}

1;
