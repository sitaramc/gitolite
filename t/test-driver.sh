#!/bin/bash

# are we in the right place
cd ${0%/*}
git rev-parse --show-toplevel || die should run t/test-driver.sh from a clone of gitolite
export TESTDIR=$PWD

# see some sample tests for how to use these functions; there is no
# documentation

# REPO_BASE has 2 manifestations in the output of various commands
export TEST_BASE=$(gl-query-rc REPO_BASE)
[ -z "$TEST_BASE" ] && { echo TEST_BASE not set >&2; exit 1; }
TEST_BASE_FULL=$TEST_BASE
[ "$TEST_BASE" = "repositories" ] && TEST_BASE_FULL=/home/gitolite-test/repositories

testnum=0

# remote local command
runlocal() { "$@" > ~/1 2> ~/2; }
# remote run command
runremote() { ssh gitolite-test@localhost "$@" > ~/1 2> ~/2; }
# remote list repositories
listrepos() { ssh gitolite-test@localhost "cd $TEST_BASE; find . -type d -name '*.git'" | sort > ~/1 2> ~/2; }
# remote cat compiled pm
catconf() { ssh gitolite-test@localhost cat .gitolite/conf/gitolite.conf-compiled.pm > ~/1 2> ~/2; }
catconfs() {
    (
        ssh gitolite-test@localhost cat .gitolite/conf/gitolite.conf-compiled.pm
        ssh gitolite-test@localhost "cd $TEST_BASE; find . -name gl-conf | sort"
        ssh gitolite-test@localhost "cd $TEST_BASE; find . -name gl-conf | sort | xargs cat"
    ) > ~/1 2> ~/2
}
# remote cat ~/.gitolite.rc
catrc() { ssh gitolite-test@localhost cat .gitolite.rc > ~/1 2> ~/2; }
# tail gitolite logfile
taillog() { ssh gitolite-test@localhost tail $1 .gitolite/logs/gitolite-????-??.log > ~/1 2> ~/2; }
hl() {  # highlight function
    normal=`tput sgr0`
    red=`tput sgr0; tput setaf 1; tput bold`
    echo >&2
    if [[ -n $1 ]]
    then
        echo $red"$@"$normal >&2
    else
        echo $red >&2
        cat
        echo $normal >&2
    fi
}

capture() { cf=$1; shift; "$@" >& $TESTDIR/$cf; }

editrc() {
    scp gitolite-test@localhost:.gitolite.rc ~/junk >/dev/null
    perl -pi -e "print STDERR if not /^#/ and /$1\b/ and s/=.*/= $2;/" ~/junk 2> >(sed -e 's/^/# /')
    scp ~/junk gitolite-test@localhost:.gitolite.rc >/dev/null
}

addrc() {
    ssh gitolite-test@localhost cat .gitolite.rc < /dev/null > ~/junk
    tee -a ~/junk
    echo '1;' >> ~/junk
    scp ~/junk gitolite-test@localhost:.gitolite.rc >/dev/null
}

ugc ()
{
    (
        cd ~/gitolite-admin;
        [[ $1 == -r ]] && {
            shift
            cat $TESTDIR/basic.conf > conf/gitolite.conf
        }
        cat     >> conf/gitolite.conf
        git add conf keydir;
        git commit --allow-empty -m "$TESTNAME";
        git push ${1:-gitolite}:gitolite-admin master
        git fetch origin >/dev/null 2>&1
    ) >~/1 2>~/2
    grep DBG: ~/2 >/dev/null && grep . ~/1 ~/2
}

mdc()
{
    (
        echo $RANDOM > ${1:-$RANDOM}
        git add .
        git commit -m "$TESTNAME"
    ) >~/1 2>~/2
}

# set test name/desc
name() {
    export TESTNAME="$*"
    if [[ $TESTNAME != INTERNAL ]]
    then
        echo '#' "$*"
    fi
}

ok() {
    (( testnum++ ))
    echo 'ok' "($testnum) $*"
}


notok() {
    (( testnum++ ))
    echo 'not ok' "($testnum) $*"
}

expect_filesame() {
    if cmp ~/1 "$1"
    then
        ok
    else
        notok files ~/1 and "$1" are different
    fi
}

die() {
    echo '***** AAAAARRRGGH! *****' >&2
    echo ${BASH_LINENO[1]} ${BASH_SOURCE[2]} >&2
    echo "vim +${BASH_LINENO[1]} \'+r !head ~/1 ~/2 /dev/null\' ${BASH_SOURCE[2]}" >&2
    exit 1
}

expect() {
    if cat ~/1 ~/2 | grep "$1" >/dev/null
    then
        ok
    else
        notok "expecting: $1, got:"
        cat ~/1 ~/2|sed -e 's/^/# /'
    fi
}

notexpect() {
    if cat ~/1 ~/2 | grep "$1" >/dev/null
    then
        notok "NOT expecting: $1, got:"
        cat ~/1 ~/2|sed -e 's/^/# /'
    else
        ok
    fi
}

print_summary() {
    echo 1..$testnum
}

expect_push_ok() {
    expect "$1"
    notexpect "DENIED"
    notexpect "failed to push"
}

export TESTDIR=$PWD
arg1=$1; shift
for testfile in ${arg1:-t??-}*
do
    hl $testfile
    . $testfile "$@" || die "$testfile failed"
    cd $TESTDIR
done

print_summary
