#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ERRORS=0
WARNINGS=0

pass() {
    printf '✓ %-24s %s\n' "$1" "$2"
}

warn() {
    printf '! %-24s %s\n' "$1" "$2"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    printf '✗ %-24s %s\n' "$1" "$2"
    ERRORS=$((ERRORS + 1))
}

printf 'PawGuard development doctor\n\n'

if [ "$(uname -s)" = "Darwin" ]; then
    pass "Platform" "macOS $(sw_vers -productVersion) ($(uname -m))"
else
    fail "Platform" "macOS is required"
fi

if command -v xcodebuild >/dev/null 2>&1; then
    pass "Xcode" "$(xcodebuild -version | tr '\n' ' ')"
else
    fail "Xcode" "xcodebuild not found"
fi

if command -v xcodegen >/dev/null 2>&1; then
    pass "XcodeGen" "$(xcodegen --version 2>/dev/null)"
else
    fail "XcodeGen" "missing; run 'brew install xcodegen'"
fi

if xcrun --find swift-format >/dev/null 2>&1; then
    pass "swift-format" "$(xcrun swift-format --version 2>/dev/null)"
else
    warn "swift-format" "unavailable; make format will not work"
fi

if [ -f "$PAWGUARD_PROJECT_ROOT/project.yml" ]; then
    pass "Project manifest" "$PAWGUARD_PROJECT_ROOT/project.yml"
else
    fail "Project manifest" "project.yml is missing"
fi

if [ -f "$PAWGUARD_PROJECT_FILE/project.pbxproj" ]; then
    if [ "$PAWGUARD_PROJECT_ROOT/project.yml" -nt "$PAWGUARD_PROJECT_FILE/project.pbxproj" ]; then
        warn "Generated project" "stale; run 'make generate'"
    else
        pass "Generated project" "$PAWGUARD_PROJECT_FILE"
    fi
else
    warn "Generated project" "missing; run 'make generate'"
fi

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Apple Development:|Developer ID Application:/ { print $2; exit }')"
if [ -n "$IDENTITY" ]; then
    pass "Signing identity" "$IDENTITY"
else
    warn "Signing identity" "none; unsigned builds work, but Accessibility approval will not persist"
fi

# An Xcode build with no development team is signed ad hoc, and macOS binds an
# Accessibility grant to the exact binary in that case. Every rebuild then voids
# the permission while System Settings still lists an enabled PawGuard row for
# the build before it, which looks exactly like the app ignoring the grant.
XCODE_BUILD="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -maxdepth 5 -type d -name "$PAWGUARD_APP_NAME.app" 2>/dev/null | head -1)"
if [ -n "$XCODE_BUILD" ]; then
    if codesign -dvv "$XCODE_BUILD" 2>&1 | grep -q "flags=.*adhoc"; then
        warn "Xcode build signature" \
            "ad-hoc signed; Accessibility approval dies on every rebuild. Use 'make run', or set PAWGUARD_TEAM_ID and re-run 'make generate'"
    else
        pass "Xcode build signature" "stably signed; Accessibility approval survives rebuilds"
    fi
fi

if [ -n "${PAWGUARD_TEAM_ID:-}" ]; then
    pass "Development team" "$PAWGUARD_TEAM_ID"
else
    warn "Development team" \
        "PAWGUARD_TEAM_ID is unset; builds made from Xcode itself will be ad-hoc signed"
fi

INSTALL_PATH="$PAWGUARD_INSTALL_DIR/$PAWGUARD_APP_NAME.app"
if [ -d "$INSTALL_PATH" ]; then
    if pawguard_verify_app "$INSTALL_PATH"; then
        pass "Installed app" "$INSTALL_PATH (valid signature and bundle identifier)"
    else
        warn "Installed app" "$INSTALL_PATH has an invalid signature or bundle identifier"
    fi
else
    warn "Installed app" "not installed; run 'make install'"
fi

if pgrep -x "$PAWGUARD_APP_NAME" >/dev/null 2>&1; then
    pass "Running process" "PID $(pgrep -x "$PAWGUARD_APP_NAME" | tr '\n' ' ')"
else
    pass "Running process" "not running"
fi

if [ -d "$HOME/Library/Application Support/PawGuard" ]; then
    pass "Local app data" "$HOME/Library/Application Support/PawGuard"
else
    pass "Local app data" "not created yet"
fi

printf '\nResult: %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS"
[ "$ERRORS" -eq 0 ]
