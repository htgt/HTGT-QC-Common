#!/bin/bash
#
# $HeadURL: svn+ssh://svn.internal.sanger.ac.uk/repos/svn/htgt/projects/HTGT-QC/trunk/bin/fetch-seq-reads.sh $
# $LastChangedRevision: 6219 $
# $LastChangedDate: 2011-10-17 14:58:55 +0100 (Mon, 17 Oct 2011) $
# $LastChangedBy: rm7 $
#

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

test -n "$1" || die "TraceServer project must be specified"
TRACE_PROJECT="$1"; shift

if test "$1" = "--list-only"; then
    /software/bin/perl /software/badger/bin/indir "${TRACE_PROJECT}"
else
    /software/bin/perl /software/badger/bin/indir "${TRACE_PROJECT}" | /software/badger/bin/exp-piece -fofn - left right
fi
