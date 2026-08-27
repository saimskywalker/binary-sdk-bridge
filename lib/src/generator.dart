import 'dart:io';

import 'package:path/path.dart' as p;

import 'spec.dart';
import 'templates/android_templates.dart' as android;
import 'templates/dart_templates.dart' as dart;
import 'templates/ios_templates.dart' as ios;
import 'templates/script_templates.dart' as scripts;

/// One file the generator intends to write.
class GeneratedFile {
  const GeneratedFile(this.relativePath, this.contents,
      {this.executable = false});

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
      GeneratedFile('.gitignore', scripts.gitignore(spec)),
      // The Dart layer exists only for the Flutter flavour. A native consumer
      // gets the SPM package and the Gradle module and nothing else — no
      // pubspec, no plugin class, nothing that drags Flutter in.
      if (spec.isFlutter) ...[
        GeneratedFile('pubspec.yaml', dart.pubspecYaml(spec)),
        GeneratedFile('lib/${spec.pluginName}.dart', dart.apiDart(spec)),
        GeneratedFile('lib/src/vendor_state.dart', dart.stateDart(spec)),
        GeneratedFile('test/${spec.pluginName}_test.dart', dart.testDart(spec)),
      ],
    ];

    if (spec.hasIos) {
      final root = 'ios/${spec.pluginName}';
      files.addAll([
        GeneratedFile('$root/Package.swift', ios.packageSwift(spec)),
        GeneratedFile(
          '$root/Sources/${spec.kitName}/${spec.kitName}.swift',
          ios.bridgeSwift(spec),
        ),
        if (spec.isFlutter)
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
        GeneratedFile(
            '$src/main/AndroidManifest.xml', android.androidManifest(spec)),
        GeneratedFile(
          '$src/main/kotlin/$pkgPath/VendorState.kt',
          android.stateKotlin(spec),
        ),
        if (spec.isFlutter)
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

  /// What to do with the package that was just written, as printed lines.
  ///
  /// Flavour-specific because the native flavour emits no `pubspec.yaml`: the
  /// pub path-dependency line is not something a native consumer can act on,
  /// and following it puts an unresolvable dependency in their app.
  List<String> nextSteps(String packagePath) {
    final lines = <String>[];
    var number = 1;
    void step(String text) => lines.add('  ${number++}. $text');
    void detail(String text) => lines.add('     $text');

    if (spec.isFlutter) {
      step('Add it to your app: ${spec.pluginName}: {path: $packagePath}');
    } else {
      step('Add it to your app — this flavour has no pubspec:');
      if (spec.hasIos) {
        detail('iOS     — add $packagePath/ios/${spec.pluginName} as a local '
            'Swift package');
      }
      if (spec.hasAndroid) {
        detail('Android — include $packagePath/android as a Gradle module');
      }
    }
    step('Drop the vendor binary in with tool/fetch_*.sh');
    step('Fill in the TODO in the bridge — that is the only place the vendor '
        'API appears');

    return lines;
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
      final target = File(
          p.join(packageRoot.path, p.joinAll(file.relativePath.split('/'))));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.contents);
      if (file.executable) {
        _markExecutable(target);
      }
    }

    return packageRoot;
  }
}

/// Sets the owner-execute bit on [file].
///
/// Skipped on Windows: there is no `chmod`, and
/// `Process.runSync` throws [ProcessException] when the executable is
/// missing rather than returning a non-zero exit code — which used to abort
/// the write loop mid-package (see #3). The execute bit has no meaning on
/// NTFS anyway; [GeneratedFile.executable] still records intent for dry-run
/// and tests.
void _markExecutable(File file) {
  if (Platform.isWindows) return;

  final result = Process.runSync('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    final stderr = (result.stderr as String).trim();
    throw ProcessException(
      'chmod',
      ['+x', file.path],
      stderr.isEmpty ? 'exit code ${result.exitCode}' : stderr,
      result.exitCode,
    );
  }
}
