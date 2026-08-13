import 'dart:io';

import '../release_matrix.dart';

/// Renders the clean-room consumer used for publication certification.
final class HostedConsumerFixture {
  const HostedConsumerFixture({
    required this.templateRoot,
    required this.destination,
    required this.matrix,
    required this.hostedPackages,
    required this.useFlutter,
  });

  final Directory templateRoot;
  final Directory destination;
  final ReleaseMatrix matrix;
  final List<String> hostedPackages;
  final bool useFlutter;

  void render() {
    if (destination.existsSync() && destination.listSync().isNotEmpty) {
      throw StateError(
        'Hosted consumer destination must be empty: ' + destination.path,
      );
    }
    destination.createSync(recursive: true);

    final variables = <String, String>{
      'DART_SDK': _requiredSdk('dart'),
      'PACKAGE_DEPENDENCIES': _dependencies(),
      'FLUTTER_DEPENDENCY': useFlutter
          ? '  flutter_test:\n    sdk: flutter\n'
          : '',
      'SOURCE_COMPATIBILITY_ID':
          matrix.compatibilityIds['dart-source'] ??
          (throw const FormatException(
            'Release matrix is missing dart-source compatibility ID',
          )),
      'RUNNER_COMPATIBILITY_ID': 'hosted-consumer-runner-v1',
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
    for (final package in hostedPackages) {
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
