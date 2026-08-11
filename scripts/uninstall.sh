#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REMOVE_ALL=false
RESET_PERMISSION=false
ASSUME_YES=false

usage() {
    printf '%s\n' \
        "Usage: ./scripts/uninstall.sh [--all] [--reset-permission] [--yes]" \
        "" \
        "Default: move the installed app to Trash and preserve profiles/data." \
        "  --all               Also remove preferences and local cat photos" \
        "  --reset-permission  Reset PawGuard's Accessibility permission" \
        "  --yes               Skip the destructive-data confirmation"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all) REMOVE_ALL=true; RESET_PERMISSION=true ;;
        --reset-permission) RESET_PERMISSION=true ;;
        --yes) ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;;
        *) pawguard_die "Unknown uninstall option: $1" ;;
    esac
    shift
done

TARGET_APP="$PAWGUARD_INSTALL_DIR/$PAWGUARD_APP_NAME.app"
pawguard_assert_safe_app_target "$TARGET_APP"

if [ "$REMOVE_ALL" = true ] && [ "$ASSUME_YES" != true ]; then
    printf 'This will remove PawGuard preferences and local cat photos. Continue? [y/N] '
    read -r confirmation
    case "$confirmation" in
        y|Y|yes|YES) ;;
        *) printf 'Uninstall cancelled.\n'; exit 0 ;;
    esac
fi

pawguard_stop_running_app
mkdir -p "$HOME/.Trash"
TRASH_STAMP="$(date +%Y%m%d-%H%M%S)-$$"

if [ -d "$TARGET_APP" ]; then
    TRASH_APP="$HOME/.Trash/PawGuard-$TRASH_STAMP.app"
    pawguard_info "Moving the installed app to Trash"
    mv "$TARGET_APP" "$TRASH_APP"
    pawguard_success "Moved to $TRASH_APP"
else
    pawguard_info "No installed app found at $TARGET_APP"
fi

if [ "$REMOVE_ALL" = true ]; then
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
    pawguard_success "Removed PawGuard preferences"
fi

if [ "$RESET_PERMISSION" = true ]; then
    tccutil reset Accessibility "$PAWGUARD_BUNDLE_ID"
    pawguard_success "Reset PawGuard Accessibility permission"
fi

printf '\nUninstall complete. Build artifacts were preserved.\n'
printf 'Run make clean separately if you also want to remove build output.\n'
