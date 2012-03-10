package Gitolite::Hooks::PostUpdate;

# everything to do with the post-update hook
# ----------------------------------------------------------------------

@EXPORT = qw(
  post_update
  post_update_hook
);

use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub post_update {
    trace(3);
    # this is the *real* post_update hook for gitolite

    tsh_try("git ls-tree --name-only master");
    _die "no files/dirs called 'hooks' or 'logs' are allowed" if tsh_text() =~ /^(hooks|logs)$/;

    {
        local $ENV{GIT_WORK_TREE} = $rc{GL_ADMIN_BASE};
        tsh_try("git checkout -f --quiet master");
    }
    _system("$ENV{GL_BINDIR}/gitolite compile");

    exit 0;
}

{
    my $text = '';

    sub post_update_hook {
        trace(1);
        if ( not $text ) {
            local $/ = undef;
            $text = <DATA>;
        }
        return $text;
    }
}

1;

__DATA__
#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    die "GL_BINDIR not set; aborting\n" unless $ENV{GL_BINDIR};
}
use lib $ENV{GL_BINDIR};
use Gitolite::Hooks::PostUpdate;

# gitolite post-update hook (only for the admin repo)
# ----------------------------------------------------------------------

post_update(@ARGV);     # is not expected to return
exit 1;                 # so if it does, something is wrong
