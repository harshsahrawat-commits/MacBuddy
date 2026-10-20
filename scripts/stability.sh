#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if (( $# < 1 )); then
    print -u2 "Usage: ./scripts/stability.sh PID [SECONDS=28800]"
    exit 2
fi
mkdir -p tmp/validation
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
LOG_PREFIX="$PWD/tmp/validation/stability-$RUN_ID"
MEASURER="$PWD/tmp/validation/measure-$RUN_ID"
xcrun clang -O2 scripts/measure.c -o "$MEASURER"
print "$LOG_PREFIX"
print "RUNNING pid=$1 seconds=${2:-28800}" > "$LOG_PREFIX-status.txt"
trap 'RESULT=$?; if (( RESULT != 0 )); then print "FAILED: exit $RESULT; inspect resource/audit logs" > "$LOG_PREFIX-status.txt"; fi' EXIT
python3 scripts/audit-history.py > "$LOG_PREFIX-before.json"
if "$MEASURER" "$1" "${2:-28800}" > "$LOG_PREFIX-resources.log" 2>&1; then
    python3 scripts/audit-history.py > "$LOG_PREFIX-after.json"
    print "COMPLETE" > "$LOG_PREFIX-status.txt"
else
    print "FAILED: process exited or measurement failed" > "$LOG_PREFIX-status.txt"
    exit 1
fi
