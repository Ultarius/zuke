import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/release_matrix.dart';
import '../../../tool/src/hosted_consumer_fixture.dart';

void main() {
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
      useFlutter: false,
    ).render();

    final pubspec = File(
      destination.path + Platform.pathSeparator + 'pubspec.yaml',
    ).readAsStringSync();
    final config = File(
      destination.path + Platform.pathSeparator + 'zuke.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('zuke_core: 0.3.0'));
    expect(pubspec, isNot(contains('{{')));
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
