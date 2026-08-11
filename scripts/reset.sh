#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

MODE="${1:-}"
ASSUME_YES=false
[ "${2:-}" != "--yes" ] || ASSUME_YES=true

usage() {
    printf '%s\n' \
        "Usage: ./scripts/reset.sh <onboarding|permission|data|all> [--yes]" \
        "" \
        "  onboarding  Reset onboarding and app settings; keep cat profiles/photos" \
        "  permission  Reset only Accessibility permission" \
        "  data        Reset preferences, profiles, statistics, and local photos" \
        "  all         Reset data and Accessibility permission"
}

case "$MODE" in
    onboarding|permission|data|all) ;;
    -h|--help|"") usage; exit 0 ;;
    *) pawguard_die "Unknown reset mode: $MODE" ;;
esac

if { [ "$MODE" = "data" ] || [ "$MODE" = "all" ]; } && [ "$ASSUME_YES" != true ]; then
    printf 'This will remove PawGuard profiles, statistics, settings, and local cat photos. Continue? [y/N] '
    read -r confirmation
    case "$confirmation" in
        y|Y|yes|YES) ;;
        *) printf 'Reset cancelled.\n'; exit 0 ;;
    esac
fi

pawguard_stop_running_app

if [ "$MODE" = "onboarding" ]; then
    defaults delete "$PAWGUARD_BUNDLE_ID" pawguard.settings >/dev/null 2>&1 || true
    pawguard_success "Reset onboarding and app settings; cat profiles were preserved"
    exit 0
fi

if [ "$MODE" = "permission" ] || [ "$MODE" = "all" ]; then
    tccutil reset Accessibility "$PAWGUARD_BUNDLE_ID"
    pawguard_success "Reset PawGuard Accessibility permission"
fi

if [ "$MODE" = "data" ] || [ "$MODE" = "all" ]; then
    mkdir -p "$HOME/.Trash"
    TRASH_STAMP="$(date +%Y%m%d-%H%M%S)-$$"
    APP_SUPPORT="$HOME/Library/Application Support/PawGuard"
    APP_CACHE="$HOME/Library/Caches/$PAWGUARD_BUNDLE_ID"

    if [ -d "$APP_SUPPORT" ]; then
        mv "$APP_SUPPORT" "$HOME/.Trash/PawGuard-data-$TRASH_STAMP"
        pawguard_success "Moved local profiles and photos to Trash"
    fi
    if [ -d "$APP_CACHE" ]; then
        mv "$APP_CACHE" "$HOME/.Trash/PawGuard-cache-$TRASH_STAMP"
    fi
    defaults delete "$PAWGUARD_BUNDLE_ID" >/dev/null 2>&1 || true
    pawguard_success "Reset PawGuard preferences and statistics"
fi

printf 'Launch PawGuard again with make run or make install.\n'
