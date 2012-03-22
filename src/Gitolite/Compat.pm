#!/usr/bin/perl

# a quick and dirty program to warn about compatibilities issues in your
# current gitolite 2 setup, with the new one.

@EXPORT = qw(
);

use Exporter 'import';

use lib $ENV{GL_BINDIR};
use Gitolite::Common;

my $header_printed = 0;

my $glrc = "$ENV{HOME}/.gitolite.rc";
do "$glrc";
if (defined($GL_ADMINDIR)) {
    check_compat();
    if ($header_printed) {
        say2 "Please read the documentation for additional details on migrating.\n\n"
    } else {
        say2 "
It looks like there were no real issues found, but you should still read the
documentation for additional details on migrating.

";
    }
}

sub check_compat {
    chdir($GL_ADMINDIR) or die "FATAL: could not chdir to $GL_ADMINDIR\n";

    my $conf = `find . -name "*.conf" | xargs cat`;

    g2warn("MUST fix", "fallthru in NAME rules; this affects user's push rights")
      if $conf =~ m(NAME/);

    g2warn("MUST fix", "subconf command in admin repo; this affects conf compilation")
      if $conf =~ m(NAME/conf/fragments);
}

sub header {
    return if $header_printed;
    $header_printed++;

    say2 "
    The following is a list of compat issues found, if any.  Please see the
    compatibility with gitolite 2' section of the documentation for additional
    details on each issue found.\n";
}

sub g2warn {
    my ($cat, $msg) = @_;
    header();
    say2 "$cat: $msg\n";
}

1;

