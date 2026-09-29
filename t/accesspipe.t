#!/bin/bash

# This needs to be run right after t/accesspipe-prep.t because that sets up
# the conf for the test.  (Accesspipe is in a somewhat unique position that
# you *can't* test it step by step, like all the other tests do.  It is
# *meant* to be a batch process.  So the structure of this test is very
# different from all the other ones we have, hence the separation of the conf
# preparation).

# ----------------------------------------------------------------------
# setup the reference output

# ----------------------------------------------------------------------
# print plan

echo 1..76

# ----------------------------------------------------------------------
# run the test

count=0

pipein() {
    cat $1 | while read i; do
        [[ -n "$i" ]] || continue
        echo "$i"
        sleep 0.05
    done | gitolite access % % % $2 | while read o; do
        echo "$o"
    done | while read result; do
        (( count += 1 ))
        ref=$(sed -ne $count"p" < t/accesspipe.ref)
        if test "$result" = "$ref"; then
            echo "ok ($count)"
        else
            echo "not ok ($count)"
            # echo "expected: $ref" >&2
            # echo "  actual: $result" >&2
            # echo >&2
        fi
    done
}

# the 4-arguments-per-line-of-STDIN mode first
pipein t/accesspipe.in1 %

# the updated counter is deep inside a loop, and we want both the "in1" and
# "in2" to look like one seamless input.
count=38

# now the 3-arguments-per-line mode
pipein t/accesspipe.in2 any
