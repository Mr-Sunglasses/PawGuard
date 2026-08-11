#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REMOVE_GENERATED=false
if [ "${1:-}" = "--all" ]; then
    REMOVE_GENERATED=true
elif [ -n "${1:-}" ]; then
    pawguard_die "Usage: ./scripts/clean.sh [--all]"
fi

pawguard_assert_project_root
pawguard_info "Removing PawGuard build directories"

find "$PAWGUARD_PROJECT_ROOT" -maxdepth 1 -type d -name '.build*' -print \
    | while IFS= read -r build_dir; do
        case "$(basename "$build_dir")" in
            .build|.build-*) rm -rf "$build_dir" ;;
            *) pawguard_die "Refusing unexpected clean target: $build_dir" ;;
        esac
    done

if [ "$REMOVE_GENERATED" = true ]; then
    if [ -d "$PAWGUARD_PROJECT_FILE" ]; then
        rm -rf "$PAWGUARD_PROJECT_FILE"
    fi
    if [ -d "$PAWGUARD_PROJECT_ROOT/dist" ]; then
        rm -rf "$PAWGUARD_PROJECT_ROOT/dist"
    fi
    pawguard_success "Removed build output, generated project, and packages"
else
    pawguard_success "Removed build output; generated project and packages were preserved"
fi
