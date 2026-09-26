/// Scans shipped Dart sources for the diagnostic codes they declare.
///
/// Two repository contracts depend on the same set of codes: the conformance
/// test (every declared code is registered in `docs/diagnostic-registry.json`)
/// and the CLI remediation test (every declared code resolves to a remedy).
/// The scan lives in one place so those scopes cannot drift apart again.
library;

import 'dart:io';

/// Every diagnostic code declared under [roots].
///
/// A code counts wherever a bare `ZUKE-…`/`ZK-…` literal appears. That covers
/// `code:`, `diagnosticCode:`, fallback values, and thrown messages without
/// depending on which key a call site happens to use.
///
/// Package test trees are skipped (see [isPackageTestSource]): their fixtures
/// and adversarial cases use fake codes that must not be demanded of the
/// registry or the remediation table.
Set<String> scanDeclaredDiagnosticCodes(Iterable<Directory> roots) {
  final pattern = RegExp(r'(?:ZUKE|ZK)-[A-Z0-9]+(?:-[A-Z0-9]+)+');
  final codes = <String>{};
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.contains('/.dart_tool/')) continue;
      if (isPackageTestSource(path)) continue;
      codes.addAll(
        pattern
            .allMatches(entity.readAsStringSync())
            .map((match) => match.group(0)!),
      );
    }
  }
  return codes;
}

/// Whether [path] is a Dart file inside a package's own test tree.
///
/// Anchored on the owning `pubspec.yaml` rather than on any segment named
/// `test` or `fixtures`, so shipped code such as `lib/src/test_support/` is
/// still scanned.
bool isPackageTestSource(String path) {
  final segments = path.replaceAll('\\', '/').split('/');
  for (var i = 0; i < segments.length - 1; i++) {
    final segment = segments[i];
    if (segment != 'test' && segment != 'integration_test') continue;
    if (i == 0) continue;
    final packageRoot = segments.sublist(0, i).join('/');
    if (File('$packageRoot/pubspec.yaml').existsSync()) return true;
  }
  return false;
}
