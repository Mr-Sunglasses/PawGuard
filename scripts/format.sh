#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

MODE="${1:-}"
[ -n "$MODE" ] || MODE="--write"
xcrun --find swift-format >/dev/null 2>&1 \
    || pawguard_die "swift-format is unavailable in the selected Xcode toolchain"

cd "$PAWGUARD_PROJECT_ROOT"
case "$MODE" in
    --write)
        xcrun swift-format format --configuration .swift-format --recursive --parallel --in-place PawGuard Tests
        pawguard_success "Formatted PawGuard and Tests"
        ;;
    --check)
        xcrun swift-format lint --configuration .swift-format --recursive --parallel --strict PawGuard Tests
        pawguard_success "Swift formatting is clean"
        ;;
    *) pawguard_die "Usage: ./scripts/format.sh [--write|--check]" ;;
esac
