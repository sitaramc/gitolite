#!/bin/bash

# tool to make adding/editing products easier
# see subconf-example.mkd or html version somewhere

# PRE-REQUISITES
#   1.  gitolite installed on all servers
#   2.  the gitolite-admin repo is also mirrored

# run this program ONLY in a clone of a gitolite-admin repo in a committed
# state.  This way a "git diff" will tell you what changed, and a "git status"
# will tell you what new files were created, and you can rollback if needed.

usage() {
    cd $od
    echo commands:
    grep '^#.*$0' $0 | cut -c7-
    echo
    echo '(please read the inline documentation for more info)'
}

# ------------------------------------------------------------------------------

# COMMANDS

# ------------------------------------------------------------------------------
# adding a new host:

#   $0  newhost hostname admin-username

# NOTE: this requires you to first add the newhost to the gitolite.conf file
# in the list of slaves for the admin repo.  That is manually done; this
# script will not do it.  You will also have to ensure that the new server
# being added has been updated and is receiving changes to the admin repo
# automatically.

# DO NOT PROCEED OTHERWISE.  If necessary, check by making a dummy change to
# the admin repo and pushing, then make sure the new server has received the
# change.

# ------------------------------------------------------------------------------
# adding a new product to a master host:

#   $0  newprod hostname product-name

# NOTE: the host admin must first create and propagate the
# master/host/prod.conf file (see section 3, "host admins only").

# ------------------------------------------------------------------------------
# adding a new slave to a master/prod combo

#   $0  newslave master-hostname product-name slave-hostname

# ------------------------------------------------------------------------------

# new *server*: edit gitolite.conf manually (slaves list for the admin repo)

# everything else is done by this tool

# ASSUMPTIONS: we are in a gitolite-admin clone somewhere

die() { echo "$@" >&2; usage; exit 1; }
finish() { echo >&2; exit 0; }

# go to the conf directory
od=$PWD; export od
git rev-parse --show-toplevel >/dev/null || die not in a git directory?
cd $(git rev-parse --show-toplevel)
cd conf || die cant find a conf/ subdirectory
[ -f gitolite.conf ] || die cant find a gitolite.conf file

verify_host() {
    grep config.*gitolite.mirror gitolite.conf |
        perl -pe 's/"/ " /g' |
        grep " $2 " >/dev/null || die "$2 not found in gitolite.conf mirror config"
}

update_file() {
    echo >&2
    echo >&2 ==== appending lines to $1 ====
    tee -a $1
}

# ------------------------------------------------------------------------------
# adding a new host:
#   newhost hostname admin-username

[ "$1" == "newhost" ] && {
    [ -z "$2" ] && die "need hostname"
    verify_host master $2
    [ -f master/$2.conf ] && die "master/$2.conf already exists"
    [ -z "$3" ] && die "need admin username for host $2"

    (
        echo
        printf "@$2\t=   $2/..*\n"                  | expand -32
    ) | update_file host-product-map.conf

    # setup the first line of the NAME-restrictions.conf file
    [ -f NAME-restrictions.conf ] || echo "repo gitolite-admin" > NAME-restrictions.conf
    (
        echo
        printf "RW\t=   $3\n"                       | expand -40
        printf "RW  NAME/conf/master/$2/\t=   $3\n" | expand -40
    ) | update_file NAME-restrictions.conf

    mkdir -p master
    (
        echo
        echo "include \"master/$2/*.conf\""
    ) | update_file master/$2.conf

    finish
}

# ------------------------------------------------------------------------------
# adding a new product to a master host:
#   newprod hostname product-name

[ "$1" == "newprod" ] && {
    [ -z "$2" ] && die "need hostname"
    verify_host master $2
    [ -f master/$2.conf ] || die "host $2 not found; forgot to run 'newhost'?"
    [ -z "$3" ] && die "need product name to add"
    [ -f master/$2/$3.conf ] || die "master/$2/$3.conf not found; contact host-admin for $2"
    [ -f mirrors/$2/$3.conf ] && die "mirrors/$2/$3.conf already exists"

    (
        echo
        printf "@$2\t=   $3/..*\n"                  | expand -32
    ) | update_file host-product-map.conf

    finish
}

# ------------------------------------------------------------------------------
# adding a new slave to a master/prod combo
#   newslave master-hostname product-name slave-hostname

[ "$1" == "newslave" ] && {
    [ -z "$2" ] && die "need hostname"
    verify_host master $2
    [ -f master/$2.conf ] || die "host $2 not found; forgot to run 'newhost'?"
    [ -z "$3" ] && die "need product name to add"
    [ -f master/$2/$3.conf ] || die "master/$2/$3.conf not found; contact host-admin for $2"
    [ -z "$4" ] && die "need slave name to add"
    verify_host slave $4

    # first create lines in slave/slavename/mastername.conf
    f="slave/$4/$2.conf"
    i="$2/$3.conf"
    [ -f $f ] && grep "$i" "$f" >/dev/null && die "$f already contains lines for $i"

    mkdir -p slave/$4
    (
        echo
        echo "include \"master/$i\""
        echo "include \"mirrors/$i\""
    ) | update_file "$f"

    # now check how many slaves we have for this and overwrite mirrors/$2/$3.conf
    sl=$(echo slave/*/$2.conf | perl -pe "chomp; s(slave/(.*?)/$2.conf)(\$1)g")
    f="mirrors/$2/$3.conf"

    [ -f $f ] && {
        echo >&2
        echo >&2 "==== overwriting file $f; old contents:"
        cat  >&2 $f
        > $f
    }

    mkdir -p mirrors/$2
    (
        echo "repo $3/..*"
        echo "    config gitolite.mirror.master = \"$2\""
        echo "    config gitolite.mirror.slaves = \"$sl\""
    ) | update_file $f

    finish
}

usage
