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
    trace( 3, 'post-up', @ARGV );

    my $master=`git symbolic-ref HEAD`; chomp $master;

    exit 0 unless grep( $_ eq $master, @ARGV );
    # this is the *real* post_update hook for gitolite
    $master =~ s(.*/)();

    tsh_try("git ls-tree --name-only $master");
    _die "no files/dirs called 'hooks' or 'logs' are allowed" if tsh_text() =~ /^(hooks|logs)$/m;

    my $hooks_changed = 0;
    {
        local $ENV{GIT_WORK_TREE} = $rc{GL_ADMIN_BASE};

        tsh_try("git diff --name-only $master");
        $hooks_changed++ if tsh_text() =~ m(/hooks/common/);
        # the leading slash ensure that this hooks/common directory is below
        # some top level directory, not *at* the top.  That's LOCAL_CODE, and
        # it's actual name could be anything but it doesn't matter to us.

        tsh_try("git checkout -f --quiet $master");
    }
    _system("gitolite compile");
    _system("gitolite setup --hooks-only") if $hooks_changed;
    _system("gitolite trigger POST_COMPILE");

    exit 0;
}

{
    my $text = '';

    sub post_update_hook {
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

use lib $ENV{GL_LIBDIR};
use Gitolite::Hooks::PostUpdate;

# gitolite post-update hook (only for the admin repo)
# ----------------------------------------------------------------------

post_update();          # is not expected to return
exit 1;                 # so if it does, something is wrong
