#!/usr/bin/perl
use strict;
use warnings;
use 5.10.0;

# usage: ./fm2mt.pl < g3-master-toc.mm > master-toc.mkd

use HTML::Entities;

sub out { my $out = shift; print $out; }

# freemind to "dense" HTML
my @in = fm2indent();

out("# gitolite documentation");
my $started = 0;
for (@in) {
    my($indent, $text) = split ' ', $_, 2;
    $indent--;

    if (not $indent) {
        out "\n\n## $text\n";
        $started = 0;
        next;
    }

    if ($indent == 1) {
        # (dense mode) $text = color("red", $text);
    }

    if ($indent <= 2) {
        # (dense mode) $text = size(2 - $indent, $text);
    } else {
        # 3 or more
        # (dense mode) $text = ("/" x ($indent-4)) . color("gray", $text);
    }

    # normal mode
    $text = "\n" . ("    " x ($indent-1)) . "  * $text";
    # (dense mode) out " -- " if $started++;
    out $text;
}

sub size {
    my ($s, $t) = @_;
    return "<font size=\"+" . $s . "\">$t</font>" if $s;
    return $t;
}

sub color {
    my ($c, $t) = @_;
    return "<font color=\"$c\">$t</font>";
}

sub get_indent {
    my $_ = shift;
    chomp;
    return () unless /\S/;
    if (/^(#+) (.*)/) {
        return (length($1)-1, $2);
    }
    if (/^( +)  \* (.*)/) {
        my $t = $2;
        my $i = length($1);
        die 1 if $i % 4;
        $i = $i/4 + 3;

        return ($i, $t);
    }
    return ();
}

sub fm2indent {
    my @out = ();
    my $indent=0;

    while (<>)
    {
        next unless /^<node / or /^<\/node/;
        if (/^<\/node>$/)
        {
            $indent--;
            next;
        }
        next unless /TEXT="([^"]*)"/;
        my $text = decode_entities($1);

        push @out, "\n$indent $text" if $indent;

        $indent++ unless (/\/>/);
    }

    return @out;
}
