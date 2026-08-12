# Development workflow

PawGuard's developer tooling follows one rule: compilation-only builds may be unsigned, but anything used for live Accessibility testing must have a stable signature and path.

## Quick start

```sh
make setup
make run
```

`make setup` checks macOS and Xcode, installs XcodeGen with Homebrew when necessary, generates `PawGuard.xcodeproj`, performs an unsigned Debug build, and runs the environment doctor.

`make run` builds PawGuard into `.build/signed`, applies the selected Apple Development signature, verifies the bundle identifier and signature, then launches the exact signed product.

## Make targets

| Command | Purpose |
| --- | --- |
| `make help` | Display the complete command list |
| `make setup` | Install missing XcodeGen, generate, and build |
| `make doctor` | Check Xcode, XcodeGen, formatter, signing, install, and running state |
| `make generate` | Regenerate the Xcode project from `project.yml` |
| `make open-project` | Generate and open the project in Xcode |
| `make build` | Unsigned Debug compilation build |
| `make build-release` | Unsigned Release compilation build |
| `make run` | Signed Debug build and launch |
| `make install` | Signed Release build and safe `/Applications` install |
| `make install-debug` | Signed Debug install for inspection |
| `make package` | Signed Release ZIP and SHA-256 in `dist/` |
| `make test` | Run all unit tests |
| `make test TEST=...` | Run one test suite or method |
| `make analyze` | Run Xcode static analysis |
| `make check` | Shell syntax, formatting, tests, and analysis |
| `make format` | Apply the repository's Swift format |
| `make format-check` | Validate formatting without edits |
| `make permissions` | Open macOS Accessibility settings |
| `make logs` | Show recent unified logs |
| `make logs-follow` | Stream unified logs |
| `make clean` | Remove `.build*` directories |
| `make clean-all` | Also remove the generated project and `dist/` |

## Targeted tests

Pass Xcode's test identifier through `TEST`:

```sh
make test TEST=PawGuardTests/CatDetectorTests
make test TEST=PawGuardTests/CatDetectorTests/testFastSequentialTypingDoesNotDetect
```

The complete local acceptance check is:

```sh
make check
```

It validates every shell script with `bash -n`, checks Swift formatting, regenerates the project, runs all tests, and runs Xcode static analysis.

## Signing selection

The scripts inspect the login keychain and prefer the first `Apple Development` identity, falling back to `Developer ID Application` if available. Inspect identities with:

```sh
security find-identity -v -p codesigning
```

Choose an exact identity when multiple certificates are installed:

```sh
PAWGUARD_SIGNING_IDENTITY='Apple Development: Your Name (IDENTIFIER)' make run
```

Or filter by the identifier shown in parentheses:

```sh
PAWGUARD_TEAM_ID=IDENTIFIER make run
```

Use the same identity consistently. Changing between certificates, ad-hoc builds, and unsigned products can invalidate the Accessibility approval associated with a previous build.

Set `PAWGUARD_VERBOSE=1` to show complete `xcodebuild` output:

```sh
PAWGUARD_VERBOSE=1 make run
```

## Installation

`make install` performs these steps:

1. Stops a running PawGuard process.
2. Produces and verifies a signed Release build.
3. Copies it to a hidden staging bundle beside the final install path.
4. Verifies the staged bundle before replacing anything.
5. Moves an existing installation to a temporary backup.
6. Atomically moves the staged app into place and verifies it again.
7. Restores the previous app if final verification fails.
8. Launches the installed app.

The default target is `/Applications/PawGuard.app`. To use a per-user Applications directory:

```sh
mkdir -p "$HOME/Applications"
PAWGUARD_INSTALL_DIR="$HOME/Applications" make install
```

Use the same `PAWGUARD_INSTALL_DIR` value for `make doctor` and `make uninstall`.

## Uninstall and reset safety

The default uninstall preserves profiles, photos, statistics, preferences, and Accessibility permission:

```sh
make uninstall
```

It moves the installed app to Trash so it remains recoverable. Build output is separate and remains in the checkout.

The reset commands have intentionally different scopes:

| Command | App | Preferences | Profiles/photos | Accessibility |
| --- | --- | --- | --- | --- |
| `make reset-onboarding` | Keep | Reset settings | Keep | Keep |
| `make reset-permission` | Keep | Keep | Keep | Reset |
| `make reset-data` | Keep | Reset | Move to Trash | Keep |
| `make reset-all` | Keep | Reset | Move to Trash | Reset |
| `make uninstall` | Move to Trash | Keep | Keep | Keep |
| `make uninstall-all` | Move to Trash | Reset | Move to Trash | Reset |

Data-destructive commands ask for confirmation. Local cat photos are moved to Trash instead of being immediately erased.

## Packaging

`make package` creates a locally signed Release archive and checksum:

```text
dist/PawGuard-<version>-<architecture>.zip
dist/PawGuard-<version>-<architecture>.zip.sha256
```

This development archive is not notarized. It is suitable for local transfer and testing, not a public macOS release. Public distribution requires Developer ID signing, notarization, stapling, and independent artifact verification.

## Script map

| Script | Responsibility |
| --- | --- |
| `common.sh` | Constants, path validation, signing selection, process and bundle checks |
| `setup.sh` | Dependency/bootstrap workflow |
| `doctor.sh` | Read-only local diagnostics |
| `build.sh` | Debug/Release and signed/unsigned builds |
| `run-signed.sh` | Stable signed development launch |
| `install.sh` | Verified install with rollback |
| `uninstall.sh` | Recoverable app removal and optional full reset |
| `reset.sh` | Scoped onboarding, data, and permission reset |
| `test.sh` | Full or targeted Xcode tests |
| `check.sh` | Local CI-equivalent checks |
| `format.sh` | Xcode-provided Swift formatter |
| `clean.sh` | Validated build-output cleanup |

## Detection traces

`Tests/Fixtures/*.jsonl` holds keyboard traces replayed by `TraceReplayTests`. One JSON object per line:

```json
{"flags":0,"key":3,"kind":"down","repeated":false,"time":0.0}
```

`kind` is `down`, `up`, or `flags`; `time` is in seconds from the start of the trace. Files named `cat-*` must trigger protection; every other file must not. Drop a recorded session in beside the generated ones and it is picked up automatically — no project changes needed.

When you change score weights, run `make test` and read the replay failures: they name the trace and its peak score, which is usually enough to see whether the change helped or just moved the problem.
| `logs.sh` | Recent or streaming unified logs |
| `package.sh` | Signed local ZIP and checksum |

## Common recovery flow

If Accessibility appears granted but monitoring cannot start:

```sh
make doctor
make install
make reset-permission
make permissions
```

Enable the installed PawGuard entry in System Settings, then launch `/Applications/PawGuard.app`. Do not switch back to an unsigned product when validating the repaired permission.
