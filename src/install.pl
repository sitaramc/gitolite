#!/usr/bin/perl

use strict;
use warnings;

our $REPO_BASE;
our $GL_ADMINDIR;
our $GL_CONF;

# wrapper around mkdir; it's not an error if the directory exists, but it is
# an error if it doesn't exist and we can't create it
sub wrap_mkdir
{
    my $dir = shift;
    -d $dir or mkdir($dir) or die "mkdir $dir failed: $!\n";
}

# the only path that is *fixed* (can't be changed without changing all 3
# programs) is ~/.gitolite.rc

my $glrc = $ENV{HOME} . "/.gitolite.rc";
unless (-f $glrc) {
    # doesn't exist.  Copy it across, tell user to edit it and come back
    system("cp conf/example.gitolite.rc $glrc");
    print STDERR "created $glrc\n";
    print STDERR "please edit it, set the paths as you like, and rerun this script\n";
    exit;
}

# ok now $glrc exists; read it to get the other paths
unless (my $ret = do $glrc)
{
    die "parse $glrc failed: $@" if $@;
    die "couldn't do $glrc: $!"  unless defined $ret;
    die "couldn't run $glrc"     unless $ret;
}

# mkdir $REPO_BASE, $GL_ADMINDIR if they don't already exist
wrap_mkdir( $REPO_BASE =~ m(^/) ? $REPO_BASE : "$ENV{HOME}/$REPO_BASE" );
wrap_mkdir($GL_ADMINDIR);
# mkdir $GL_ADMINDIR's subdirs
for my $dir qw(conf doc keydir src) {
    wrap_mkdir("$GL_ADMINDIR/$dir");
}

# "src" and "doc" will be overwritten on each install, but not conf
system("cp -R src doc $GL_ADMINDIR");

unless (-f $GL_CONF) {
    system("cp conf/example.conf $GL_CONF");
    print STDERR <<EOF;
    created $GL_CONF
    please edit it, then run these two commands:
        cd $GL_ADMINDIR
        src/gl-compile-conf
    (the "admin" document should help here...)
EOF
}
