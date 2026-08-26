# Changelog

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
