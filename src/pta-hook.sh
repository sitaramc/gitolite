#!/bin/sh

# get this from your .gitolite.conf; and don't forget this is shell, while
# that is perl :-)
export GL_ADMINDIR=/home/git/.gitolite

# checkout the master branch to $GL_ADMINDIR
GIT_WORK_TREE=$GL_ADMINDIR git checkout -f master

# collect all the delegated fragments
mkdir -p $GL_ADMINDIR/conf/fragments
for br in $(git for-each-ref --format='%(refname:short)')
do
    # skip master (duh!)
    [[ $br == master ]] && continue
    # all other branches *should* contain a file called <branchname>.conf
    # inside conf/fragments; if so copy it
    if git show $br:conf/fragments/$br.conf > /dev/null 2>&1
    then
        git show $br:conf/fragments/$br.conf > $GL_ADMINDIR/conf/fragments/$br.conf
        echo "(extracted $br conf; `wc -l < $GL_ADMINDIR/conf/fragments/$br.conf` lines)"
    else
        echo "                ***** ERROR *****"
        echo "        branch $br does not contain conf/fragments/$br.conf"
    fi
done

cd $GL_ADMINDIR
src/gl-compile-conf
