#!/bin/bash

function die () {
    echo "$1" >&2
    exit 2
}

if test -z "$DONE_RESET_ENV"; then
    # First try to find data in the lims2 seq project structure
    test -n "$1" || die "Sequencing project must be specified"

    OUTPUT=`fetch_lims2_seq_reads.pl "$@"`

    if [[ $OUTPUT ]] ; then
        echo "${OUTPUT}"
        exit
    fi

    # If we got no output from fetch_lims2_seq_reads.pl reset env and try getting
    # project from the TraceServer as before
    exec env -i DONE_RESET_ENV=yes LSB_EXEC_CLUSTER=$LSB_EXEC_CLUSTER $0 "$@"
fi

test -f /software/badger/etc/profile.badger || die "TraceServer access not available on this system"
source /software/badger/etc/profile.badger

# The Oracle profile is in different places on 32- and 64-bit servers
if [[ $HOSTNAME =~ htgt2 ]] ; then
    source /software/oracle-ic-11.2/etc/profile.oracle
elif [[ $LSB_EXEC_CLUSTER =~ farm3 ]] ; then
    source /software/oracle-ic-11.2/etc/profile.oracle
elif test -f /software/oracle_instant_client_10_2/etc/profile.oracle; then
    source /software/oracle_instant_client_10_2/etc/profile.oracle
elif test -f /software/oracle_instant_client_10_2/profile.oracle; then
    source /software/oracle_instant_client_10_2/profile.oracle
else
    die "Oracle instant client not availale on this system"
fi

# We've already checked that we have a project name
TRACE_PROJECT="$1"; shift

if test "$1" = "--list-only"; then
    perl /software/badger/bin/indir "${TRACE_PROJECT}"
else
    perl /software/badger/bin/indir "${TRACE_PROJECT}" | /software/badger/bin/exp-piece -fofn - left right
fi
