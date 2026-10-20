#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if (( $# < 1 )); then
    print -u2 "Usage: ./scripts/measure.sh PID [SECONDS=1800] [--observed-duration]"
    print -u2 "Close the dashboard and collapse the strip first. Obtain PID with: pgrep -x MacBuddy"
    exit 2
fi
mkdir -p tmp
MEASURER="$PWD/tmp/measure-$$"
trap 'rm -f "$MEASURER"' EXIT
xcrun clang -O2 scripts/measure.c -o "$MEASURER"
if (( $# >= 3 )); then
    "$MEASURER" "$1" "${2:-1800}" "$3"
else
    "$MEASURER" "$1" "${2:-1800}"
fi
