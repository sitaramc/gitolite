#!/bin/bash

# what/why: re-establish gitolite admin access when admin key(s) lost
# where:    on server (NOT client!)

# pre-req:  shell access to the server (even with password is fine)
# pre-work:  -  make yourself a new keypair on your workstation
#            -  copy the pubkey and this script to the server

# usage:    $0 admin_name client_host_shortname pubkeyfile
# notes:     -  admin_name should already have RW or RW+ access to the
#               gitolite-admin repo
#            -  client_host_shortname is any simple word; see example below

# WARNING: ABSOLUTELY NO ARGUMENT CHECKING DONE
# WARNING: NEWER GITS ONLY ON SERVER SIDE (for now)

# example:  $0 sitaram laptop /tmp/sitaram.pub
# result:   a new keyfile named sitaram@laptop.pub would be added

# ENDHELP

[[ -z $1 ]] && { perl -pe "s(\\\$0)($0); last if /ENDHELP/" < $0; exit 1; }

set -e

cd
REPO_BASE=$(  perl -e 'do ".gitolite.rc"; print $REPO_BASE'  )
GL_ADMINDIR=$(perl -e 'do ".gitolite.rc"; print $GL_ADMINDIR')

cd; cd $GL_ADMINDIR/keydir; pwd
cp -v $3 $1@$2.pub

cd; cd $REPO_BASE/gitolite-admin.git; pwd
# XXX FIXME TODO -- fix this to work with older gits also
GIT_WORK_TREE=$GL_ADMINDIR git add keydir
GIT_WORK_TREE=$GL_ADMINDIR git commit -m "emergency add $1@$2.pub"

cd $GL_ADMINDIR
src/gl-compile-conf
