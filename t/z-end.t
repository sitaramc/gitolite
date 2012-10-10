#!/usr/bin/env perl
use strict;
use warnings;

# this is hardcoded; change it if needed
use lib "src/lib";
use Gitolite::Test;

try "plan 1; cd $ENV{PWD}; git status -s -uno; !/./ or die" or die "dirty tree";
try "git log -1 --format='%h %ai %s'";
put "|cat >> prove.log", text();



