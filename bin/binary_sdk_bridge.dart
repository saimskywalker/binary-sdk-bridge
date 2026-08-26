import 'dart:io';

import 'package:args/args.dart';
import 'package:binary_sdk_bridge/binary_sdk_bridge.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('name',
        abbr: 'n', help: 'Plugin package name (lower_snake_case).')
    ..addOption('org', abbr: 'o', help: 'Reverse-DNS prefix, e.g. com.example.')
    ..addOption(
      'ios-framework',
      help: 'Base name of the .xcframework, without the extension. '
          'Omit to skip iOS.',
    )
    ..addOption(
      'android-aar',
      help:
          'Base name of the .aar, without the extension. Omit to skip Android.',
    )
    ..addOption(
      'flavor',
      defaultsTo: 'flutter',
      allowed: ['flutter', 'native'],
      help: 'flutter = full plugin (Dart API + plugin classes).\n'
          'native  = SPM package + Gradle module only, no Flutter.',
    )
    ..addOption('out',
        defaultsTo: '.', help: 'Directory to create the package in.')
    ..addOption('description', help: 'Package description.')
    ..addOption('ios-target',
        defaultsTo: '15.0', help: 'iOS deployment target.')
    ..addOption('min-sdk', defaultsTo: '24', help: 'Android minSdk.')
    ..addOption('compile-sdk', defaultsTo: '36', help: 'Android compileSdk.')
    ..addOption('java', defaultsTo: '17', help: 'Java/jvmTarget version.')
    ..addFlag('force',
        help: 'Overwrite an existing package directory.', negatable: false)
    ..addFlag('dry-run',
        help: 'List the files that would be written.', negatable: false)
    ..addFlag('help', abbr: 'h', help: 'Show this usage.', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    _fail(e.message, parser);
    return;
  }

  if (args.flag('help') || arguments.isEmpty) {
    stdout.writeln(_usage(parser));
    return;
  }

  final name = args.option('name');
  final org = args.option('org');
  if (name == null || org == null) {
    _fail('--name and --org are both required.', parser);
    return;
  }

  // Parsed defensively: `int.parse` on a bad flag threw an unhandled
  // FormatException and dumped a Dart stack trace at the user, which reads as
  // a crash rather than as "you typed that wrong".
  final int? minSdk = int.tryParse(args.option('min-sdk')!);
  final int? compileSdk = int.tryParse(args.option('compile-sdk')!);
  final int? java = int.tryParse(args.option('java')!);
  for (final (flag, value) in [
    ('--min-sdk', minSdk),
    ('--compile-sdk', compileSdk),
    ('--java', java),
  ]) {
    if (value == null) {
      _fail('$flag must be a whole number.', parser);
      return;
    }
  }

  final flavor = BridgeFlavor.parse(args.option('flavor')!);
  if (flavor == null) {
    _fail('--flavor must be "flutter" or "native".', parser);
    return;
  }

  final spec = BridgeSpec(
    pluginName: name,
    organization: org,
    flavor: flavor,
    iosFrameworkName: args.option('ios-framework'),
    androidAarName: args.option('android-aar'),
    iosDeploymentTarget: args.option('ios-target')!,
    androidMinSdk: minSdk!,
    androidCompileSdk: compileSdk!,
    javaVersion: java!,
    description: args.option('description'),
  );

  final BridgeGenerator generator;
  try {
    generator = BridgeGenerator(spec);
  } on FormatException catch (e) {
    _fail(e.message, parser);
    return;
  }

  if (args.flag('dry-run')) {
    stdout.writeln('Would create ${spec.pluginName}/ with:');
    for (final file in generator.plan()) {
      stdout.writeln(
          '  ${file.relativePath}${file.executable ? '  (executable)' : ''}');
    }
    return;
  }

  final Directory root;
  try {
    root = generator.write(args.option('out')!, force: args.flag('force'));
  } on StateError catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 1;
    return;
  }

  stdout
    ..writeln('Created ${root.path}')
    ..writeln()
    ..writeln('Next:')
    ..writeln('  1. Add it to your app: '
        '${spec.pluginName}: {path: ${root.path}}')
    ..writeln('  2. Drop the vendor binary in with tool/fetch_*.sh')
    ..writeln('  3. Fill in the TODO in the bridge — that is the only place '
        'the vendor API appears');
}

String _usage(ArgParser parser) => '''
binary-sdk-bridge — wrap a closed-source binary SDK as a Flutter plugin.

Usage:
  binary-sdk-bridge --name <plugin> --org <com.example> [options]

Example:
  binary-sdk-bridge \\
    --name acme_ads --org com.example \\
    --ios-framework AcmeSDK --android-aar AcmeSDK \\
    --out packages

Options:
${parser.usage}''';

void _fail(String message, ArgParser parser) {
  stderr
    ..writeln('error: $message')
    ..writeln()
    ..writeln(_usage(parser));
  exitCode = 64; // EX_USAGE
}
