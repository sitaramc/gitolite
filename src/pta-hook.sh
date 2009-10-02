#!/bin/sh

GIT_WORK_TREE=/home/git/.gitolite git checkout -f

cd /home/git/.gitolite
src/gl-compile-conf
