#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

"$SCRIPT_DIR/build.sh" --release --signed

APP_PATH="$(pawguard_app_path Release signed)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHITECTURE="$(uname -m)"
DIST_DIR="$PAWGUARD_PROJECT_ROOT/dist"
ARCHIVE_PATH="$DIST_DIR/PawGuard-$VERSION-$ARCHITECTURE.zip"

mkdir -p "$DIST_DIR"
if [ -f "$ARCHIVE_PATH" ]; then
    rm -f "$ARCHIVE_PATH"
fi

pawguard_info "Creating $ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
shasum -a 256 "$ARCHIVE_PATH" > "$ARCHIVE_PATH.sha256"

pawguard_success "Package created"
printf 'Archive: %s\n' "$ARCHIVE_PATH"
printf 'SHA-256: %s\n' "$(awk '{print $1}' "$ARCHIVE_PATH.sha256")"
printf 'Note: local development packages are signed but not notarized.\n'
