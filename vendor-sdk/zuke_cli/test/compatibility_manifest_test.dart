import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/build_compatibility_manifest.dart';

void main() {
  Map<String, Object?> report({
    required String host,
    required String platform,
    bool passed = true,
  }) => {
    'kind': 'zuke.hosted-consumer-certification',
    'host': host,
    'platform': platform,
    'passed': passed,
    'packageVersions': {'zuke': '0.4.0', 'zuke_cli': '0.5.0'},
    'compatibilityIds': {'dart-source': 'dart-source-package-v1'},
    'sdk': {'dart': '3.10.0', if (host == 'flutter') 'flutter': '3.44.8'},
    'resolvedPackages': {'zuke': 'hosted:0.4.0'},
    'lockDigests': {'pullRequest': 'abc'},
  };

  test('builds a sorted manifest from certification evidence', () {
    final manifest = buildCompatibilityManifest([
      report(host: 'flutter', platform: 'windows'),
      report(host: 'dart', platform: 'linux'),
    ]);
    final encoded = encodeCompatibilityManifest(manifest);
    expect(encoded, contains('schemaVersion: 1'));
    expect(encoded, contains('certifications:'));
    expect(
      encoded.indexOf("host: 'dart'"),
      lessThan(encoded.indexOf("host: 'flutter'")),
    );
    expect(encoded, contains("status: 'pass'"));
    final parsed = loadYaml(encoded) as YamlMap;
    expect(parsed['schemaVersion'], 1);
    expect((parsed['certifications'] as YamlList).length, 2);
  });

  test('keeps failed certification status instead of hiding it', () {
    final manifest = buildCompatibilityManifest([
      report(host: 'dart', platform: 'linux', passed: false),
    ]);
    expect(encodeCompatibilityManifest(manifest), contains("status: 'fail'"));
  });

  test('does not copy raw command output into the manifest', () {
    final source = report(host: 'dart', platform: 'linux')
      ..['commands'] = [
        {'stdout': 'authorization: bearer secret-token'},
      ];
    final encoded = encodeCompatibilityManifest(
      buildCompatibilityManifest([source]),
    );
    expect(encoded, isNot(contains('secret-token')));
    expect(encoded, isNot(contains('authorization')));
  });

  test('rejects duplicate tuples and mixed release tuples', () {
    expect(
      () => buildCompatibilityManifest([
        report(host: 'dart', platform: 'linux'),
        report(host: 'dart', platform: 'linux'),
      ]),
      throwsFormatException,
    );
    final other = report(host: 'dart', platform: 'windows');
    (other['packageVersions'] as Map)['zuke'] = '0.5.0';
    expect(
      () => buildCompatibilityManifest([
        report(host: 'dart', platform: 'linux'),
        other,
      ]),
      throwsFormatException,
    );
  });

  test('compares release tuple maps independent of JSON key order', () {
    final reordered = report(host: 'dart', platform: 'windows')
      ..['packageVersions'] = {'zuke_cli': '0.5.0', 'zuke': '0.4.0'}
      ..['compatibilityIds'] = {'dart-source': 'dart-source-package-v1'};
    expect(
      () => buildCompatibilityManifest([
        report(host: 'dart', platform: 'linux'),
        reordered,
      ]),
      returnsNormally,
    );
  });
}
