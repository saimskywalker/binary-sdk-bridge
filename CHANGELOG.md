# Changelog

## Unreleased

Fixes found by running the README end to end as a new user would, plus
Windows support for the generator itself.

- The generated `tool/fetch_ios_sdk.sh` ran `flutter build` while trying to
  explain it: the backticks in the advice line were command substitution
  inside a double-quoted `echo`.
- A vendor binary name containing a dash or a dot — `Acme-SDK`, which the
  validator deliberately accepts — was substituted into the generated scripts'
  own shell variable names, producing `Acme-SDKS_DIR=...` and
  `${VENDOR_Acme-SDK_URL}`. The iOS script died on its first statement and the
  Android one built a garbage URL. The env-file keys are now literally
  `VENDOR_AAR_URL` / `VENDOR_AAR_SHA256`, as the script's own help text says.
- The `swift package describe` command the script prints ended in `\\`, so
  pasting it broke the line instead of continuing it.
- `--flavor native` no longer tells you to add a pub path dependency to a
  package that has no `pubspec.yaml`, and its fetch script no longer points at
  Flutter's `Runner.app`.
- The README's install step was missing entirely, and its example commands
  (`dart run binary_sdk_bridge`) could not work from a fresh checkout.
- Skip `chmod +x` on Windows so generation no longer throws
  `ProcessException` mid-write and leaves a half-written package (#3). On
  Unix a non-zero `chmod` exit is now surfaced instead of ignored.
- Keep Android package relative paths with `/` separators on Windows so
  planned and written layouts match other hosts.
- On Windows the CLI notes that `tool/fetch_*.sh` need WSL or Git Bash.

## 0.1.0

First release.

Generates a wrapper for a closed-source binary SDK: a Swift Package Manager
package on iOS and a Gradle module on Android, with the vendor binary kept out
of version control and **optional at build time** — so CI and a fresh checkout
build without ever holding the vendor's `.xcframework` or `.aar`.

Two flavours from one generator:

- `--flavor flutter` (default) — a Flutter plugin package: native wrappers, a
  Dart API, and the plugin classes on both platforms.
- `--flavor native` — the SPM package and the Gradle module only, with no
  Flutter anywhere. For a plain iOS or Android app, or any runtime that can
  consume a Swift package and a Gradle module.

Also in this release:

- Input that reaches a generated shell script is validated before any file is
  written, so a vendor name cannot smuggle a shell command into `tool/fetch_*.sh`.
- The generated fetch scripts clear all three SwiftPM manifest cache locations.
  Clearing fewer produces a green build that silently links no SDK at all.
- The Android module consumes the vendor `.aar` in a form that does not trip
  Gradle's refusal of local `.aar` dependencies inside a library module.
