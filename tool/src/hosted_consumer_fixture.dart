import 'dart:io';

import '../release_matrix.dart';

/// Renders the clean-room consumer used for publication certification.
final class HostedConsumerFixture {
  const HostedConsumerFixture({
    required this.templateRoot,
    required this.destination,
    required this.matrix,
    required this.hostedPackages,
    required this.host,
  });

  final Directory templateRoot;
  final Directory destination;
  final ReleaseMatrix matrix;
  final List<String> hostedPackages;

  /// The host is explicit so certification never changes its dependency
  /// graph based on whichever SDK happens to be installed.
  final String host;

  void render() {
    if (destination.existsSync() && destination.listSync().isNotEmpty) {
      throw StateError(
        'Hosted consumer destination must be empty: ' + destination.path,
      );
    }
    destination.createSync(recursive: true);

    if (!const {'dart', 'flutter'}.contains(host)) {
      throw FormatException('Unsupported hosted-consumer host: $host');
    }
    if (host == 'flutter' && !matrix.flutterCertification.isConfigured) {
      throw const FormatException(
        'Release matrix does not declare a hosted Flutter certification band',
      );
    }

    final variables = <String, String>{
      'DART_SDK': _requiredSdk('dart'),
      'PACKAGE_DEPENDENCIES': _dependencies(),
      'CLI_DEPENDENCY': _cliDependency(),
      'TEST_DEPENDENCY': host == 'dart'
          ? "  test: '${_testConstraint()}'\n"
          : '',
      'FLUTTER_DEPENDENCY': host == 'flutter'
          ? '  flutter_test:\n    sdk: flutter\n'
          : '',
      'RUNNER_IMPORT': host == 'flutter'
          ? 'package:zuke_runner_flutter/zuke_runner_flutter.dart'
          : 'package:zuke_runner/zuke_runner.dart',
      'TEST_IMPORT': host == 'flutter'
          ? 'package:flutter_test/flutter_test.dart'
          : 'package:test/test.dart',
      'TEST_CALL': host == 'flutter' ? 'zukeTestWidgets' : 'zukeTest',
      'TEST_BODY': host == 'flutter'
          ? '(tester) async => expect(add(2, 3), 5)'
          : '() => expect(add(2, 3), 5)',
      'FRAMEWORK': host == 'flutter' ? 'flutter' : 'dart',
      'RUNNER_EXECUTABLE': host == 'flutter' ? 'flutter' : 'dart',
      'SOURCE_COMPATIBILITY_ID':
          matrix.compatibilityIds['dart-source'] ??
          (throw const FormatException(
            'Release matrix is missing dart-source compatibility ID',
          )),
      'RUNNER_COMPATIBILITY_ID':
          matrix.compatibilityIds[host == 'flutter'
              ? 'runner-flutter'
              : 'runner-dart'] ??
          (throw FormatException(
            'Release matrix is missing ${host}-runner compatibility ID',
          )),
    };

    _renderText('pubspec.yaml.tmpl', 'pubspec.yaml', variables);
    _renderText('zuke.yaml.tmpl', 'zuke.yaml', variables);
    _renderText(
      'specs/features/consumer.feature',
      'specs/features/consumer.feature',
      variables,
    );
    _renderText(
      'specs/epics/EPIC-HOSTED-001.yaml',
      'specs/epics/EPIC-HOSTED-001.yaml',
      variables,
    );
    _renderText('lib/calculator.dart', 'lib/calculator.dart', variables);
    _renderText(
      'lib/hosted_consumer.dart',
      'lib/hosted_consumer.dart',
      variables,
    );
    _renderText(
      'test/consumer_test.dart.tmpl',
      'test/consumer_test.dart',
      variables,
    );
  }

  String _requiredSdk(String name) {
    final value = matrix.sdk[name];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Release matrix sdk.' + name + ' is missing');
    }
    return value;
  }

  String _dependencies() {
    final values = <String>[];
    final runner = host == 'flutter' ? 'zuke_runner_flutter' : 'zuke_runner';
    final requested =
        <String>{
            ...hostedPackages,
            'zuke',
            'zuke_annotations',
            'zuke_core',
            'zuke_frontend',
            runner,
          }
          ..remove('zuke_cli')
          ..remove(host == 'flutter' ? 'zuke_runner' : 'zuke_runner_flutter');
    final ordered = requested.toList()..sort();
    for (final package in ordered) {
      final release = matrix.packages[package];
      if (release == null) {
        throw FormatException(
          'Package is not in the release matrix: ' + package,
        );
      }
      values.add('  ' + package + ': ' + release.version);
    }
    return values.join('\n') + '\n';
  }

  String _cliDependency() {
    final release = matrix.packages['zuke_cli'];
    if (release == null) {
      throw const FormatException(
        'Package is not in the release matrix: zuke_cli',
      );
    }
    return '  zuke_cli: ${release.version}\n';
  }

  String _testConstraint() {
    final value = matrix.sdk['test'];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Release matrix sdk.test is missing');
    }
    final match = RegExp(r'^(\d+)\.(\d+)\.x$').firstMatch(value.trim());
    if (match == null) {
      throw FormatException(
        'Release matrix sdk.test must use a major.minor.x band: $value',
      );
    }
    final major = match.group(1)!;
    final minor = int.parse(match.group(2)!);
    return ">=$major.$minor.0 <$major.${minor + 1}.0";
  }

  void _renderText(
    String templatePath,
    String outputPath,
    Map<String, String> variables,
  ) {
    final source = File(
      templateRoot.path +
          Platform.pathSeparator +
          templatePath.replaceAll('/', Platform.pathSeparator),
    );
    if (!source.existsSync()) {
      throw StateError('Missing hosted-consumer template: ' + source.path);
    }
    var content = source.readAsStringSync();
    for (final entry in variables.entries) {
      content = content.replaceAll('{{' + entry.key + '}}', entry.value);
    }
    final unresolved = RegExp(r'\{\{[A-Z0-9_]+\}\}').firstMatch(content);
    if (unresolved != null) {
      throw StateError(
        'Unresolved hosted-consumer template variable: ' +
            unresolved.group(0).toString(),
      );
    }
    final destinationFile = File(
      destination.path +
          Platform.pathSeparator +
          outputPath.replaceAll('/', Platform.pathSeparator),
    );
    destinationFile.parent.createSync(recursive: true);
    destinationFile.writeAsStringSync(content);
  }
}
