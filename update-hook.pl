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

our $GL_ADMINDIR;
our $GL_CONF;
our $GL_KEYDIR;
our $GL_CONF_COMPILED;
our $REPO_BASE;
our %repos;

my $glrc = $ENV{HOME} . "/.gitolite.rc";
unless (my $ret = do $glrc)
{
    die "parse $glrc failed: $@" if $@;
    die "couldn't do $glrc: $!"  unless defined $ret;
    die "couldn't run $glrc"     unless $ret;
}

die "couldnt do perms file" unless (my $ret = do $GL_CONF_COMPILED);

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
# non-ff push to branch.  Notice that branch delete looks like a rewind, as it
# should
$perm = '+' if $ref =~ m(refs/heads/) and $oldsha ne $merge_base;

my $allowed_refs = $repos{$ENV{GL_REPO}}{$perm}{$ENV{GL_USER}};
for my $refex (@$allowed_refs)
# refex?  sure -- a regex to match a ref against :)
{
    if ($ref =~ /$refex/)
    {
        # if log failure isn't important enough to block pushes, get rid of
        # all the error checking
        open my $log_fh, ">>", "$GL_ADMINDIR/log"
            or die "open log failed: $!";
        print $log_fh "$perm: $ENV{GL_USER} $ENV{GL_REPO} $ref $oldsha $newsha\n";
        close $log_fh or die "close log failed: $!";
        exit 0;
    }
}
exit 1;
