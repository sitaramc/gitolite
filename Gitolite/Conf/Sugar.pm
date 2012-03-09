package Gitolite::Conf::Sugar;

# syntactic sugar for the conf file, including site-local macros
# ----------------------------------------------------------------------

@EXPORT = qw(
  sugar
);

use Exporter 'import';

use lib $ENV{GL_BINDIR};
use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Explode;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub sugar {
    # gets a filename, returns a listref

    my @lines = ();
    explode(shift, 'master', \@lines);

    my $lines;
    $lines = \@lines;

    # run through the sugar stack one by one

    # first, user supplied sugar:
    if (exists $rc{SYNTACTIC_SUGAR}) {
        if (ref($rc{SYNTACTIC_SUGAR}) ne 'ARRAY') {
            _warn "bad syntax for specifying sugar scripts; see docs";
        } else {
            for my $s (@{ $rc{SYNTACTIC_SUGAR} }) {
                _warn "ignoring unreadable sugar script $s" if not -r $s;
                do $s if -r $s;
                $lines = sugar_script($lines);
                $lines = [ grep /\S/, map { cleanup_conf_line($_) } @$lines ];
            }
        }
    }

    # then our stuff:

    $lines = owner_desc($lines);
    # $lines = name_vref($lines);

    return $lines;
}

sub owner_desc {
    my $lines = shift;
    my @ret;

    # XXX compat breakage: (1) adding repo/owner does not automatically add an
    # entry to projects.list -- we need a post-procesor for that, and (2)
    # removing the 'repo' line no longer suffices to remove the config entry
    # from projects.list.  Maybe the post-procesor should do that as well?

    # owner = "owner name"
    #   ->  config gitweb.owner = owner name
    # description = "some long description"
    #   ->  config gitweb.description = some long description
    # category = "whatever..."
    #   ->  config gitweb.category = whatever...

    # older formats:
    # repo = "some long description"
    # repo = "owner name" = "some long description"
    #   ->  config gitweb.owner = owner name
    #   ->  config gitweb.description = some long description

    for my $line (@$lines) {
        if ( $line =~ /^(\S+)(?: "(.*?)")? = "(.*)"$/ ) {
            my ( $repo, $owner, $desc ) = ( $1, $2, $3 );
            # XXX these two checks should go into add_config
            # _die "bad repo name '$repo'" unless $repo =~ $REPONAME_PATT;
            # _die "$fragment attempting to set description for $repo"
            #   if check_fragment_repo_disallowed( $fragment, $repo );
            push @ret, "repo $repo";
            push @ret, "config gitweb.description = $desc";
            push @ret, "config gitweb.owner = $owner" if $owner;
        } elsif ( $line =~ /^desc = (\S.*)/ ) {
            push @ret, "config gitweb.description = $1";
        } elsif ( $line =~ /^owner = (\S.*)/ ) {
            push @ret, "config gitweb.owner = $1";
        } elsif ( $line =~ /^category = (\S.*)/ ) {
            push @ret, "config gitweb.category = $1";
        } else {
            push @ret, $line;
        }
    }
    return \@ret;
}

1;

