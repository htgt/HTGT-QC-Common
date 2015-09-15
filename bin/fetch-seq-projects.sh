#!/bin/bash

if test -z "$DONE_RESET_ENV"; then
    exec env -i DONE_RESET_ENV=yes $0 "$@"
fi
 
function die () {
    echo "$1" >&2
    exit 2
}

test -f /software/badger/etc/profile.badger || die "TraceServer access not available on this system"
source /software/badger/etc/profile.badger

# The Oracle profile is in different places on 32- and 64-bit servers
if test -f /software/oracle_instant_client_10_2/etc/profile.oracle; then
    source /software/oracle_instant_client_10_2/etc/profile.oracle
elif test -f /software/oracle_instant_client_10_2/profile.oracle; then
    source /software/oracle_instant_client_10_2/profile.oracle
else
    die "Oracle instant client 10.2 not availale on this system"
fi

test -n "$1" || die "Project search string must be specified"
SEARCH_STRING="$1"; shift

/software/bin/perl /opt/t87/global/software/perl/bin/htgt-pfind "${SEARCH_STRING}"

