#!/bin/bash

set -e
hosts="frodo sam gollum"
mainhost=frodo

# setup software
bd=`gitolite query-rc -n GL_BINDIR`
mkdir -p /tmp/g3
rm -rf /tmp/g3/src
cp -a $bd /tmp/g3/src
chmod -R go+rX /tmp/g3

# setup symlinks in frodo, sam, and gollum's accounts
for h in $hosts
do
    sudo -u $h -i bash -c "rm -rf *.pub bin .ssh projects.list repositories .gitolite .gitolite.rc"
done

[ "$1" = "clear" ] && exit

cd /tmp/g3
[ -d keys ] || {
    mkdir keys
    cd keys
    for h in $hosts
    do
        ssh-keygen -N '' -q -f server-$h  -C $h
        chmod go+r /tmp/g3/keys/server-$h
    done
    cp $bd/../t/mirror-test-ssh-config ssh-config
}
chmod -R go+rX /tmp/g3

for h in $hosts
do
    sudo -u $h -i bash -c "mkdir -p bin; ln -sf /tmp/g3/src/gitolite bin; mkdir -p .ssh; chmod 0700 .ssh"

    sudo -u $h -i cp /tmp/g3/keys/ssh-config    .ssh/config
    sudo -u $h -i cp /tmp/g3/keys/server-$h     .ssh/id_rsa
    sudo -u $h -i cp /tmp/g3/keys/server-$h.pub .ssh/id_rsa.pub
    sudo -u $h -i chmod go-rwx                  .ssh/id_rsa .ssh/config

done

# add all pubkeys to all servers
for h in $hosts
do
    sudo -u $h -i gitolite setup -a admin
    for j in $hosts
    do
        sudo -u $h -i gitolite setup -pk /tmp/g3/keys/server-$j.pub
        echo sudo _u $j _i ssh $h@localhost info
        sudo -u $j -i ssh -o StrictHostKeyChecking=no $h@localhost info
    done
    echo ----
done

# now copy our admin key to the main host
cd;cd .ssh
cp admin id_rsa; cp admin.pub id_rsa.pub
cp admin.pub /tmp/g3/keys; chmod go+r /tmp/g3/keys/admin.pub
sudo -u $mainhost -i gitolite setup -pk /tmp/g3/keys/admin.pub
ssh $mainhost@localhost info

lines="
repo gitolite-admin
    option mirror.master = frodo
    option mirror.copies-1 = sam gollum
    option mirror.redirectOK = sam

repo r1
    RW+     =   u1
    RW      =   u2
    R       =   u3
    option mirror.master = sam
    option mirror.copies-1 = frodo

repo r2
    RW+     =   u2
    RW      =   u3
    R       =   u4
    option mirror.master = sam
    option mirror.copies-1 = frodo gollum
    option mirror.redirectOK = all

include \"%HOSTNAME.conf\"
"

lines2="
repo l-%HOSTNAME
RW  =   u1
"

# for each server, set the HOSTNAME to the rc, add the mirror options to the
# conf file, and compile
for h in $hosts
do
    cat $bd/../t/mirror-test-rc | perl -pe "s/%HOSTNAME/$h/" > /tmp/g3/temp
    chmod go+rX /tmp/g3/temp
    sudo -u $h -i cp /tmp/g3/temp .gitolite.rc
    echo "$lines"  | sudo -u $h -i sh -c 'cat >> .gitolite/conf/gitolite.conf'
    echo "$lines2" | sudo -u $h -i sh -c "cat >> .gitolite/conf/$h.conf"
    sudo -u $h -i gitolite setup
done

# goes on frodo
lines="
# local to frodo but sam thinks frodo is a copy
repo lfrodo
RW  =   u1

# both think they're master
repo mboth
RW  =   u1
option mirror.master = frodo
option mirror.copies = sam

# frodo thinks someone else is the master but sam thinks he is
repo mnotsam
RW  =   u1
option mirror.master = merry
option mirror.copies = frodo

# local to frodo but sam thinks frodo is a master and redirect is OK
repo lfrodo2
RW  =   u1

# non-native to frodo but sam thinks frodo is master
repo nnfrodo
RW  =   u1
option mirror.master = gollum
option mirror.copies = frodo
option mirror.redirectOK = all

# sam is not a valid copy to send stuff to frodo
repo nvsfrodo
RW  =   u1
option mirror.master = frodo
option mirror.copies = gollum
option mirror.redirectOK = all
"

echo "$lines" | sudo -u frodo -i sh -c "cat >> .gitolite/conf/frodo.conf"

# goes on sam
lines="
# local to frodo but sam thinks frodo is a copy
repo lfrodo
RW  =   u1
option mirror.master = sam
option mirror.copies = frodo

# both think they're master
repo mboth
RW  =   u1
option mirror.master = sam
option mirror.copies = frodo

# frodo thinks someone else is the master but sam thinks he is
repo mnotsam
RW  =   u1
option mirror.master = sam
option mirror.copies = frodo

# local to frodo but sam thinks frodo is a master and redirect is OK
repo lfrodo2
RW  =   u1
option mirror.master = frodo
option mirror.copies = sam
option mirror.redirectOK = all

# non-native to frodo but sam thinks frodo is master
repo nnfrodo
RW  =   u1
option mirror.master = frodo
option mirror.copies = sam
option mirror.redirectOK = all

# sam is not a valid copy to send stuff to frodo
repo nvsfrodo
RW  =   u1
option mirror.master = frodo
option mirror.copies = sam
option mirror.redirectOK = all
"

echo "$lines" | sudo -u sam -i sh -c "cat >> .gitolite/conf/sam.conf"

for h in $hosts
do
    sudo -u $h -i gitolite setup
done

# that ends the setup phase
echo ======================================================================
