package Gitolite::Triggers::Motd;

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# print a message of the day to STDERR
# ----------------------------------------------------------------------

my $file = "gl-motd";

sub input {
    # at present, we print it for every single interaction with gitolite.  We
    # may want to change that later; if we do, get code from Kindergarten.pm
    # to get the gitcmd+repo or cmd+args so you can filter on them

    my $f = "$rc{GL_ADMIN_BASE}/$file";
    print STDERR slurp($f) if -f $f;
}

sub pre_git {
    my $repo = $_[1];
    my $f    = "$rc{GL_REPO_BASE}/$repo.git/$file";
    print STDERR slurp($f) if -f $f;
}

1;
