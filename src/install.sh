#!/bin/bash

# install gitolite

# quick safety check: do not run if ~/.gitolite.rc is present

[[ -f ~/.gitolite.rc ]] && {
    echo sorry\; \'~/.gitolite.rc\' already exists
    exit 1
}

# this one is fixed to the location shown
cp conf/example.gitolite.rc ~/.gitolite.rc

# the destinations below are defaults; if you change the paths in the "rc"
# file above, these destinations also must change accordingly

# mkdir $REPO_BASE, $GL_ADMINDIR, it's subdirs, and $GL_KEYDIR
mkdir                       ~/repositories
mkdir                       ~/.gitolite
mkdir                       ~/.gitolite/{src,conf,doc,keydir}

# copy conf, src, doc
cp -a src doc conf          ~/.gitolite
cp conf/example.conf        ~/.gitolite/conf/gitolite.conf
