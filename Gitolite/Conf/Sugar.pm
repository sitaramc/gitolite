package Gitolite::Conf::Sugar;

# syntactic sugar for the conf file, including site-local macros
# ----------------------------------------------------------------------

@EXPORT = qw(
  macro_expand
  cleanup_conf_line
);

use Exporter 'import';

use lib $ENV{GL_BINDIR};
use Gitolite::Common;
use Gitolite::Rc;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub macro_expand {
    # site-local macros, if any, then gitolite internal macros, to munge the
    # input conf line if needed

    my @lines = @_;

    # TODO: user macros, how to allow the user to specify them?

    # cheat, to keep *our* regexes simple :)
    # XXX but this also kills the special '# BEGIN filename' and '# END
    # filename' lines that explode() surrounds the actual data with when it
    # called macro_expand().  Right now we don't need it, but...
    @lines = grep /\S/, map { cleanup_conf_line($_) } @lines;

    @lines = owner_desc(@lines);

    return @lines;
}

sub cleanup_conf_line {
    my $line = shift;

    # kill comments, but take care of "#" inside *simple* strings
    $line =~ s/^((".*?"|[^#"])*)#.*/$1/;
    # normalise whitespace; keeps later regexes very simple
    $line =~ s/=/ = /;
    $line =~ s/\s+/ /g;
    $line =~ s/^ //;
    $line =~ s/ $//;
    return $line;
}

sub owner_desc {
    my @lines = @_;
    my @ret;

    for my $line (@lines) {
        #       reponame = "some description string"
        #       reponame "owner name" = "some description string"
        if ( $line =~ /^(\S+)(?: "(.*?)")? = "(.*)"$/ ) {
            my ( $repo, $owner, $desc ) = ( $1, $2, $3 );
            # XXX these two checks should go into add_config
            # _die "bad repo name '$repo'" unless $repo =~ $REPONAME_PATT;
            # _die "$fragment attempting to set description for $repo"
            #   if check_fragment_repo_disallowed( $fragment, $repo );
            push @ret, "config gitolite-options.repo-desc = $desc";
            push @ret, "config gitolite-options.repo-owner = $owner" if $owner;
        } elsif ( $line =~ /^desc = (\S.*)/ ) {
            push @ret, "config gitolite-options.repo-desc = $1";
        } elsif ( $line =~ /^owner = (\S.*)/ ) {
            my ( $repo, $owner, $desc ) = ( $1, $2, $3 );
            push @ret, "config gitolite-options.repo-owner = $1";
        } else {
            push @ret, $line;
        }
    }
    return @ret;
}

1;

