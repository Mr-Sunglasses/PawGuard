#!/bin/bash

set -euo pipefail

MODE="${1:-}"
[ -n "$MODE" ] || MODE="--recent"
LAST="${PAWGUARD_LOG_LAST:-15m}"
PREDICATE='process == "PawGuard" OR subsystem BEGINSWITH "com.pawguard"'

case "$MODE" in
    --recent)
        exec /usr/bin/log show --style compact --last "$LAST" --predicate "$PREDICATE"
        ;;
    --follow)
        exec /usr/bin/log stream --style compact --level info --predicate "$PREDICATE"
        ;;
    -h|--help)
        printf 'Usage: ./scripts/logs.sh [--recent|--follow]\n'
        printf 'Set PAWGUARD_LOG_LAST to change the recent window (default: 15m).\n'
        ;;
    *)
        printf 'Unknown logs option: %s\n' "$MODE" >&2
        exit 1
        ;;
esac
