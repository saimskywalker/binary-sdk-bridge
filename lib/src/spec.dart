import 'package:path/path.dart' as p;

/// Everything the generator needs to emit one wrapper package.
///
/// Kept as a plain value object with its validation in [BridgeSpec.validate]
/// so the CLI and any future config-file front end share one definition of
/// what a legal spec is.
/// What the generator emits.
enum BridgeFlavor {
  /// A Flutter plugin: native wrappers plus the Dart API and plugin classes.
  flutter,

  /// The native wrappers only — an SPM package and a Gradle module with no
  /// Flutter dependency at all. For a plain iOS/Android app, or any other
  /// cross-platform runtime that can consume native modules.
  native;

  static BridgeFlavor? parse(String raw) => switch (raw.trim().toLowerCase()) {
        'flutter' => BridgeFlavor.flutter,
        'native' => BridgeFlavor.native,
        _ => null,
      };
}

class BridgeSpec {
  BridgeSpec({
    required this.pluginName,
    required this.organization,
    this.flavor = BridgeFlavor.flutter,
    this.iosFrameworkName,
    this.androidAarName,
    this.iosDeploymentTarget = '15.0',
    this.androidMinSdk = 24,
    this.androidCompileSdk = 36,
    this.javaVersion = 17,
    this.description,
  });

  final BridgeFlavor flavor;

  bool get isFlutter => flavor == BridgeFlavor.flutter;

  /// Package name, and the module name. `snake_case`.
  final String pluginName;

  /// Reverse-DNS prefix for the Android package, e.g. `com.example`.
  final String organization;

  /// Base name of the `.xcframework`, without the extension. Null skips iOS.
  final String? iosFrameworkName;

  /// Base name of the `.aar`, without the extension. Null skips Android.
  final String? androidAarName;

  final String iosDeploymentTarget;
  final int androidMinSdk;
  final int androidCompileSdk;
  final int javaVersion;
  final String? description;

  bool get hasIos => iosFrameworkName != null;
  bool get hasAndroid => androidAarName != null;

  /// `acme_ads` -> `AcmeAds`, used for the plugin class name.
  String get pluginClassName => pluginName
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();

  /// The Swift target that holds the vendor-facing code, kept free of any
  /// Flutter import so a plain iOS app can depend on it.
  String get kitName => '${pluginClassName}Kit';

  /// SPM product names are conventionally dashed; Flutter's own integration
  /// looks for the dashed spelling of the plugin name.
  String get iosProductName => pluginName.replaceAll('_', '-');

  String get androidPackage => '$organization.$pluginName';

  // Always `/` — [GeneratedFile.relativePath] is platform-independent, and
  // `path.joinAll` would inject `\` on Windows (#3 / Windows generation).
  String get androidPackagePath => p.posix.joinAll(androidPackage.split('.'));

  /// Method-channel name. The `_method` suffix is deliberate: Flutter's binary
  /// messenger keys handlers by name alone, so an EventChannel added later
  /// under the bare name would silently replace this handler. Reserving the
  /// bare name costs nothing.
  String get channelName => '$pluginName/${pluginName}_method';

  /// Swift compilation condition and Gradle source-set switch.
  String get sdkDefine => '${pluginName.toUpperCase()}_SDK';

  static final _snakeCase = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _reverseDns = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

  /// Binary names end up inside generated SHELL SCRIPTS, Swift string
  /// literals and Gradle files. Anything outside this set could break the
  /// generated file or, worse, execute — `Vendor\$(rm -rf ~)` in a shell
  /// script is not a hypothetical. Letters, digits, dot, dash, underscore
  /// covers every real framework name and nothing dangerous.
  static final _binaryName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// `15.0`, `13`, `16.4` — what `.iOS("…")` accepts.
  static final _version = RegExp(r'^\d+(\.\d+){0,2}$');

  /// Throws [FormatException] describing the first problem found.
  ///
  /// Validating here rather than at the point of use means a bad spec fails
  /// before a single file is written — a half-generated package is much worse
  /// to recover from than an error.
  void validate() {
    if (!_snakeCase.hasMatch(pluginName)) {
      throw FormatException(
        'plugin name must be lower_snake_case starting with a letter, '
        'got "$pluginName"',
      );
    }
    if (pluginName.endsWith('_')) {
      throw FormatException(
          'plugin name must not end with "_", got "$pluginName"');
    }
    if (!_reverseDns.hasMatch(organization)) {
      throw FormatException(
        'organization must be reverse-DNS like "com.example", '
        'got "$organization"',
      );
    }
    // Binary names: see _binaryName. Checked before anything is written, so a
    // dangerous value never reaches a file on disk.
    for (final (label, value) in [
      ('--ios-framework', iosFrameworkName),
      ('--android-aar', androidAarName),
    ]) {
      if (value == null) continue;
      if (!_binaryName.hasMatch(value)) {
        throw FormatException(
          '$label must be letters, digits, dot, dash or underscore '
          '(and start with a letter or digit), got "$value"',
        );
      }
      if (value.length > 100) {
        throw FormatException('$label is implausibly long (${value.length})');
      }
    }

    if (!_version.hasMatch(iosDeploymentTarget)) {
      throw FormatException(
        'iOS deployment target must look like "15.0", got '
        '"$iosDeploymentTarget"',
      );
    }

    // Ranges that produce a file Gradle will actually accept.
    if (androidMinSdk < 16 || androidMinSdk > 40) {
      throw FormatException('minSdk out of range: $androidMinSdk');
    }
    if (androidCompileSdk < androidMinSdk || androidCompileSdk > 60) {
      throw FormatException(
        'compileSdk ($androidCompileSdk) must be >= minSdk ($androidMinSdk) '
        'and plausible',
      );
    }
    if (![8, 11, 17, 21, 25].contains(javaVersion)) {
      throw FormatException(
        'java must be an LTS Gradle accepts (8, 11, 17, 21, 25), '
        'got $javaVersion',
      );
    }

    if (!hasIos && !hasAndroid) {
      throw const FormatException(
        'nothing to generate: pass --ios-framework, --android-aar, or both',
      );
    }
    // Dart reserves these; a package named after one cannot be imported.
    if (pluginName.length > 64) {
      throw FormatException(
          'plugin name is implausibly long (${pluginName.length})');
    }
    const reserved = {
      'test',
      'flutter',
      'dart',
      'build',
      'lib',
      'src',
      'ios',
      'android',
      'main',
      'core',
      'async',
      'io',
      'math',
    };
    if (reserved.contains(pluginName)) {
      throw FormatException('"$pluginName" is a reserved package name');
    }
  }
}
