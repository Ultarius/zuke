import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  for (final paths in [
    ['.', './'],
    ['apps/api', './apps//api/'],
    ['apps/api', r'apps\api'],
    ['apps/api', 'apps/temp/../api'],
  ]) {
    for (final sameTarget in [false, true]) {
      test('rejects conflicting $paths with sameTarget=$sameTarget', () {
        for (final order in [paths, paths.reversed.toList()]) {
          expect(
            () => ZukeConfig.fromYaml(_config(order, sameTarget: sameTarget)),
            throwsA(
              isA<InvalidWorkspaceConfigError>().having(
                (error) => error.toString(),
                'message',
                contains('conflicting owners'),
              ),
            ),
          );
        }
      });
    }
  }
  test('nested packages and distinct path prefixes remain valid', () {
    for (final paths in [
      ['.', 'a'],
      ['apps/api', 'apps/api/contracts'],
      ['a', 'ab'],
    ]) {
      expect(() => ZukeConfig.fromYaml(_config(paths)), returnsNormally);
    }
  });
  test('case-only collisions follow the host filesystem comparison policy', () {
    ZukeConfig read() => ZukeConfig.fromYaml(_config(['apps/API', 'apps/api']));
    expect(
      read,
      Platform.isWindows
          ? throwsA(isA<InvalidWorkspaceConfigError>())
          : returnsNormally,
    );
  });
}

String _config(List<String> paths, {bool sameTarget = false}) {
  Map<String, Object> package(int index) => {
    'id': 'package-$index',
    'path': paths[index],
    'roots': ['lib'],
  };
  Map<String, Object> target(List<Map<String, Object>> packages) => {
    'language': 'dart',
    'framework': 'flutter',
    'packages': packages,
  };
  return jsonEncode({
    'schemaVersion': 3,
    'targets': sameTarget
        ? {
            'app': target([package(0), package(1)]),
          }
        : {
            'first': target([package(0)]),
            'second': target([package(1)]),
          },
  });
}
