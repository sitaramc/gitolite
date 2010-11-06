#!/bin/bash

# see some sample tests for how to use these functions; there is not
# documentation

testnum=0
subtests=0

# remote local command
runlocal() { "$@" > ~/1 2> ~/2; }
# remote run command
runremote() { ssh gitolite-test@localhost "$@" > ~/1 2> ~/2; }
# remote list repositories
listrepos() { ssh gitolite-test@localhost find repositories -type d -name "*.git" | sort > ~/1 2> ~/2; }
# remote cat compiled pm
catconf() { ssh gitolite-test@localhost cat .gitolite/conf/gitolite.conf-compiled.pm > ~/1 2> ~/2; }
# remote cat ~/.gitolite.rc
catrc() { ssh gitolite-test@localhost cat .gitolite.rc > ~/1 2> ~/2; }
# tail gitolite logfile
taillog() { ssh gitolite-test@localhost tail $1 .gitolite/logs/gitolite-????-??.log > ~/1 2> ~/2; }
hl() {  # highlight function
    normal=`tput sgr0`
    red=`tput sgr0; tput setaf 1; tput bold`
    if [[ -n $1 ]]
    then
        echo $red"$@"$normal
    else
        echo $red
        cat
        echo $normal
    fi
}
pause() { echo pausing, "$@"\; hit enter or ctrl-c...; read; }

capture() { cf=$1; shift; "$@" >& $TESTDIR/$cf; }

editrc() {
    scp gitolite-test@localhost:.gitolite.rc ~/junk >/dev/null
    perl -pi -e "print STDERR if not /^#/ and /$1\b/ and s/=.*/= $2;/" ~/junk
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

# flush result of last test when next one comes along
testdone() {
    [[ $subtests > 1 ]] && TESTNAME="($subtests) $TESTNAME"
    echo -e $testnum\\t$TESTNAME
}

# set test name/desc
name() {
    if [[ -n $TESTNAME ]]
    then
        if [[ $TESTNAME != INTERNAL ]]
        then
            (( testnum++ ))
            testdone
        fi
        subtests=0
    fi
    export TESTNAME="$*"
}

notok() {
    echo ----------
    head -999 ~/1 ~/2 | sed -e 's/^/    /'
}

expect_filesame() {
    if cmp ~/1 "$1"
    then
        (( subtests++ ))
    else
        echo files ~/1 and "$1" are different
        echo '*** ABORTING ***'
        exit 1
    fi
}

die() {
    echo '***** AAAAARRRGGH! *****'
    echo ${BASH_LINENO[1]} ${BASH_SOURCE[2]}
    read
    cd $TESTDIR
    vim +${BASH_LINENO[1]} '+r !head ~/1 ~/2 /dev/null' ${BASH_SOURCE[2]}
    exit 1
}

expect() {
    if cat ~/1 ~/2 | grep "$1" >/dev/null
    then
        (( subtests++ ))
    else
        notok
        echo ----------
        echo "    expecting: $1"
        echo ----------
        die $TESTNAME
        exit 1
    fi
}

notexpect() {
    if cat ~/1 ~/2 | grep "$1" >/dev/null
    then
        notok
        echo "NOT expecting: $1"
        echo ----------
        die $TESTNAME
        exit 1
    else
        (( subtests++ ))
    fi
}

print_summary() {
    echo -e "==========\n$testnum tests succeeded"
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
