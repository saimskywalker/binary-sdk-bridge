import 'dart:io';

import 'package:path/path.dart' as p;

import 'spec.dart';
import 'templates/android_templates.dart' as android;
import 'templates/dart_templates.dart' as dart;
import 'templates/ios_templates.dart' as ios;
import 'templates/script_templates.dart' as scripts;

/// One file the generator intends to write.
class GeneratedFile {
  const GeneratedFile(this.relativePath, this.contents, {this.executable = false});

  /// Path relative to the package root, always with `/` separators.
  final String relativePath;
  final String contents;
  final bool executable;
}

/// Turns a [BridgeSpec] into the set of files that make up a wrapper package.
///
/// [plan] is deliberately pure — it returns the file set without touching the
/// filesystem, so tests can assert on the output and the CLI can offer a dry
/// run without a second code path.
class BridgeGenerator {
  BridgeGenerator(this.spec) {
    spec.validate();
  }

  final BridgeSpec spec;

  List<GeneratedFile> plan() {
    final files = <GeneratedFile>[
      GeneratedFile('pubspec.yaml', dart.pubspecYaml(spec)),
      GeneratedFile('.gitignore', scripts.gitignore(spec)),
      GeneratedFile('lib/${spec.pluginName}.dart', dart.apiDart(spec)),
      GeneratedFile('lib/src/vendor_state.dart', dart.stateDart(spec)),
      GeneratedFile('test/${spec.pluginName}_test.dart', dart.testDart(spec)),
    ];

    if (spec.hasIos) {
      final root = 'ios/${spec.pluginName}';
      files.addAll([
        GeneratedFile('$root/Package.swift', ios.packageSwift(spec)),
        GeneratedFile(
          '$root/Sources/${spec.kitName}/${spec.kitName}.swift',
          ios.bridgeSwift(spec),
        ),
        GeneratedFile(
          '$root/Sources/${spec.pluginName}/${spec.pluginClassName}Plugin.swift',
          ios.pluginSwift(spec),
        ),
        // Keeps the directory in git while its contents are ignored, so
        // the Package.swift probe always has a stable path to look at.
        GeneratedFile('$root/Frameworks/.gitkeep', ''),
        GeneratedFile(
          'tool/fetch_ios_sdk.sh',
          scripts.fetchIosSh(spec),
          executable: true,
        ),
      ]);
    }

    if (spec.hasAndroid) {
      const src = 'android/src';
      final pkgPath = spec.androidPackagePath;
      files.addAll([
        GeneratedFile('android/build.gradle.kts', android.buildGradleKts(spec)),
        GeneratedFile('$src/main/AndroidManifest.xml', android.androidManifest(spec)),
        GeneratedFile(
          '$src/main/kotlin/$pkgPath/VendorState.kt',
          android.stateKotlin(spec),
        ),
        GeneratedFile(
          '$src/main/kotlin/$pkgPath/${spec.pluginClassName}Plugin.kt',
          android.pluginKotlin(spec),
        ),
        GeneratedFile(
          '$src/noSdk/kotlin/$pkgPath/sdk/VendorBridge.kt',
          android.bridgeKotlinNoSdk(spec),
        ),
        GeneratedFile(
          '$src/withSdk/kotlin/$pkgPath/sdk/VendorBridge.kt',
          android.bridgeKotlinWithSdk(spec),
        ),
        GeneratedFile('android/libs/.gitkeep', ''),
        GeneratedFile(
          'tool/fetch_android_sdk.sh',
          scripts.fetchAndroidSh(spec),
          executable: true,
        ),
      ]);
    }

    return files;
  }

  /// Writes [plan] under `[outputDir]/<pluginName>`.
  ///
  /// Refuses to touch an existing directory unless [force] is set: silently
  /// overwriting a package someone has since edited is the one failure mode
  /// with no undo.
  Directory write(String outputDir, {bool force = false}) {
    final packageRoot = Directory(p.join(outputDir, spec.pluginName));
    if (packageRoot.existsSync() && !force) {
      throw StateError(
        '${packageRoot.path} already exists. Pass --force to overwrite it.',
      );
    }

    for (final file in plan()) {
      final target = File(p.join(packageRoot.path, p.joinAll(file.relativePath.split('/'))));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.contents);
      if (file.executable) {
        // Dart has no chmod; the shell one is universal on the platforms that
        // can build these packages at all.
        Process.runSync('chmod', ['+x', target.path]);
      }
    }

    return packageRoot;
  }
}
