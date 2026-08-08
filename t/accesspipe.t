#!/bin/bash

# this needs to be run right after t/access.t because we're using the conf
# used in the last step of that test.

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
