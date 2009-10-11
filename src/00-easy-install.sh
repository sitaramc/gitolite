#!/bin/bash

# easy install for gitolite

# this runs on the client side, and itself takes care of all the server side
# work.  You don't have to do anything on the server side directly

# run without any arguments for "usage" info

# important setting: bail on any errors (else we have to check every single
# command!)
set -e

die() { echo "$@"; echo "run $0 again without any arguments for help and tips"; exit 1; }
prompt() {
    echo
    echo
    echo ------------------------------------------------------------------------
    echo "$1"
    echo
    read -p '...press enter to continue or Ctrl-C to bail out'
}
usage() {
    cat <<EOFU
Usage: $0 user host admin_name
  - "user" is the username on the server where you will be installing gitolite
  - "host" is that server's hostname (or IP address is also fine)
  - "admin_name" is *your* name as you want it to appear in the eventual
    gitolite config file

Example usage: $0 git my.git.server sitaram

Output:
  - a proper gitolite admin repo in $HOME/gitolite-admin

Notes:
  - "user" and "admin_name" must be simple names -- no special characters etc
    please (only alphanumerics, dot, hyphen, underscore)
  - traditionally, the "user" is "git", but it can be anything you want
  - "admin_name" should be your name, for clarity, or whoever will be the
    gitolite admin

Pre-requisites:
  - you must run this from the gitolite working tree top level directory.
    This means you run this as "src/00-easy-install-clientside.sh"
  - you must already have pubkey based access to user@host.  If you currently
    only have password access, use "ssh-copy-id" or something.  Somehow get to
    the point where you can type "ssh user@host" and get a command line.  Run
    this program only after that is done

Errors:
  - if you get a "pubkey [...filename...] exists" error, it is either leftover
    from a previous, failed, run, or a genuine file you need.  Decide which it
    is, and remove it and retry, or use a different "admin_name", respectively.

EOFU
    exit 1;
}

[[ -z $1 ]] && usage
[[ -z $3 ]] && usage

[[ "$1" =~ [^a-zA-Z0-9._-] ]] && die "user '$1' invalid"
[[ "$3" =~ [^a-zA-Z0-9._-] ]] && die "admin_name '$3' invalid"

user=$1
host=$2
admin_name=$3

# ----------------------------------------------------------------------
# basic sanity checks
# ----------------------------------------------------------------------

# are we in the right directory?  We should have all the gitolite sources
# here...
ls src/gl-auth-command  \
    src/gl-compile-conf \
    src/install.pl  \
    src/update-hook.pl  \
    conf/example.conf   \
    conf/example.gitolite.rc    >/dev/null ||
    die "cant find at least some files in gitolite sources/config; aborting"

# do we have pubkey auth on the server
ssh -o PasswordAuthentication=no $user@$host pwd >/dev/null ||
    die "pubkey access didn't work; please set it up using 'ssh-copy-id' or something"

# can the "gitolite-admin" repo be safely created in $HOME
[[ -d $HOME/gitolite-admin ]] &&
    die "please delete or move aside the \$HOME/gitolite-admin directory"

# cool; now let's create a new key for you as a "gitolite user" (as opposed to
# a gitolite admin who needs to login to the server and get a command line)

[[ -f $HOME/.ssh/$admin_name.pub ]] && die "pubkey $HOME/.ssh/$admin_name.pub exists; can't proceed"
prompt "the next command will create a new keypair for your gitolite access

    The pubkey will be $HOME/.ssh/$admin_name.pub.  You will have to
    choose a passphrase or hit enter for none.  I recommend not having a
    passphrase for now, and adding one with 'ssh-keygen -p' *as soon as*
    all the setup is done and you've successfully cloned and pushed the
    gitolite-admin repo.

    After that, I suggest you (1) install 'keychain' or something
    similar, and (2) add the following command to your bashrc (since
    this is a non-default key)

        ssh-add \$HOME/.ssh/$admin_name

    This makes using passphrases very convenient."

ssh-keygen -t rsa -f $HOME/.ssh/$admin_name || die "ssh-keygen failed for some reason..."

if [[ -n $SSH_AGENT_PID ]]
then
    prompt "you're running ssh-agent.  We'll try and do an ssh-add of the
    private key we just created, otherwise this key won't get picked up.  If
    you specified a passphrase in the previous step, you'll get asked for one
    now -- type in the same one."

    ssh-add $HOME/.ssh/$admin_name
