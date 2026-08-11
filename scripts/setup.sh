#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

INSTALL_DEPS=false
BUILD_AFTER_SETUP=true

usage() {
    printf '%s\n' \
        "Usage: ./scripts/setup.sh [--install-deps] [--no-build]" \
        "" \
        "  --install-deps  Install XcodeGen with Homebrew when missing" \
        "  --no-build      Generate the project without compiling it"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --install-deps) INSTALL_DEPS=true ;;
        --no-build) BUILD_AFTER_SETUP=false ;;
        -h|--help) usage; exit 0 ;;
        *) pawguard_die "Unknown setup option: $1" ;;
    esac
    shift
done

pawguard_assert_project_root

[ "$(uname -s)" = "Darwin" ] || pawguard_die "PawGuard development requires macOS"
pawguard_require_command xcode-select
pawguard_require_command xcodebuild
xcode-select -p >/dev/null 2>&1 || pawguard_die "Install Xcode and select it with xcode-select"
xcodebuild -version >/dev/null

if ! command -v xcodegen >/dev/null 2>&1; then
    if [ "$INSTALL_DEPS" = true ]; then
        pawguard_require_command brew
        pawguard_info "Installing XcodeGen with Homebrew"
        brew install xcodegen
    else
        pawguard_die "XcodeGen is missing. Run 'make setup' or 'brew install xcodegen'."
    fi
fi

cd "$PAWGUARD_PROJECT_ROOT"
pawguard_info "Generating the Xcode project"
xcodegen generate

if [ "$BUILD_AFTER_SETUP" = true ]; then
    "$SCRIPT_DIR/build.sh" --debug
fi

"$SCRIPT_DIR/doctor.sh"

printf '\nSetup complete. Next commands:\n'
printf '  make run      Build, sign, and launch PawGuard\n'
printf '  make install  Install a signed Release build to %s\n' "$PAWGUARD_INSTALL_DIR"
printf '  make check    Run formatting checks, tests, and analysis\n'
