import 'package:test/test.dart';
import 'package:zuke_cli/src/path_safety.dart' as cli;
// The frontend copy is reached through its own barrel, and the CLI copy through
// `path_safety.dart`. Importing both unprefixed would make every use ambiguous,
// which is itself part of what this test exists to make visible.
import 'package:zuke_frontend/zuke_frontend.dart' as frontend;

/// Holds the two copies of the lexical path helpers in step.
///
/// `zuke_frontend` and `zuke_cli` each define `pathComparisonKey`,
/// `normalizeRelativePath` and `normalizePackagePath`. That duplication is forced:
/// the frontend normalizes a package path when it reads the configuration, and
/// the CLI depends on the frontend by *published* version, so a fresh resolution —
/// the one the analysis-server plugin fixture performs — fetches whatever is on
/// pub.dev. Importing the frontend's copy would fail to compile against an
/// unreleased version.
///
/// Two copies that agree is acceptable; two copies that drift is not, because the
/// whole reason the frontend owns normalization is that a package declared as
/// `./` must not be dropped by one reader and kept as the workspace root by
/// another. This test is what makes that reason enforceable rather than a
/// convention: any edit to one copy that is not mirrored in the other fails here.
void main() {
  // The spellings that have actually caused disagreement, plus the ordinary ones.
  const spellings = <String>[
    '.',
    './',
    './.',
    '',
    '   ',
    'lib',
    './lib',
    'lib/',
    'apps/api',
    './apps/api',
    './apps//api/',
    r'apps\api',
    r'.\apps\api',
    'apps/temp/../api',
    'a/./b',
    'a//b',
    'apps/api/',
  ];

  test('the CLI and frontend normalize a package path identically', () {
    for (final path in spellings) {
      expect(
        frontend.normalizePackagePath(path),
        cli.normalizePackagePath(path),
        reason: 'normalizePackagePath disagreed on ${jsonSafe(path)}',
      );
    }
  });

  test('the CLI and frontend normalize a relative path identically', () {
    for (final path in spellings) {
      expect(
        frontend.normalizeRelativePath(path),
        cli.normalizeRelativePath(path),
        reason: 'normalizeRelativePath disagreed on ${jsonSafe(path)}',
      );
    }
  });

  test('the CLI and frontend build comparison keys identically', () {
    // After normalization, so the only variable is the host-aware comparison.
    for (final path in spellings) {
      final normalized = cli.normalizePackagePath(path);
      expect(
        frontend.pathComparisonKey(normalized),
        cli.pathComparisonKey(normalized),
        reason: 'pathComparisonKey disagreed on ${jsonSafe(path)}',
      );
    }
  });

  test('the spellings that motivated the helpers still collapse together', () {
    // Guards the behaviour, not just the agreement: if these stopped collapsing,
    // a package declared three ways would be counted three times.
    final root = {
      cli.normalizePackagePath('.'),
      cli.normalizePackagePath('./'),
      cli.normalizePackagePath('./.'),
      frontend.normalizePackagePath('.'),
      frontend.normalizePackagePath('./'),
      frontend.normalizePackagePath('./.'),
    };
    expect(root, hasLength(1), reason: 'the workspace root has one spelling');
    expect(root.single, '.');

    final nested = {
      cli.normalizePackagePath('apps/api'),
      cli.normalizePackagePath('./apps/api/'),
      cli.normalizePackagePath(r'apps\api'),
      cli.normalizePackagePath('apps/temp/../api'),
    };
    expect(nested, hasLength(1), reason: 'a nested package has one spelling');
    expect(nested.single, 'apps/api');
  });
}

/// Renders a spelling readably in a failure message without letting a trailing
/// backslash or a control character hide the difference.
String jsonSafe(String value) => '"${value.replaceAll('\\', r'\\')}"';
