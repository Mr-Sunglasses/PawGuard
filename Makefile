# PawGuard developer commands. Run `make help` for the command list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

TEST ?=

.PHONY: help setup bootstrap doctor generate open-project build build-release run dev install install-debug reinstall uninstall uninstall-all package test analyze check ci format format-check clean clean-all reset-onboarding reset-permission reset-data reset-all permissions logs logs-follow

## Show available developer commands
help:
	@printf '%s\n' \
		'PawGuard developer commands' \
		'' \
		'  make setup              Install missing tooling, generate, and build' \
		'  make doctor             Diagnose Xcode, XcodeGen, signing, and install state' \
		'  make generate           Regenerate PawGuard.xcodeproj with XcodeGen' \
		'  make open-project       Generate and open the Xcode project' \
		'' \
		'  make build              Fast unsigned Debug build for compilation checks' \
		'  make build-release      Unsigned Release build for compilation checks' \
		'  make run                Signed Debug build and launch (recommended for dev)' \
		'  make install            Signed Release build, install to /Applications, launch' \
		'  make install-debug      Signed Debug install to /Applications' \
		'  make package            Signed Release ZIP plus SHA-256 in dist/' \
		'' \
		'  make test               Run all tests' \
		'  make test TEST=...      Run one test identifier' \
		'  make analyze            Run Xcode static analysis' \
		'  make check              Format check, tests, analysis, and shell validation' \
		'  make format             Format Swift sources with the selected Xcode toolchain' \
		'  make format-check       Check formatting without changing files' \
		'' \
		'  make permissions        Open macOS Accessibility settings' \
		'  make reset-onboarding   Re-run onboarding; preserve cat profiles/photos' \
		'  make reset-permission   Reset only PawGuard Accessibility permission' \
		'  make reset-data         Reset preferences, profiles, stats, and local photos' \
		'  make uninstall          Move installed app to Trash; preserve local data' \
		'  make uninstall-all      Uninstall and reset local data/permission' \
		'' \
		'  make logs               Show recent PawGuard unified logs' \
		'  make logs-follow        Stream PawGuard unified logs' \
		'  make clean              Remove build output' \
		'  make clean-all          Also remove generated project and dist/' \
		'' \
		'Environment: PAWGUARD_SIGNING_IDENTITY, PAWGUARD_TEAM_ID,' \
		'             PAWGUARD_INSTALL_DIR, PAWGUARD_VERBOSE=1'

## Install dependencies and prepare a development checkout
setup:
	@./scripts/setup.sh --install-deps

bootstrap: setup

## Diagnose the local development and signing environment
doctor:
	@./scripts/doctor.sh

## Regenerate the Xcode project
generate:
	@xcodegen generate

## Regenerate and open the Xcode project
open-project: generate
	@open PawGuard.xcodeproj

## Build Debug without signing
build:
	@./scripts/build.sh --debug

## Build Release without signing
build-release:
	@./scripts/build.sh --release

## Build, sign, and launch the stable development app
run:
	@./scripts/run-signed.sh

dev: run

## Build, sign, install to Applications, and launch
install:
	@./scripts/install.sh

## Install a signed Debug build
install-debug:
	@./scripts/install.sh --debug

reinstall: install

## Move the installed app to Trash while preserving data
uninstall:
	@./scripts/uninstall.sh

## Uninstall and reset local data plus Accessibility permission
uninstall-all:
	@./scripts/uninstall.sh --all

## Build a signed Release ZIP and checksum
package:
	@./scripts/package.sh

## Run all tests, or one test with TEST=PawGuardTests/TestCase/testName
test:
	@if [ -n "$(TEST)" ]; then ./scripts/test.sh --only "$(TEST)"; else ./scripts/test.sh; fi

## Run Xcode static analysis
analyze: generate
	@xcodebuild -project PawGuard.xcodeproj -scheme PawGuard -configuration Debug -sdk macosx -derivedDataPath .build/analyze CODE_SIGNING_ALLOWED=NO analyze -quiet

## Run the complete local validation suite
check:
	@./scripts/check.sh

ci: check

## Format Swift sources
format:
	@./scripts/format.sh --write

## Validate Swift formatting without edits
format-check:
	@./scripts/format.sh --check

## Remove build output
clean:
	@./scripts/clean.sh

## Remove build output, generated project, and packages
clean-all:
	@./scripts/clean.sh --all

## Reset onboarding and settings while preserving cat profiles/photos
reset-onboarding:
	@./scripts/reset.sh onboarding

## Reset PawGuard Accessibility permission
reset-permission:
	@./scripts/reset.sh permission

## Reset all PawGuard local data; asks for confirmation
reset-data:
	@./scripts/reset.sh data

## Reset all local data and Accessibility permission; asks for confirmation
reset-all:
	@./scripts/reset.sh all

## Open macOS Accessibility settings
permissions:
	@open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'

## Show recent PawGuard logs
logs:
	@./scripts/logs.sh --recent

## Follow PawGuard logs
logs-follow:
	@./scripts/logs.sh --follow
