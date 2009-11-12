#!/usr/bin/perl

use strict;
use warnings;

# === update ===
# this is gitolite's update hook

# part of the gitolite (GL) suite

# how run:      via git, being copied as .git/hooks/update in every repo
# when:         every push
# input:
#     - see man githooks for STDIN
#     - uses the compiled config file to get permissions info
# output:       based on permissions etc., exit 0 or 1
# security:
#     - none

# robustness:

# other notes:

# ----------------------------------------------------------------------------
#       common definitions
# ----------------------------------------------------------------------------

our ($GL_CONF_COMPILED, $PERSONAL);
our %repos;

# we should already have the GL_RC env var set when we enter this hook
die "parse $ENV{GL_RC} failed: "       . ($! or $@) unless do $ENV{GL_RC};
# then "do" the compiled config file, whose name we now know
die "parse $GL_CONF_COMPILED failed: " . ($! or $@) unless do $GL_CONF_COMPILED;

# ----------------------------------------------------------------------------
#       start...
# ----------------------------------------------------------------------------

my $ref = shift;
my $oldsha = shift;
my $newsha = shift;
my $merge_base = '0' x 40;
# compute a merge-base if both SHAs are non-0, else leave it as '0'x40
# (i.e., for branch create or delete, merge_base == '0'x40)
chomp($merge_base = `git merge-base $oldsha $newsha`)
    unless $oldsha eq '0' x 40
        or $newsha eq '0' x 40;

# some of this is from an example hook in Documentation/howto of git.git, with
# some variations

# what are you trying to do?  (is it 'W' or '+'?)
my $perm = 'W';
# rewriting a tag is considered a rewind, in terms of permissions
$perm = '+' if $ref =~ m(refs/tags/) and $oldsha ne ('0' x 40);
# non-ff push to ref
# notice that ref delete looks like a rewind, as it should
$perm = '+' if $oldsha ne $merge_base;

my @allowed_refs;
# personal stuff -- right at the start in the new regime, I guess!
push @allowed_refs, { "$PERSONAL/$ENV{GL_USER}/" => "RW+" } if $PERSONAL;
# we want specific perms to override @all, so they come first
push @allowed_refs, @ { $repos{$ENV{GL_REPO}}{$ENV{GL_USER}} || [] };
push @allowed_refs, @ { $repos{$ENV{GL_REPO}}{'@all'} || [] };
for my $ar (@allowed_refs)
{
    my $refex = (keys %$ar)[0];
    # refex?  sure -- a regex to match a ref against :)
    next unless $ref =~ /$refex/;
    if ($ar->{$refex} =~ /\Q$perm/)
    {
        # if log failure isn't important enough to block pushes, get rid of
        # all the error checking
        open my $log_fh, ">>", $ENV{GL_LOG}
            or die "open log failed: $!\n";
        print $log_fh "$ENV{GL_TS}  $perm\t" .
            substr($oldsha, 0, 14) . "\t" . substr($newsha, 0, 14) .
            "\t$ENV{GL_REPO}\t$ref\t$ENV{GL_USER}\t$refex\n";
        close $log_fh or die "close log failed: $!\n";
        exit 0;
    }
}
die "$perm $ref $ENV{GL_REPO} $ENV{GL_USER} DENIED by fallthru\n";
