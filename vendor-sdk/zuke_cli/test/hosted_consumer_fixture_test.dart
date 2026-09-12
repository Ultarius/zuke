import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/check_hosted_consumer.dart';
import '../../../tool/release_matrix.dart';
import '../../../tool/src/hosted_consumer_fixture.dart';

void main() {
  test('rejects a fixture nested under a declared Pub workspace', () {
    final root = Directory.systemTemp.createTempSync(
      'zuke-hosted-workspace-test-',
    );
    final fixture = Directory('${root.path}${Platform.pathSeparator}fixture')
      ..createSync(recursive: true);
    File('${root.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
      '''
name: parent_workspace
workspace:
  - fixture
''',
    );
    addTearDown(() => root.deleteSync(recursive: true));

    expect(isInsidePubWorkspace(fixture), isTrue);
  });

  test('renders an exact, standalone consumer from the release matrix', () {
    final root = _findRoot(Directory.current);
    final matrix = readReleaseMatrix(root);
    final destination = Directory.systemTemp.createTempSync(
      'zuke-hosted-fixture-test-',
    );
    addTearDown(() => destination.deleteSync(recursive: true));

    HostedConsumerFixture(
      templateRoot: Directory(
        root.path +
            Platform.pathSeparator +
            'tool' +
            Platform.pathSeparator +
            'fixtures' +
            Platform.pathSeparator +
            'hosted_consumer' +
            Platform.pathSeparator +
            'template',
      ),
      destination: destination,
      matrix: matrix,
      hostedPackages: const ['zuke_core'],
      host: 'dart',
    ).render();

    final pubspec = File(
      destination.path + Platform.pathSeparator + 'pubspec.yaml',
    ).readAsStringSync();
    final config = File(
      destination.path + Platform.pathSeparator + 'zuke.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('zuke_core: 0.4.0'));
    expect(pubspec, isNot(contains('{{')));
    expect(pubspec, isNot(contains('dependency_overrides:')));
    expect(pubspec, isNot(contains('resolution: workspace')));
    expect(pubspec, isNot(contains('path:')));
    expect(pubspec, isNot(contains('git:')));
    final parsedPubspec = loadYaml(pubspec) as YamlMap;
    expect(
      (parsedPubspec['dependencies'] as YamlMap).containsKey('zuke_cli'),
      isFalse,
    );
    expect(
      (parsedPubspec['dev_dependencies'] as YamlMap)['zuke_cli'],
      equals('0.5.0'),
    );
    expect(config, contains('dart-source-package-v1'));
    expect(config, contains('kind: test'));
    expect(config, contains('schemaVersion: 3'));
    expect(
      File(
        destination.path +
            Platform.pathSeparator +
            'lib' +
            Platform.pathSeparator +
            'hosted_consumer.dart',
      ).readAsStringSync(),
      contains("src/generated/feat_hosted_001_contracts.g.dart"),
    );
    expect(
      File(
        destination.path +
            Platform.pathSeparator +
            'test' +
            Platform.pathSeparator +
            'consumer_test.dart',
      ).readAsStringSync(),
      contains('FeatHosted001Scenarios.all.single'),
    );
  });

  test('renders a Flutter capsule without a direct package:test dependency', () {
    final root = _findRoot(Directory.current);
    final matrix = readReleaseMatrix(root);
    final destination = Directory.systemTemp.createTempSync(
      'zuke-hosted-flutter-fixture-test-',
    );
    addTearDown(() => destination.deleteSync(recursive: true));

    HostedConsumerFixture(
      templateRoot: Directory(
        '${root.path}${Platform.pathSeparator}tool${Platform.pathSeparator}'
        'fixtures${Platform.pathSeparator}hosted_consumer${Platform.pathSeparator}'
        'template',
      ),
      destination: destination,
      matrix: matrix,
      hostedPackages: const ['zuke_core'],
      host: 'flutter',
    ).render();

    final pubspec = File(
      '${destination.path}${Platform.pathSeparator}pubspec.yaml',
    ).readAsStringSync();
    final test = File(
      '${destination.path}${Platform.pathSeparator}test${Platform.pathSeparator}'
      'consumer_test.dart',
    ).readAsStringSync();
    expect(pubspec, contains('flutter_test:'));
    expect(pubspec, isNot(contains('  test:')));
    expect(pubspec, isNot(contains('dependency_overrides:')));
    expect(pubspec, isNot(contains('resolution: workspace')));
    expect(test, contains('zuke_runner_flutter'));
    expect(test, contains('zukeTestWidgets'));
  });
}

Directory _findRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File(
      current.path +
          Platform.pathSeparator +
          'docs' +
          Platform.pathSeparator +
          'release-matrix.yaml',
    ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the Zuke workspace root');
    }
    current = parent;
  }
}
