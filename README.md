# binary-sdk-bridge

Generate a Flutter plugin that wraps a **closed-source binary SDK** — Swift
Package Manager on iOS, a Gradle module on Android — with the vendor binary
kept out of version control and *optional at build time*.

```bash
dart run binary_sdk_bridge \
  --name acme_ads --org com.example \
  --ios-framework AcmeSDK --android-aar AcmeSDK \
  --out packages
```

## The problem

Plenty of vendor SDKs — ad mediation, analytics, payments, DRM — ship as a
prebuilt `.xcframework` behind a CocoaPods podspec and a bare `.aar`. Wiring
one into a Flutter app that uses **Swift Package Manager** runs into three
walls at once:

1. **SPM and CocoaPods have no shared resolver.** If the vendor pod and a
   pub.dev plugin both depend on the same underlying SDK, the version cannot be
   negotiated between them. The usual advice — "just use a CocoaPods wrapper" —
   quietly means *turn SPM off for the whole app*. That is a worse trade every
   month: **CocoaPods trunk goes permanently read-only on 2026-12-02.**

2. **The binary cannot be committed, but the build must still work without it.**
   Vendor binaries are proprietary, often issued per customer, and large. Yet a
   `.binaryTarget(path:)` pointing at a file that is not there fails the resolve
   of the **entire** SPM package graph — not just that target. So a fresh
   checkout without vendor credentials cannot build *anything*, and CI never
   can.

3. **A bare `.aar` carries no transitive dependency metadata.** Every SDK it
   expects at runtime has to be declared and version-managed by hand, and a
   missing one is a `ClassNotFoundException` at call time rather than a build
   error.

## What the generated package does about it

**The vendor binary is optional, and that is enforced by the build system, not
by convention.**

| | Probe | What it swaps |
|---|---|---|
| iOS | `Package.swift` checks `Frameworks/<Name>.xcframework` | declares the `binaryTarget` and defines a compilation condition |
| Android | `build.gradle.kts` checks `libs/<Name>.aar` | selects the `withSdk` or `noSdk` source set |

Without the binary, the plugin still compiles and still answers Dart — it just
reports `unavailable`. With it, the same call sites reach the real SDK. Nobody
needs vendor credentials to build the app, and CI stays green.

> ⚠️ SPM caches manifest evaluation by manifest **content**, not by filesystem
> state, so dropping the binary in afterwards does not by itself flip the
> branch. The generated fetch script clears the Flutter SPM cache for exactly
> this reason.

**No reflection on Android.** Kotlin has no `#if`. The alternatives were
`Class.forName` or two source sets declaring the same object; the generator
picks source sets, because reflection would compile fine without the SDK while
throwing away every compile-time check against the vendor API — precisely the
surface least worth leaving unchecked. A generated test asserts the two bridges
keep identical signatures, since drift there compiles in one configuration and
not the other.

**The native layers carry no Flutter import**, so one wrapper serves three
consumers:

| Consumer | Entry point |
|---|---|
| Flutter | `package:<name>/<name>.dart` |
| Plain iOS | the `<Name>Kit` SPM product |
| Plain Android | the generated Gradle module |

**Every degraded path fails closed.** Absent binary, unregistered plugin, native
throw, malformed payload — all resolve to `VendorState.unavailable(reason)` with
a machine-readable token. There is no `unknown` state to misread, and nothing on
the API throws at the call site.

**Downloads are checksum-pinned or refused.** The fetch scripts will not
trust-on-first-use: an artifact that links into a shipping app, behind a vendor
URL whose contents can change silently, is not something to accept sight-unseen.

## Generated layout

```
acme_ads/
├── pubspec.yaml
├── lib/
│   ├── acme_ads.dart              # probe() / initialize()
│   └── src/vendor_state.dart      # sealed ready | unavailable
├── ios/acme_ads/
│   ├── Package.swift              # the conditional binaryTarget
│   ├── Frameworks/                # gitignored — fetched
│   └── Sources/
│       ├── AcmeAdsKit/            # no Flutter import
│       └── acme_ads/              # the Flutter plugin
├── android/
│   ├── build.gradle.kts           # AGP 9 DSL
│   ├── libs/                      # gitignored — fetched
│   └── src/{main,noSdk,withSdk}/
├── test/
└── tool/fetch_{ios,android}_sdk.sh
```

Exactly one file has a `TODO`: the bridge. That is the only place the vendor's
own API appears, which is the point — everything around it is already decided.

## Notes for the generated Android module

Written against the **AGP 9** DSL, which also works on AGP 8. Two forms are
avoided deliberately, because AGP 9.1 rejects them at *script compilation* —
failing the module before a single source file is read:

- `kotlinOptions` inside `android { }` → top-level `kotlin { compilerOptions { } }`
- `sourceSets { java.srcDir(...) }` → `java.directories.add(...)`

The first is the nastier one: it also drags the `android { }` accessor itself
into deprecation-as-error.

## Options

| Flag | Default | |
|---|---|---|
| `--name`, `-n` | *required* | plugin package name, `lower_snake_case` |
| `--org`, `-o` | *required* | reverse-DNS prefix, e.g. `com.example` |
| `--ios-framework` | — | `.xcframework` base name; omit to skip iOS |
| `--android-aar` | — | `.aar` base name; omit to skip Android |
| `--out` | `.` | directory to create the package in |
| `--ios-target` | `15.0` | iOS deployment target |
| `--min-sdk` | `24` | Android `minSdk` |
| `--compile-sdk` | `36` | Android `compileSdk` |
| `--java` | `17` | Java / `jvmTarget` |
| `--dry-run` | | list the files without writing them |
| `--force` | | overwrite an existing package directory |

## Status

Early. The generated package is verified end-to-end — `flutter pub get`,
`flutter analyze` and `flutter test` all pass on fresh output, and the same
structure builds on both platforms in a real app. What it does **not** do yet
is write the vendor calls for you; no generator can, since that API is
whatever the vendor shipped.

## License

MIT