fi

# ok the gitolite key is done; create a stanza for it in ~/.ssh/config
echo "
host gitolite
     hostname $host
     user $user
     identityfile ~/.ssh/$admin_name" > $HOME/.ssh/.gl-stanza

if grep 'host  *gitolite' $HOME/.ssh/config &>/dev/null
then
    prompt "your \$HOME/.ssh/config already has settings for gitolite.  I will
    assume they're correct, but if they're not, please edit that file, delete
    that paragraph (that line and the following few lines), and rerun.

    In case you want to check right now (from another terminal) if they're
    correct, here's what they are *supposed* to look like:
$(cat ~/.ssh/.gl-stanza)"

else
    prompt "creating settings for your gitolite access in $HOME/.ssh/config;
    these are the lines that will be appended to your ~/.ssh/config:
$(cat ~/.ssh/.gl-stanza)"

    cat $HOME/.ssh/.gl-stanza >> $HOME/.ssh/config
    # if the file didn't exist at all, it might have the wrong permissions
    chmod 644 $HOME/.ssh/config
fi
rm  $HOME/.ssh/.gl-stanza

# ----------------------------------------------------------------------
# client side stuff almost done; server side now
# ----------------------------------------------------------------------

# setup the gitolite sources and conf on the server
ssh $user@$host mkdir -p gitolite-install
rsync -a src conf doc $user@$host:gitolite-install/

# give the user an opportunity to change the rc
cp conf/example.gitolite.rc .gitolite.rc
    # hey here it means "release candidate" ;-)

prompt "the gitolite rc file needs to be edited by hand.  The defaults
are sensible, so if you wish, you can just exit the editor.

Otherwise, make any changes you wish and save it.  Read the comments to
understand what is what -- the rc file's documentation is inline.

Please remember this file will actually be copied to the server, and
that all the paths etc. represent paths on the server!"

${VISUAL:-${EDITOR:-vi}} .gitolite.rc

# copy the rc across
scp .gitolite.rc $user@$host:

prompt "ignore any 'please edit this file' or 'run this command' type
lines in the next set of command outputs coming up.  They're only
relevant for a manual install, not this one..."

# extract the GL_ADMINDIR and REPO_BASE locations
GL_ADMINDIR=$(ssh $user@$host "perl -e 'do \".gitolite.rc\"; print \$GL_ADMINDIR'")
REPO_BASE=$(  ssh $user@$host "perl -e 'do \".gitolite.rc\"; print \$REPO_BASE'")

# run the install script on the server
ssh $user@$host "cd gitolite-install; src/install.pl"

# setup the initial config file
echo "#gitolite conf
#please see conf/example.conf for details on syntax and features

repo gitolite-admin
    RW+                 = $admin_name

repo testing
    RW+                 = @all

" > gitolite.conf

# send the config and the key to the remote
scp gitolite.conf $user@$host:$GL_ADMINDIR/conf/

scp $HOME/.ssh/$admin_name.pub $user@$host:$GL_ADMINDIR/keydir

# run the compile script on the server
ssh $user@$host "cd $GL_ADMINDIR; src/gl-compile-conf"

# ----------------------------------------------------------------------
# hey lets go the whole hog on this; setup push-to-admin!
# ----------------------------------------------------------------------

# setup the initial commit for the admin repo
echo "cd $REPO_BASE/gitolite-admin.git
GIT_WORK_TREE=$GL_ADMINDIR git add conf/gitolite.conf keydir
GIT_WORK_TREE=$GL_ADMINDIR git commit -am start
" | ssh $user@$host

ssh $user@$host "cd gitolite-install; src/install.pl"

prompt "now we will clone the gitolite-admin repo to your workstation
and see if it all hangs together.  We'll do this in your \$HOME for now,
and you can move it elsewhere later if you wish to."

cd $HOME
git clone gitolite:gitolite-admin.git

echo
echo
echo ------------------------------------------------------------------------
echo "Cool -- we're done.  Now you can edit the config file (currently
in ~/gitolite-admin/conf/gitolite.conf) to add more repos, users, etc.
When done, 'git add' the changed files, 'git commit' and 'git push'.

Read the comments in conf/example.conf for information about the config
file format -- like the rc file, this also has inline documentation.

Your URL for cloning any repo on this server will be

    gitolite:reponame.git

However, any other users you set up will have to use

    $user@$host:reponame.git

unless they also create similar settings in their '.ssh/config' file."
