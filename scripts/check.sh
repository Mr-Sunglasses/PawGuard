#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

pawguard_info "Checking shell script syntax"
for script_file in "$SCRIPT_DIR"/*.sh; do
    bash -n "$script_file"
done
pawguard_success "Shell syntax passed"

if command -v shellcheck >/dev/null 2>&1; then
    pawguard_info "Linting developer scripts with ShellCheck"
    shellcheck -x -P "$SCRIPT_DIR" "$SCRIPT_DIR"/*.sh
    pawguard_success "ShellCheck passed"
else
    pawguard_warning "ShellCheck is not installed; skipping optional shell lint"
fi

"$SCRIPT_DIR/format.sh" --check
"$SCRIPT_DIR/test.sh"

cd "$PAWGUARD_PROJECT_ROOT"
pawguard_info "Running Xcode static analysis"
xcodebuild \
    -project "$PAWGUARD_PROJECT_FILE" \
    -scheme "$PAWGUARD_SCHEME" \
    -configuration Debug \
    -sdk macosx \
    -derivedDataPath "$PAWGUARD_PROJECT_ROOT/.build/analyze" \
    CODE_SIGNING_ALLOWED=NO \
    analyze \
    -quiet
pawguard_success "Static analysis passed"

printf '\nAll PawGuard checks passed.\n'
