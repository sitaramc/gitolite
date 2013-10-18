package Gitolite::Triggers::RefexExpr;
use strict;
use warnings;

# track refexes passed and evaluate expressions on them
# ----------------------------------------------------------------------
# see src/VREF/refex-expr for instructions and WARNINGS!

use Gitolite::Easy;

my %passed;
my %rules;
my $init_done = 0;

sub access_2 {
    # get out quick for repos that don't have any rules
    return if $init_done and not %rules;

    # but we don't really know that the first time, heh!
    if ( not $init_done ) {
        my $repo = $_[1];
        init($repo);
        return unless %rules;
    }

    my $refex = $_[5];
    return if $refex =~ /DENIED/;

    $passed{$refex}++;

    # evaluate the rules each time; it's not very expensive
    for my $k ( sort keys %rules ) {
        $ENV{ "GL_REFEX_EXPR_" . $k } = eval_rule( $rules{$k} );
    }
}

sub eval_rule {
    my $rule = shift;

    my $e;
    $e = join " ", map { convert($_) } split ' ', $rule;

    my $ret = eval $e;
    _die "eval '$e' -> '$@'" if $@;
    Gitolite::Common::trace( 1, "RefexExpr", "'$rule' -> '$e' -> '$ret'" );

    return "'$rule' -> '$e'" if $ret;
}

my %constant;
%constant = map { $_ => $_ } qw(1 not and or xor + - ==);
$constant{'-lt'} = '<';
$constant{'-gt'} = '>';
$constant{'-eq'} = '==';
$constant{'-le'} = '<=';
$constant{'-ge'} = '>=';
$constant{'-ne'} = '!=';

sub convert {
    my $i = shift;
    return $i if $i =~ /^-?\d+$/;
    return $constant{$i} || $passed{$i} || $passed{"refs/heads/$i"} || 0;
}

# called only once
sub init {
    $init_done = 1;
    my $repo = shift;

    # find all the rule expressions
    my %t = config( $repo, "^gitolite-options\\.refex-expr\\." );
    my ( $k, $v );
    # get rid of the cruft and store just the rule name as the key
    while ( ( $k, $v ) = each %t ) {
        $k =~ s/^gitolite-options\.refex-expr\.//;
        $rules{$k} = $v;
    }
}

1;
