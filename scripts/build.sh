#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CONFIGURATION="Debug"
SIGNED=false
OPEN_AFTER_BUILD=false

usage() {
    printf '%s\n' \
        "Usage: ./scripts/build.sh [--debug|--release] [--signed] [--open]" \
        "" \
        "  --debug      Build the Debug configuration (default)" \
        "  --release    Build the Release configuration" \
        "  --signed     Apply and verify a stable Apple code signature" \
        "  --open       Launch the app after a successful build"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --debug) CONFIGURATION="Debug" ;;
        --release) CONFIGURATION="Release" ;;
        --signed) SIGNED=true ;;
        --open) OPEN_AFTER_BUILD=true ;;
        -h|--help) usage; exit 0 ;;
        *) pawguard_die "Unknown build option: $1" ;;
    esac
    shift
done

pawguard_assert_project_root
pawguard_require_command xcodegen
pawguard_require_command xcodebuild
pawguard_require_command codesign

SIGNING_MODE="unsigned"
if [ "$SIGNED" = true ]; then
    SIGNING_MODE="signed"
    pawguard_stop_running_app
fi

DERIVED_DATA="$(pawguard_derived_data_path "$SIGNING_MODE")"
APP_PATH="$(pawguard_app_path "$CONFIGURATION" "$SIGNING_MODE")"

cd "$PAWGUARD_PROJECT_ROOT"
pawguard_info "Generating PawGuard.xcodeproj"
xcodegen generate

pawguard_info "Building $CONFIGURATION ($SIGNING_MODE)"
XCODEBUILD_ARGS=(
    -project "$PAWGUARD_PROJECT_FILE"
    -scheme "$PAWGUARD_SCHEME"
    -configuration "$CONFIGURATION"
    -sdk macosx
    -derivedDataPath "$DERIVED_DATA"
    CODE_SIGNING_ALLOWED=NO
    build
)

if [ "${PAWGUARD_VERBOSE:-0}" = "1" ]; then
    xcodebuild "${XCODEBUILD_ARGS[@]}"
else
    xcodebuild "${XCODEBUILD_ARGS[@]}" -quiet
fi

[ -d "$APP_PATH" ] || pawguard_die "Build completed without producing $APP_PATH"

if [ "$SIGNED" = true ]; then
    SIGNING_IDENTITY="$(pawguard_resolve_signing_identity)"
    pawguard_info "Signing with $SIGNING_IDENTITY"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
    pawguard_verify_app "$APP_PATH" \
        || pawguard_die "Code-signature or bundle-identifier verification failed: $APP_PATH"
    pawguard_success "Signature is valid and satisfies its designated requirement"
fi

pawguard_success "Built $APP_PATH"

if [ "$OPEN_AFTER_BUILD" = true ]; then
    pawguard_stop_running_app
    open "$APP_PATH"
    pawguard_success "Launched $PAWGUARD_APP_NAME"
fi
