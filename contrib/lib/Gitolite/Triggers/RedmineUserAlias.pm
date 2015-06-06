package Gitolite::Triggers::RedmineUserAlias;

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

# aliasing a redmine username to a more user-friendly one
# ----------------------------------------------------------------------

=for usage

Why:

    Redmine creates users like "redmine_alice_123"; we want the users to just
    see "alice" instead of that.

Assumption:

*   Redmine does not allow duplicates in the middle bit; i.e., you can't
    create redmine_alice_123 and redmine_alice_456 also.

How:

*   add this code as lib/Gitolite/Triggers/RedmineUserAlias.pm to your
    site-local code directory; see this link for how:

        http://gitolite.com/gitolite/non-core.html#ncloc

*   add the following to the rc file, just before the ENABLE section (don't
    forget the trailing comma):

        INPUT   =>  [ 'RedmineUserAlias::input' ],

Notes:

*   http mode has not been tested and will not be.  If someone has the time to
    test it and make it work please let me know.

*   not tested with mirroring.

Quote:

*   "All that for what is effectively one line of code.  I need a life".

=cut

sub input {
    $ARGV[0] or _die "no username???";
    $ARGV[0] =~ s/^redmine_(\S+)_\d+$/$1/;
}

1;
