# Contributing

Contributions are welcome. A few things worth knowing before you spend time.

## How changes land

Every change reaches `main` through a pull request that the maintainer
reviews and merges. That includes changes from forks, which is the normal path
— you cannot push to this repository directly, and nothing merges without a
review. If a PR sits without a response, a nudge is fine.

## The product is the generated output

This repository generates files. A change to a template is only reviewable
alongside what it produces, so please generate both flavours and read the
result:

```bash
dart run bin/binary_sdk_bridge.dart --name acme_ads --org com.example \
  --ios-framework AcmeSDK --android-aar AcmeSDK --out /tmp/flutter

dart run bin/binary_sdk_bridge.dart --name acme_sdk --org com.example \
  --flavor native --ios-framework AcmeSDK --android-aar AcmeSDK --out /tmp/native
```

Paste the relevant part of the output into the PR. A template diff alone hides
the thing users will actually see, and escaping mistakes in particular look
fine in the template and wrong in the output.

## Before opening a PR

```bash
dart pub get
dart analyze --fatal-infos
dart format .
dart test
```

CI runs the same, plus a check that no template expression leaked into the
generated files and that the generated shell scripts parse.

## What a good bug fix looks like

A test that fails without the fix. Several of the tests here exist because
something shipped broken once — the comments say which — and that is the shape
worth adding to.

## Things to be careful with

**Anything that reaches a generated shell script.** Binary names are
interpolated into `tool/fetch_*.sh`. They are validated for exactly that
reason, and the validation has tests with real injection payloads. Please do
not widen it without a strong case.

**Escaping in templates.** A `$` that should interpolate but does not prints
the expression verbatim into the user's file. A test walks every generated file
of both flavours checking for that, which is the only reliable guard.

**Fail-closed defaults.** The generated bridge treats every degraded state as
"binary absent". That direction is deliberate: an integration that silently
believes it has a vendor SDK when it does not is worse than one that plainly
says it has none.

## Scope

This wraps a vendor's prebuilt binary for consumption. It is not a build
system, not a dependency manager, and it does not try to write the vendor's API
calls for you — no generator can, since that API is whatever the vendor
shipped.
