#!/usr/bin/perl -w

use strict;
use warnings;

# migrate gitosis.conf to gitolite.conf format

# not very smart, but there shouldn't be any errors for simple configurations.
# the biggest thing you'll find is probably some comments rearranged or
# something, due to the "flush" thing below

# for stuff it can't handle, it'll ignore the trivial ones (like gitweb and
# daemon), and put in an obviously syntax error-ed line for "repositories" and
# "map" statements.

my @repos;
my @RO_repos;
my @comments;
my @users;
my $groupname;

# a gitosis.conf stanza ends when a new "[group name]" line shows up, so you
# can't write as you go; you have to accumulate and flush
sub flush {
    die "repos but no users?\n" if (not @users and (@repos or @RO_repos));
    # just a groupname
    if (@users and not (@repos or @RO_repos)) {
        print "\@$groupname = ", join(" ", @users), "\n";
    }
    # RW repos
    if (@repos)
    {
        print "repo ", join(" ", @repos), "\n";
        print "    RW = ", join(" ", @users), "\n";
    }
    # RO repos
    if (@RO_repos)
    {
        print "repo ", join(" ", @RO_repos), "\n";
        print "    R  = ", join(" ", @users), "\n";
    }
    # comments; yes there'll be some reordering, sorry!
    print @comments if @comments;

    # empty out for next round
    @users = ();
    @repos = ();
    @RO_repos = ();
    @comments = ();
}

while (<>)
{
    # pure comment lines or blank lines
    if (/^\s*#/ or /^\s*$/) {
        push @comments, $_;
        next;
    }

    # not supported
    if (/^repositories *=/ or /^map /) {
        print STDERR "not supported: $_";
        s/^/NOT SUPPORTED: /;
        print;
        next;
    }

    chomp;

    # normalise whitespace to help later regexes
    s/\s+/ /g;
    s/ ?= ?/ = /;
    s/^ //;
    s/ $//;

    # the chaff...
    next if     /^\[(gitosis|repo)\]$/
            or  /^(gitweb|daemon|loglevel|description|owner) =/;

    # the wheat...
    if (/^members = (.*)/) {
        push @users, split(' ', $1);
        next;
    }
    if (/^write?able = (.*)/) {
        push @repos, split(' ', $1);
        next;
    }
    if (/^readonly = (.*)/) {
        push @RO_repos, split(' ', $1);
        next;
    }

    # new group starts
    if (/^\[group (.*?) ?\]/) {
        flush();
        $groupname = $1;
    }
}

flush();
