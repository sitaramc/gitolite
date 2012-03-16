#!/usr/bin/perl
use strict;
use warnings;

my @a = `grep -r use.Gitolite . | grep -i '^./gitolite'`;

# chomp(@a);
open( my $fh, "|-", "tee module-tree.gv | dot -Tpng | tee module-tree.png | display" );

@a = map {
    print $fh "#$_";
    s/^\.\/gitolite\///i;
    s/-/_/g;
    s/\.\///;
    s/\//_/g;
    s/\.pm:/ -> /;
    s/use Gitolite:://;
    s/::/_/g;
    s/:/ -> /;
    s/;//;
    s/^(\S+) -> \1$//;
    s/.* -> Rc//;
    s/.* -> Common//;
    $_;
} @a;

# open(my $fh, "|-", "cat > /tmp/junkg3");
print $fh "digraph G {\n";
print $fh $_ for @a;
print $fh "}\n";
close $fh;
