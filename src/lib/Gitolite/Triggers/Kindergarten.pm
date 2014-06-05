package Gitolite::Triggers::Kindergarten;

# http://www.great-quotes.com/quote/424177
#   "Doctor, it hurts when I do this."
#   "Then don't do that!"

# Prevent various things that sensible people shouldn't be doing anyway. List
# of things it prevents is at the end of the program.

# If you were forced to enable this module because someone is *constantly*
# doing things that need to be caught, consider getting rid of that person.
# Because, really, who knows what *else* he/she is doing that can't be caught
# with some clever bit of code?

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

my %active;
sub active {
    # in rc, you either see just 'Kindergarten' to activate all features, or
    # 'Kindergarten U0 CREATOR' (i.e., a space sep list of features after the
    # word Kindergarten) to activate only those named features.

    # no features specifically activated; implies all of them are active
    return 1 if not %active;
    # else check if this specific feature is active
    return 1 if $active{ +shift };

    return 0;
}

my ( $verb, $repo, $cmd, $args );
sub input {
    # get the features to be activated, if supplied
    while ( $_[0] ne 'INPUT' ) {
        $active{ +shift } = 1;
    }

    # generally fill up variables you might use later
    my $git_commands = "git-upload-pack|git-receive-pack|git-upload-archive";
    if ( $ENV{SSH_ORIGINAL_COMMAND} =~ /($git_commands) '\/?(\S+)'$/ ) {
        $verb = $1;
        $repo = $2;
    } elsif ( $ENV{SSH_ORIGINAL_COMMAND} =~ /^(\S+) (.*)$/ ) {
        $cmd  = $1;
        $args = $2;
    }

    prevent_CREATOR($repo) if active('CREATOR') and $verb;
    prevent_0(@ARGV)       if active('U0')      and @ARGV;
}

sub prevent_CREATOR {
    my $repo = shift;
    _die "'CREATOR' not allowed as part of reponame" if $repo =~ /\bCREATOR\b/;
}

sub prevent_0 {
    my $user = shift;
    _die "'0' is not a valid username" if $user eq '0';
}

1;

__END__

CREATOR

    prevent literal 'CREATOR' from being part of a repo name

    a quirk deep inside gitolite would let this config

        repo foo/CREATOR/..*
            C   =   ...

    allow the creation of repos like "foo/CREATOR/bar", i.e., the word CREATOR is
    literally used.

    I consider this a totally pathological situation to check for.  The worst that
    can happen is someone ends up cluttering the server with useless repos.

    One solution could be to prevent this only for wild repos, but I can't be
    bothered to fine tune this, so this module prevents even normal repos from
    having the literal CREATOR in them.

    See https://groups.google.com/forum/#!topic/gitolite/cS34Vxix0Us for more.

U0

    prevent a user from being called literal '0'

    Ideally we should prevent keydir/0.pub (or variants) from being created,
    but for "Then don't do that" purposes it's enough to prevent the user from
    logging in.

    See https://groups.google.com/forum/#!topic/gitolite/F1IBenuSTZo for more.
