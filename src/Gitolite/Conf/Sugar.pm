# and now for something completely different...

package SugarBox;

sub run_sugar_script {
    my ( $ss, $lref ) = @_;
    do $ss if -x $ss;
    $lref = sugar_script($lref);
    return $lref;
}

# ----------------------------------------------------------------------

package Gitolite::Conf::Sugar;

# syntactic sugar for the conf file, including site-local macros
# ----------------------------------------------------------------------

@EXPORT = qw(
  sugar
);

use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Explode;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub sugar {
    # gets a filename, returns a listref

    my @lines = ();
    explode( shift, 'master', \@lines );

    my $lines;
    $lines = \@lines;

    # run through the sugar stack one by one

    # first, user supplied sugar:
    if ( exists $rc{SYNTACTIC_SUGAR} ) {
        if ( ref( $rc{SYNTACTIC_SUGAR} ) ne 'ARRAY' ) {
            _warn "bad syntax for specifying sugar scripts; see docs";
        } else {
            for my $s ( @{ $rc{SYNTACTIC_SUGAR} } ) {

                # perl-ism; apart from keeping the full path separate from the
                # simple name, this also protects %rc from change by implicit
                # aliasing, which would happen if you touched $s itself
                my $sfp = "$ENV{GL_BINDIR}/syntactic-sugar/$s";

                _warn("skipped sugar script '$s'"), next if not -x $sfp;
                $lines = SugarBox::run_sugar_script( $sfp, $lines );
                $lines = [ grep /\S/, map { cleanup_conf_line($_) } @$lines ];
            }
        }
    }

    # then our stuff:

    $lines = rw_cdm($lines);
    $lines = option($lines);       # must come after rw_cdm
    $lines = owner_desc($lines);
    $lines = name_vref($lines);

    return $lines;
}

sub rw_cdm {
    my $lines = shift;
    my @ret;

    # repo foo <...> RWC = ...
    #   ->  option CREATE_IS_C = 1
    # (and similarly DELETE_IS_D and MERGE_CHECK)
    # but only once per repo of course

    my %seen = ();
    for my $line (@$lines) {
        push @ret, $line;
        if ( $line =~ /^repo / ) {
            %seen = ();
        } elsif ( $line =~ /^(-|C|R|RW\+?(?:C?D?|D?C?)M?) (.* )?= (.+)/ ) {
            my $perms = $1;
            push @ret, "option DELETE_IS_D = 1" if $perms =~ /D/     and not $seen{D}++;
            push @ret, "option CREATE_IS_C = 1" if $perms =~ /RW.*C/ and not $seen{C}++;
            push @ret, "option MERGE_CHECK = 1" if $perms =~ /M/     and not $seen{M}++;
        }
    }
    return \@ret;
}

sub option {
    my $lines = shift;
    my @ret;

    # option foo = bar
    #   ->  config gitolite-options.foo = bar

    for my $line (@$lines) {
        if ( $line =~ /^option (\S+) = (\S.*)/ ) {
            push @ret, "config gitolite-options.$1 = $2";
        } else {
            push @ret, $line;
        }
    }
    return \@ret;
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

sub name_vref {
    my $lines = shift;
    my @ret;

    # <perm> NAME/foo = <user>
    #   ->  <perm> VREF/NAME/foo = <user>

    for my $line (@$lines) {
        if ( $line =~ /^(-|R\S+) \S.* = \S.*/ ) {
            $line =~ s( NAME/)( VREF/NAME/)g;
        }
        push @ret, $line;
    }
    return \@ret;
}

1;

