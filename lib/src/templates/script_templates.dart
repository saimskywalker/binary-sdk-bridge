import '../spec.dart';

/// Fetch script for the iOS xcframework.
///
/// It refuses an unpinned download rather than trusting on first use: the
/// artifact links into a shipping app, and a vendor URL whose contents can
/// change silently is not something to accept sight-unseen.
String fetchIosSh(BridgeSpec spec) => r'''
#!/usr/bin/env bash
#
# Fetch the vendor xcframework into ios/PLUGIN/Frameworks/.
#
# The binary is NOT committed. This script is the only supported way to put it
# in place, so every machine and CI runner ends up with a byte-identical,
# checksum-verified copy.
#
#   Usage:
#     tool/fetch_ios_sdk.sh                  # reads tool/sdk_source.env
#     VENDOR_URL=... VENDOR_SHA256=... tool/fetch_ios_sdk.sh
#     tool/fetch_ios_sdk.sh /path/to/Vendor.xcframework   # local directory
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="$PKG_DIR/ios/PLUGIN/Frameworks"
ENV_FILE="$PKG_DIR/tool/sdk_source.env"
DEST="$FRAMEWORKS_DIR/FRAMEWORK.xcframework"

mkdir -p "$FRAMEWORKS_DIR"

install_from_dir() {
  rm -rf "$DEST"
  cp -R "$1" "$DEST"
  echo "==> installed $(basename "$1") as FRAMEWORK.xcframework"
}

# SPM caches manifest evaluation by CONTENT, so a freshly-arrived binary is
# invisible to the Package.swift probe until the cache is dropped.
clear_spm_cache() {
  local ephemeral="$PKG_DIR/../../ios/Flutter/ephemeral"
  if [[ -d "$ephemeral" ]]; then
    rm -rf "$ephemeral"
    echo "==> cleared Flutter SPM cache"
  fi
  echo
  echo "In Xcode, also run File > Packages > Reset Package Caches if it is open."
}

# --- local directory form --------------------------------------------------
if [[ $# -ge 1 ]]; then
  if [[ ! -d "$1" ]]; then
    echo "error: not a directory: $1" >&2
    exit 1
  fi
  install_from_dir "$1"
  clear_spm_cache
  exit 0
fi

# --- download form ---------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

URL="${VENDOR_URL:-}"
EXPECTED_SHA="${VENDOR_SHA256:-}"

if [[ -z "$URL" ]]; then
  cat >&2 <<'MSG'
error: no download URL.

  Either pass a local .xcframework directory, or create tool/sdk_source.env:

    VENDOR_URL=https://.../Vendor.xcframework.zip
    VENDOR_SHA256=<sha256 of that zip>

  sdk_source.env is gitignored — vendor URLs are often issued per customer.
MSG
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> downloading"
curl -fsSL --retry 3 "$URL" -o "$TMP_DIR/sdk.zip"

ACTUAL_SHA="$(shasum -a 256 "$TMP_DIR/sdk.zip" | cut -d' ' -f1)"
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "error: VENDOR_SHA256 is not set." >&2
  echo "       downloaded artifact hashes to: $ACTUAL_SHA" >&2
  echo "       verify that with the vendor, then pin it in sdk_source.env." >&2
  exit 1
fi
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "error: checksum mismatch" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi
echo "==> checksum ok"

unzip -q "$TMP_DIR/sdk.zip" -d "$TMP_DIR/unpacked"
XCFRAMEWORK="$(find "$TMP_DIR/unpacked" -maxdepth 3 -type d -name '*.xcframework' | head -1)"
if [[ -z "$XCFRAMEWORK" ]]; then
  echo "error: no .xcframework inside the archive" >&2
  exit 1
fi

install_from_dir "$XCFRAMEWORK"
clear_spm_cache
'''
    .replaceAll('PLUGIN', spec.pluginName)
    .replaceAll('FRAMEWORK', spec.iosFrameworkName ?? 'Vendor');

String fetchAndroidSh(BridgeSpec spec) => r'''
#!/usr/bin/env bash
#
# Fetch the vendor .aar into android/libs/.
#
# The binary is NOT committed. Prefer a Maven coordinate if the vendor offers
# one: a bare .aar carries no transitive dependency metadata, so every SDK it
# needs must be version-managed by hand in android/build.gradle.kts.
#
#   Usage:
#     tool/fetch_android_sdk.sh                       # tool/sdk_source.env
#     tool/fetch_android_sdk.sh /path/to/Vendor.aar   # local file
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS_DIR="$PKG_DIR/android/libs"
ENV_FILE="$PKG_DIR/tool/sdk_source.env"
DEST="$LIBS_DIR/AAR.aar"

mkdir -p "$LIBS_DIR"

# --- local file form -------------------------------------------------------
if [[ $# -ge 1 ]]; then
  if [[ ! -f "$1" ]]; then
    echo "error: no such file: $1" >&2
    exit 1
  fi
  cp "$1" "$DEST"
  echo "==> installed $(basename "$1") as AAR.aar"
  echo "    sha256: $(shasum -a 256 "$DEST" | cut -d' ' -f1)"
  echo
  echo "Record that hash — for a hand-delivered .aar it is the only evidence"
  echo "of WHICH build shipped."
  exit 0
fi

# --- download form ---------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

URL="${VENDOR_AAR_URL:-}"
EXPECTED_SHA="${VENDOR_AAR_SHA256:-}"

if [[ -z "$URL" ]]; then
  cat >&2 <<'MSG'
error: no .aar source.

  Either pass a local file, or create tool/sdk_source.env:

    VENDOR_AAR_URL=https://.../Vendor.aar
    VENDOR_AAR_SHA256=<sha256 of that file>
MSG
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> downloading"
curl -fsSL --retry 3 "$URL" -o "$TMP_DIR/sdk.aar"

ACTUAL_SHA="$(shasum -a 256 "$TMP_DIR/sdk.aar" | cut -d' ' -f1)"
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "error: VENDOR_AAR_SHA256 is not set." >&2
  echo "       downloaded artifact hashes to: $ACTUAL_SHA" >&2
  exit 1
fi
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "error: checksum mismatch" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi

cp "$TMP_DIR/sdk.aar" "$DEST"
echo "==> checksum ok, installed AAR.aar"
'''
    .replaceAll('AAR', spec.androidAarName ?? 'Vendor');

String gitignore(BridgeSpec spec) {
  final lines = <String>[
    '# Vendor binaries — fetched by tool/, never committed.',
    if (spec.hasIos) 'ios/${spec.pluginName}/Frameworks/*.xcframework/',
    if (spec.hasAndroid) 'android/libs/*.aar',
    '',
    '# Vendor download URLs are often issued per customer.',
    'tool/sdk_source.env',
    '',
    '.dart_tool/',
    'pubspec.lock',
    'build/',
  ];
  return '${lines.join('\n')}\n';
}
