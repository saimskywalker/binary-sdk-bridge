import 'package:path/path.dart' as p;

/// Everything the generator needs to emit one wrapper package.
///
/// Kept as a plain value object with its validation in [BridgeSpec.validate]
/// so the CLI and any future config-file front end share one definition of
/// what a legal spec is.
class BridgeSpec {
  BridgeSpec({
    required this.pluginName,
    required this.organization,
    this.iosFrameworkName,
    this.androidAarName,
    this.iosDeploymentTarget = '15.0',
    this.androidMinSdk = 24,
    this.androidCompileSdk = 36,
    this.javaVersion = 17,
    this.description,
  });

  /// Dart package name, and the Flutter plugin name. `snake_case`.
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

  /// `anymanager_ads` -> `AnymanagerAds`, used for the plugin class name.
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

  String get androidPackagePath => p.joinAll(androidPackage.split('.'));

  /// Method-channel name. The `_method` suffix is deliberate: Flutter's binary
  /// messenger keys handlers by name alone, so an EventChannel added later
  /// under the bare name would silently replace this handler. Reserving the
  /// bare name costs nothing.
  String get channelName => '$pluginName/${pluginName}_method';

  /// Swift compilation condition and Gradle source-set switch.
  String get sdkDefine => '${pluginName.toUpperCase()}_SDK';

  static final _snakeCase = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _reverseDns = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

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
    if (!hasIos && !hasAndroid) {
      throw const FormatException(
        'nothing to generate: pass --ios-framework, --android-aar, or both',
      );
    }
    // Dart reserves these; a package named after one cannot be imported.
    const reserved = {'test', 'flutter', 'dart', 'build'};
    if (reserved.contains(pluginName)) {
      throw FormatException('"$pluginName" is a reserved package name');
    }
  }
}
