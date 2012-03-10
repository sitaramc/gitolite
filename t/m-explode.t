#!/usr/bin/perl
use strict;
use warnings;
use 5.10.0;

use Test;
BEGIN { plan tests =>
    2
}

use lib "$ENV{PWD}/src";
use Gitolite::Test;
use Gitolite::Conf::Explode;

my @out;
my @out2;

warn "
        <<< expect a couple of warnings about already included files >>>
";

# test 1 -- space normalisation

    put "foo", "
        foo line 1          
                                foo=line 2


        foo      3
    ";
    @out = ();
    explode("foo", 'master', \@out);
    @out2 = (
        'foo line 1',
        'foo = line 2',
        'foo 3',
    );

    ok(@out ~~ @out2);

# test 2 -- include/subconf processing

    put "foo", "
        foo line 1
        \@fog=line 2
            include                         \"bar.conf\"

        foo line=5
            subconf \"subs/baz.conf\"
            include                         \"bar.conf\"
        foo line=7
            include \"bazup.conf\"
    ";

    put "bar.conf", "
        \@brg=line 1

        bar line 3
    ";

    mkdir("subs");

    put "subs/baz.conf", "
        \@bzg         =           line 1

            include \"subs/baz2.conf\"

        baz=line 3
    ";

    put "subs/baz2.conf", "
        baz2 line 1
        baz2 line 2
            include \"bazup.conf\"
        baz2 line 4
    ";

    put "bazup.conf", "
        whatever...
    ";

    @out = ();
    explode("foo", 'master', \@out);

    @out2 = (
        'foo line 1',
        '@fog = line 2',
        '@brg = line 1',
        'bar line 3',
        'foo line = 5',
        'subconf baz',
        '@baz.bzg = line 1',
        'baz2 line 1',
        'baz2 line 2',
        'whatever...',
        'baz2 line 4',
        'baz = line 3',
        'subconf master',
        'foo line = 7'
    );

    ok(@out ~~ @out2);
