#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CONFIGURATION="Release"
OPEN_AFTER_INSTALL=true

usage() {
    printf '%s\n' \
        "Usage: ./scripts/install.sh [--debug] [--no-open]" \
        "" \
        "Build, sign, and install PawGuard to PAWGUARD_INSTALL_DIR." \
        "The default install directory is /Applications."
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --debug) CONFIGURATION="Debug" ;;
        --no-open) OPEN_AFTER_INSTALL=false ;;
        -h|--help) usage; exit 0 ;;
        *) pawguard_die "Unknown install option: $1" ;;
    esac
    shift
done

pawguard_assert_project_root
pawguard_stop_running_app

if [ "$CONFIGURATION" = "Debug" ]; then
    "$SCRIPT_DIR/build.sh" --debug --signed
else
    "$SCRIPT_DIR/build.sh" --release --signed
fi

SOURCE_APP="$(pawguard_app_path "$CONFIGURATION" signed)"
TARGET_APP="$PAWGUARD_INSTALL_DIR/$PAWGUARD_APP_NAME.app"
STAGED_APP="$PAWGUARD_INSTALL_DIR/.PawGuard.installing.$$.app"
BACKUP_APP="$PAWGUARD_INSTALL_DIR/.PawGuard.previous.$$.app"
INSTALL_COMMITTED=false

pawguard_assert_safe_app_target "$TARGET_APP"

if [ ! -d "$PAWGUARD_INSTALL_DIR" ]; then
    mkdir -p "$PAWGUARD_INSTALL_DIR" \
        || pawguard_die "Could not create $PAWGUARD_INSTALL_DIR"
fi
[ -w "$PAWGUARD_INSTALL_DIR" ] \
    || pawguard_die "$PAWGUARD_INSTALL_DIR is not writable. Set PAWGUARD_INSTALL_DIR to another Applications directory."

cleanup_install() {
    [ ! -d "$STAGED_APP" ] || rm -rf "$STAGED_APP"
    if [ "$INSTALL_COMMITTED" != true ] && [ -d "$BACKUP_APP" ] && [ ! -d "$TARGET_APP" ]; then
        pawguard_warning "Install was interrupted; restoring the previous app"
        mv "$BACKUP_APP" "$TARGET_APP" || pawguard_warning "Could not restore $BACKUP_APP automatically"
    fi
}
trap cleanup_install EXIT

pawguard_info "Staging the signed app in $PAWGUARD_INSTALL_DIR"
ditto "$SOURCE_APP" "$STAGED_APP"
pawguard_verify_app "$STAGED_APP" \
    || pawguard_die "Staged app failed signature or bundle-identifier verification"

if [ -d "$TARGET_APP" ]; then
    pawguard_info "Replacing the existing installation"
    mv "$TARGET_APP" "$BACKUP_APP"
fi

if ! mv "$STAGED_APP" "$TARGET_APP"; then
    [ ! -d "$BACKUP_APP" ] || mv "$BACKUP_APP" "$TARGET_APP"
    pawguard_die "Could not install $TARGET_APP"
fi

if ! pawguard_verify_app "$TARGET_APP"; then
    rm -rf "$TARGET_APP"
    [ ! -d "$BACKUP_APP" ] || mv "$BACKUP_APP" "$TARGET_APP"
    pawguard_die "Installed app verification failed; the previous installation was restored"
fi

[ ! -d "$BACKUP_APP" ] || rm -rf "$BACKUP_APP"
INSTALL_COMMITTED=true
trap - EXIT

pawguard_success "Installed $TARGET_APP"

if [ "$OPEN_AFTER_INSTALL" = true ]; then
    open "$TARGET_APP"
    pawguard_success "Launched $PAWGUARD_APP_NAME"
fi

printf '\nIf this is the first signed install, enable PawGuard in:\n'
printf 'System Settings → Privacy & Security → Accessibility\n'
printf 'Use make permissions to open that page directly.\n'
