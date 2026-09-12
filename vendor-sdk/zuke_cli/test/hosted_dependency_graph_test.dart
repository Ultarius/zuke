import 'dart:convert';

import 'package:test/test.dart';

import '../../../tool/src/hosted_dependency_graph.dart';

void main() {
  const expected = {
    'zuke': '0.4.0',
    'zuke_annotations': '0.4.0',
    'zuke_cli': '0.5.0',
    'zuke_runner': '0.4.0',
    'zuke_runner_flutter': '0.4.0',
  };

  String graph(Iterable<Map<String, String>> packages) =>
      jsonEncode({'packages': packages});

  test('accepts the exact Dart tuple and excludes the Flutter runner', () {
    assertHostedDependencyGraph(
      graph([
        {'name': 'zuke', 'version': '0.4.0'},
        {'name': 'zuke_annotations', 'version': '0.4.0'},
        {'name': 'zuke_cli', 'version': '0.5.0'},
        {'name': 'zuke_runner', 'version': '0.4.0'},
        {'name': 'http', 'version': '1.0.0'},
      ]),
      expectedVersions: expected,
      host: 'dart',
    );
  });

  test('accepts the exact Flutter tuple and excludes the Dart runner', () {
    assertHostedDependencyGraph(
      graph([
        {'name': 'zuke', 'version': '0.4.0'},
        {'name': 'zuke_annotations', 'version': '0.4.0'},
        {'name': 'zuke_cli', 'version': '0.5.0'},
        {'name': 'zuke_runner_flutter', 'version': '0.4.0'},
        {'name': 'flutter_test', 'version': '0.0.0'},
      ]),
      expectedVersions: expected,
      host: 'flutter',
    );
  });

  test('rejects a wrong or missing matrix package', () {
    expect(
      () => assertHostedDependencyGraph(
        graph([
          {'name': 'zuke', 'version': '0.3.0'},
          {'name': 'zuke_annotations', 'version': '0.4.0'},
          {'name': 'zuke_cli', 'version': '0.5.0'},
          {'name': 'zuke_runner', 'version': '0.4.0'},
        ]),
        expectedVersions: expected,
        host: 'dart',
      ),
      throwsFormatException,
    );
  });

  test('rejects unexpected Zuke packages and duplicate entries', () {
    expect(
      () => assertHostedDependencyGraph(
        graph([
          {'name': 'zuke', 'version': '0.4.0'},
          {'name': 'zuke_annotations', 'version': '0.4.0'},
          {'name': 'zuke_cli', 'version': '0.5.0'},
          {'name': 'zuke_runner', 'version': '0.4.0'},
          {'name': 'zuke_private', 'version': '0.1.0'},
        ]),
        expectedVersions: expected,
        host: 'dart',
      ),
      throwsFormatException,
    );
    expect(
      () => assertHostedDependencyGraph(
        graph([
          {'name': 'zuke', 'version': '0.4.0'},
          {'name': 'zuke', 'version': '0.4.0'},
        ]),
        expectedVersions: expected,
        host: 'dart',
      ),
      throwsFormatException,
    );
  });

  test('rejects the opposite host runner even when it is in the matrix', () {
    expect(
      () => assertHostedDependencyGraph(
        graph([
          {'name': 'zuke', 'version': '0.4.0'},
          {'name': 'zuke_annotations', 'version': '0.4.0'},
          {'name': 'zuke_cli', 'version': '0.5.0'},
          {'name': 'zuke_runner', 'version': '0.4.0'},
          {'name': 'zuke_runner_flutter', 'version': '0.4.0'},
        ]),
        expectedVersions: expected,
        host: 'dart',
      ),
      throwsFormatException,
    );
  });

  test('allows optional matrix packages to remain absent', () {
    assertHostedDependencyGraph(
      graph([
        {'name': 'zuke', 'version': '0.4.0'},
        {'name': 'zuke_runner', 'version': '0.4.0'},
      ]),
      expectedVersions: {...expected, 'zuke_http_runtime': '0.1.1'},
      requiredPackages: const {'zuke', 'zuke_runner'},
      host: 'dart',
    );
  });

  test('rejects malformed Pub JSON instead of guessing', () {
    expect(
      () => assertHostedDependencyGraph(
        jsonEncode({
          'packages': {'zuke': '0.4.0'},
        }),
        expectedVersions: expected,
        host: 'dart',
      ),
      throwsFormatException,
    );
  });
}
