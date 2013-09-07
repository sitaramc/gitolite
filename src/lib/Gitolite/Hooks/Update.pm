package Gitolite::Hooks::Update;

# everything to do with the update hook
# ----------------------------------------------------------------------

@EXPORT = qw(
  update
  update_hook
);

use Exporter 'import';

use Gitolite::Rc;
use Gitolite::Common;
use Gitolite::Conf::Load;

use strict;
use warnings;

# ----------------------------------------------------------------------

sub update {
    # this is the *real* update hook for gitolite

    bypass() if $ENV{GL_BYPASS_ACCESS_CHECKS};

    my ( $ref, $oldsha, $newsha, $oldtree, $newtree, $aa ) = args(@ARGV);

    trace( 1, 'update', $ENV{GL_REPO}, $ENV{GL_USER}, $aa, @ARGV );

    my $ret = access( $ENV{GL_REPO}, $ENV{GL_USER}, $aa, $ref );
    trigger( 'ACCESS_2', $ENV{GL_REPO}, $ENV{GL_USER}, $aa, $ref, $ret, $oldsha, $newsha );
    _die $ret if $ret =~ /DENIED/;

    check_vrefs( $ref, $oldsha, $newsha, $oldtree, $newtree, $aa );

    gl_log( 'update', $ENV{GL_REPO}, $ENV{GL_USER}, $aa, @ARGV, $ret);
    exit 0;
}

sub bypass {
    require Cwd;
    Cwd->import;
    gl_log( 'update', getcwd(), '(' . ( $ENV{USER} || '?' ) . ')', 'bypass', @ARGV );
    exit 0;
}

sub check_vrefs {
    my ( $ref, $oldsha, $newsha, $oldtree, $newtree, $aa ) = @_;
    my $name_seen = 0;
    my $n_vrefs   = 0;
    for my $vref ( vrefs( $ENV{GL_REPO}, $ENV{GL_USER} ) ) {
        $n_vrefs++;
        if ( $vref =~ m(^VREF/NAME/) ) {
            # this one is special; we process it right here, and only once
            next if $name_seen++;

            for my $ref ( map { chomp; s(^)(VREF/NAME/); $_; } `git diff --name-only $oldtree $newtree` ) {
                check_vref( $aa, $ref );
            }
        } else {
            my ( $dummy, $pgm, @args ) = split '/', $vref;
            $pgm = _which("VREF/$pgm", 'x');
            $pgm or _die "'$vref': helper program missing or unexecutable";

            open( my $fh, "-|", $pgm, @_, $vref, @args ) or _die "'$vref': can't spawn helper program: $!";
            while (<$fh>) {
                # print non-vref lines and skip processing (for example,
                # normal STDOUT by a normal update hook)
                unless (m(^VREF/)) {
                    print;
                    next;
                }
                my ( $ref, $deny_message ) = split( ' ', $_, 2 );
                check_vref( $aa, $ref, $deny_message );
            }
            close($fh) or _die $!
              ? "Error closing sort pipe: $!"
              : "$vref: helper program exit status $?";
        }
    }
    return $n_vrefs;
}

sub check_vref {
    my ( $aa, $ref, $deny_message ) = @_;

    my $ret = access( $ENV{GL_REPO}, $ENV{GL_USER}, $aa, $ref );
    trace( 2, "access($ENV{GL_REPO}, $ENV{GL_USER}, $aa, $ref)", "-> $ret" );
    trigger( 'ACCESS_2', $ENV{GL_REPO}, $ENV{GL_USER}, $aa, $ref, $ret );
    _die "$ret" . ( $deny_message ? "\n$deny_message" : '' )
      if $ret =~ /DENIED/ and $ret !~ /by fallthru/;
    trace( 2, "remember, fallthru is success here!" ) if $ret =~ /by fallthru/;
}

{
    my $text = '';

    sub update_hook {
        if ( not $text ) {
            local $/ = undef;
            $text = <DATA>;
        }
        return $text;
    }
}

# ----------------------------------------------------------------------

sub args {
    my ( $ref, $oldsha, $newsha ) = @_;
    my ( $oldtree, $newtree, $aa );

    # this is special to git -- the hash of an empty tree
    my $empty = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
    $oldtree = $oldsha eq '0' x 40 ? $empty : $oldsha;
    $newtree = $newsha eq '0' x 40 ? $empty : $newsha;

    my $merge_base = '0' x 40;
    # for branch create or delete, merge_base stays at '0'x40
    chomp( $merge_base = `git merge-base $oldsha $newsha` )
      unless $oldsha eq '0' x 40
          or $newsha eq '0' x 40;

    $aa = 'W';
    # tag rewrite
    $aa = '+' if $ref =~ m(refs/tags/) and $oldsha ne ( '0' x 40 );
    # non-ff push to ref (including ref delete)
    $aa = '+' if $oldsha ne $merge_base;

    $aa = 'D' if ( option( $ENV{GL_REPO}, 'DELETE_IS_D' ) ) and $newsha eq '0' x 40;
    $aa = 'C' if ( option( $ENV{GL_REPO}, 'CREATE_IS_C' ) ) and $oldsha eq '0' x 40;

    # and now "M" commits.  All the other accesses (W, +, C, D) were mutually
    # exclusive in some sense.  Sure a W could be a C or a + could be a D but
    # that's by design.  A merge commit, however, could still be any of the
    # others (except a "D").

    # so we have to *append* 'M' to $aa (if the repo has MERGE_CHECK in
    # effect and this push contains a merge inside)

    if ( option( $ENV{GL_REPO}, 'MERGE_CHECK' ) ) {
        if ( $oldsha eq '0' x 40 or $newsha eq '0' x 40 ) {
            _warn "ref create/delete ignored for purposes of merge-check\n";
        } else {
            $aa .= 'M' if `git rev-list -n 1 --merges $oldsha..$newsha` =~ /./;
        }
    }

    return ( $ref, $oldsha, $newsha, $oldtree, $newtree, $aa );
}

1;

__DATA__
#!/usr/bin/perl

use strict;
use warnings;

use lib $ENV{GL_LIBDIR};
use Gitolite::Hooks::Update;

# gitolite update hook
# ----------------------------------------------------------------------

update();               # is not expected to return
exit 1;                 # so if it does, something is wrong
