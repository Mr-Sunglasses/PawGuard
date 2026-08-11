#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ONLY_TEST=""
if [ "${1:-}" = "--only" ]; then
    [ -n "${2:-}" ] || pawguard_die "--only requires a test identifier"
    ONLY_TEST="$2"
elif [ -n "${1:-}" ]; then
    pawguard_die "Usage: ./scripts/test.sh [--only PawGuardTests/TestCase/testName]"
fi

pawguard_require_command xcodegen
pawguard_require_command xcodebuild
cd "$PAWGUARD_PROJECT_ROOT"
xcodegen generate

TEST_ARGS=(
    -project "$PAWGUARD_PROJECT_FILE"
    -scheme "$PAWGUARD_SCHEME"
    -configuration Debug
    -sdk macosx
    -derivedDataPath "$PAWGUARD_PROJECT_ROOT/.build-tests"
    CODE_SIGNING_ALLOWED=NO
    test
)

if [ -n "$ONLY_TEST" ]; then
    TEST_ARGS+=("-only-testing:$ONLY_TEST")
fi

pawguard_info "Running PawGuard tests${ONLY_TEST:+: $ONLY_TEST}"
xcodebuild "${TEST_ARGS[@]}" -quiet
pawguard_success "Tests passed"
