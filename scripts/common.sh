#!/bin/bash

# Shared constants and helpers for PawGuard developer scripts.
# shellcheck disable=SC2034  # Constants are consumed by scripts that source this file.

PAWGUARD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAWGUARD_PROJECT_ROOT="$(dirname "$PAWGUARD_SCRIPT_DIR")"
PAWGUARD_APP_NAME="PawGuard"
PAWGUARD_BUNDLE_ID="com.pawguard.app"
PAWGUARD_PROJECT_FILE="$PAWGUARD_PROJECT_ROOT/PawGuard.xcodeproj"
PAWGUARD_SCHEME="PawGuard"
PAWGUARD_INSTALL_DIR="${PAWGUARD_INSTALL_DIR:-/Applications}"

pawguard_info() {
    printf '→ %s\n' "$*"
}

pawguard_success() {
    printf '✓ %s\n' "$*"
}

pawguard_warning() {
    printf 'Warning: %s\n' "$*" >&2
}

pawguard_die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

pawguard_require_command() {
    command -v "$1" >/dev/null 2>&1 || pawguard_die "Required command not found: $1"
}

pawguard_assert_project_root() {
    [ -f "$PAWGUARD_PROJECT_ROOT/project.yml" ] || pawguard_die "project.yml is missing from $PAWGUARD_PROJECT_ROOT"
    [ -d "$PAWGUARD_PROJECT_ROOT/PawGuard" ] || pawguard_die "PawGuard source directory is missing"
}

pawguard_configuration_name() {
    case "${1:-Debug}" in
        Debug|debug) printf 'Debug\n' ;;
        Release|release) printf 'Release\n' ;;
        *) pawguard_die "Unknown build configuration: $1" ;;
    esac
}

pawguard_derived_data_path() {
    if [ "${1:-unsigned}" = "signed" ]; then
        printf '%s/.build/signed\n' "$PAWGUARD_PROJECT_ROOT"
    else
        printf '%s/.build/dev\n' "$PAWGUARD_PROJECT_ROOT"
    fi
}

pawguard_app_path() {
    local configuration
    local signing_mode
    configuration="$(pawguard_configuration_name "${1:-Debug}")"
    signing_mode="${2:-unsigned}"
    printf '%s/Build/Products/%s/%s.app\n' \
        "$(pawguard_derived_data_path "$signing_mode")" \
        "$configuration" \
        "$PAWGUARD_APP_NAME"
}

pawguard_resolve_signing_identity() {
    local identities
    local identity
    local team_filter

    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    identity="${PAWGUARD_SIGNING_IDENTITY:-}"
    team_filter="${PAWGUARD_TEAM_ID:-}"

    if [ -n "$identity" ]; then
        printf '%s\n' "$identities" | grep -F "\"$identity\"" >/dev/null 2>&1 \
            || pawguard_die "PAWGUARD_SIGNING_IDENTITY is not available in the keychain"
        printf '%s\n' "$identity"
        return
    fi

    if [ -n "$team_filter" ]; then
        identity="$(printf '%s\n' "$identities" \
            | awk -F '"' -v suffix="($team_filter)" \
                '/Apple Development:|Developer ID Application:/ && index($2, suffix) { print $2; exit }')"
    else
        identity="$(printf '%s\n' "$identities" \
            | awk -F '"' '/Apple Development:/ { print $2; exit }')"
        if [ -z "$identity" ]; then
            identity="$(printf '%s\n' "$identities" \
                | awk -F '"' '/Developer ID Application:/ { print $2; exit }')"
        fi
    fi

    [ -n "$identity" ] || pawguard_die \
        "No Apple Development or Developer ID Application signing identity was found. Run 'make doctor' for setup help."
    printf '%s\n' "$identity"
}

pawguard_stop_running_app() {
    if pgrep -x "$PAWGUARD_APP_NAME" >/dev/null 2>&1; then
        pawguard_info "Stopping the running $PAWGUARD_APP_NAME instance"
        pkill -x "$PAWGUARD_APP_NAME" 2>/dev/null || true
        local attempt=0
        while pgrep -x "$PAWGUARD_APP_NAME" >/dev/null 2>&1 && [ "$attempt" -lt 30 ]; do
            sleep 0.1
            attempt=$((attempt + 1))
        done
        pgrep -x "$PAWGUARD_APP_NAME" >/dev/null 2>&1 \
            && pawguard_die "$PAWGUARD_APP_NAME did not quit"
    fi
    return 0
}

pawguard_verify_app() {
    local app_path="$1"
    local bundle_identifier
    [ -d "$app_path" ] || return 1
    codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 || return 1
    bundle_identifier="$(/usr/libexec/PlistBuddy \
        -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
    [ "$bundle_identifier" = "$PAWGUARD_BUNDLE_ID" ]
}

pawguard_assert_safe_app_target() {
    local app_path="$1"
    local parent_path
    parent_path="$(dirname "$app_path")"
    case "$app_path" in
        /*) ;;
        *) pawguard_die "Install target must be an absolute path: $app_path" ;;
    esac
    case "/$app_path/" in
        */../*|*/./*) pawguard_die "Refusing a non-canonical install target: $app_path" ;;
    esac
    [ "$(basename "$app_path")" = "$PAWGUARD_APP_NAME.app" ] \
        || pawguard_die "Refusing unexpected app target: $app_path"
    [ "$parent_path" != "/" ] && [ "$parent_path" != "$HOME" ] \
        || pawguard_die "Refusing unsafe install directory: $parent_path"
}
