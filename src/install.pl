#!/usr/bin/perl

use strict;
use warnings;

our ($REPO_BASE, $GL_ADMINDIR, $GL_CONF, $GIT_PATH);

# wrapper around mkdir; it's not an error if the directory exists, but it is
# an error if it doesn't exist and we can't create it
sub wrap_mkdir
{
    my $dir = shift;
    if ( -d $dir ) {
        print STDERR "$dir already exists\n";
        return;
    }
    mkdir($dir) or die "mkdir $dir failed: $!\n";
    print STDERR "created $dir\n";
}

# the common setup module is in the same directory as this running program is
my $bindir = $0;
$bindir =~ s/\/[^\/]+$//;
require "$bindir/gitolite.pm";

# ask where the rc file is, get it, and "do" it
&where_is_rc();
unless ($ENV{GL_RC}) {
    # doesn't exist.  Copy it across, tell user to edit it and come back
    my $glrc = $ENV{HOME} . "/.gitolite.rc";
    system("cp conf/example.gitolite.rc $glrc");
    print STDERR "created $glrc\n";
    print STDERR "please edit it, change the paths if you wish to, and RERUN THIS SCRIPT\n";
    exit;
}

# ok now the rc file exists; read it to get the other paths
die "parse $ENV{GL_RC} failed: " . ($! or $@) unless do $ENV{GL_RC};

# add a custom path for git binaries, if specified
$ENV{PATH} .= ":$GIT_PATH" if $GIT_PATH;

# mkdir $REPO_BASE, $GL_ADMINDIR if they don't already exist
my $repo_base_abs = ( $REPO_BASE =~ m(^/) ? $REPO_BASE : "$ENV{HOME}/$REPO_BASE" );
wrap_mkdir($repo_base_abs);
wrap_mkdir($GL_ADMINDIR);
# mkdir $GL_ADMINDIR's subdirs
for my $dir qw(conf doc keydir logs src) {
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

# finally, any potential changes to src/update-hook.pl must be propagated to
# all the repos' hook directories
chdir("$repo_base_abs") or die "chdir $repo_base_abs failed: $!\n";
for my $repo (`find . -type d -name "*.git"`) {
    chomp ($repo);
    system("cp $GL_ADMINDIR/src/update-hook.pl $repo/hooks/update");
    chmod 0755, "$repo/hooks/update";
}

# oh and one of those repos is a bit more special and has an extra hook :)
if ( -d "gitolite-admin.git/hooks" ) {
    print STDERR "copying post-update hook to gitolite-admin repo...\n";
    system("cp -v $GL_ADMINDIR/src/pta-hook.sh gitolite-admin.git/hooks/post-update");
    system("perl", "-i", "-p", "-e", "s(export GL_ADMINDIR=.*)(export GL_ADMINDIR=$GL_ADMINDIR)",
        "gitolite-admin.git/hooks/post-update");
    chmod 0755, "gitolite-admin.git/hooks/post-update";
}
