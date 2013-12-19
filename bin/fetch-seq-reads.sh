#!/bin/bash

if test -z "$DONE_RESET_ENV"; then
    exec env -i DONE_RESET_ENV=yes LSB_EXEC_CLUSTER=$LSB_EXEC_CLUSTER $0 "$@"
fi
 
function die () {
    echo "$1" >&2
    exit 2
}

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

test -n "$1" || die "TraceServer project must be specified"
TRACE_PROJECT="$1"; shift

if test "$1" = "--list-only"; then
    perl /software/badger/bin/indir "${TRACE_PROJECT}"
else
    perl /software/badger/bin/indir "${TRACE_PROJECT}" | /software/badger/bin/exp-piece -fofn - left right
fi
