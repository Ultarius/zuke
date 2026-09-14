import 'dart:convert';

/// Validates the machine-readable dependency graph emitted by `pub deps`.
///
/// This is intentionally independent from the lockfile parser. The lockfile
/// proves source provenance; this graph proves that Pub selected the exact
/// release tuple through the dependency graph it actually solved.
void assertHostedDependencyGraph(
  String encoded, {
  required Map<String, String> expectedVersions,
  required String host,
  Set<String>? requiredPackages,
}) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw const FormatException('pub deps --json did not return an object');
  }
  final rawPackages = decoded['packages'];
  if (rawPackages is! List) {
    throw const FormatException(
      'pub deps --json did not contain the expected package list',
    );
  }

  final packages = <String, String>{};
  for (final raw in rawPackages) {
    if (raw is! Map || raw['name'] is! String || raw['version'] is! String) {
      throw const FormatException(
        'pub deps --json contains a malformed package entry',
      );
    }
    final name = raw['name'] as String;
    if (packages.containsKey(name)) {
      throw FormatException('pub deps --json contains duplicate package $name');
    }
    packages[name] = raw['version'] as String;
  }

  final excludedRunner = host == 'flutter'
      ? 'zuke_runner'
      : 'zuke_runner_flutter';
  if (packages.containsKey(excludedRunner)) {
    throw FormatException(
      'pub deps resolved the opposite Zuke runner $excludedRunner',
    );
  }
  final required = requiredPackages ?? expectedVersions.keys.toSet();
  for (final name in required) {
    if (name == excludedRunner) continue;
    final expected = expectedVersions[name];
    if (expected == null) {
      throw FormatException(
        'Required hosted package $name is not in the release matrix',
      );
    }
    final actual = packages[name];
    if (actual != expected) {
      throw FormatException(
        'pub deps resolved $name to ${actual ?? 'missing'}, '
        'expected hosted matrix version $expected',
      );
    }
  }
  for (final name in packages.keys) {
    if (name == 'zuke' || name.startsWith('zuke_')) {
      final expected = expectedVersions[name];
      if (name == excludedRunner || expected == null) {
        throw FormatException(
          'pub deps resolved unexpected Zuke package $name',
        );
      }
      if (packages[name] != expected) {
        throw FormatException(
          'pub deps resolved $name to ${packages[name]}, '
          'expected hosted matrix version $expected',
        );
      }
    }
  }
}
