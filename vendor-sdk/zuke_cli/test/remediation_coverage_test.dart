import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/diagnostic_text.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_core/src/diagnostic_codes.dart';

/// Resolves the first candidate that exists.
Directory _firstDirectory(List<String> candidates) {
  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (directory.existsSync()) return directory;
  }
  fail('none of these directories exist: $candidates');
}

/// Codes the CLI declares, using the same scan as the conformance registry
/// test so the two contracts cannot drift onto different scopes.
Set<String> _declaredCodes() {
  final root = _firstDirectory([
    // Repository root (the vendored test runner executes from there).
    'vendor-sdk/zuke_cli/lib',
    // Package root (`cd vendor-sdk/zuke_cli && dart test`).
    'lib',
  ]);
  return scanDeclaredDiagnosticCodes([root]);
}

void main() {
  group('defaultRemediation', () {
    test('covers every declared diagnostic code', () {
      final codes = _declaredCodes();
      expect(
        codes.length,
        greaterThan(40),
        reason: 'the CLI should expose many validation codes',
      );
      final uncovered = <String>[
        for (final code in codes)
          // Informational success codes intentionally carry no action.
          if (!code.endsWith('-OK') && defaultRemediation(code) == null) code,
      ]..sort();
      expect(
        uncovered,
        isEmpty,
        reason:
            'add these codes to remediation.dart (or a family) so a failure '
            'never leaves the operator to infer the recipe: $uncovered',
      );
    });

    test('returns nothing for informational success codes', () {
      expect(defaultRemediation('ZUKE-CARD-OK'), isNull);
      expect(defaultRemediation('ZUKE-ANYTHING-OK'), isNull);
    });

    test('falls back by family and stays null for unknown codes', () {
      expect(defaultRemediation('ZUKE-ID-999'), contains('Rename'));
      expect(defaultRemediation('ZK-BINDING-SLOT-INVALID'), contains('target'));
      expect(defaultRemediation('NOT-A-CODE'), isNull);
    });

    test('every explicit code is registered in the diagnostic registry', () {
      final registry = File(
        Platform.environment['ZUKE_DIAGNOSTIC_REGISTRY'] ??
            'docs/diagnostic-registry.json',
      );
      if (!registry.existsSync()) {
        markTestSkipped('diagnostic registry is not vendored in this checkout');
        return;
      }
      final decoded = jsonDecode(registry.readAsStringSync());
      final registered = {
        for (final entry in (decoded as Map)['diagnostics'] as List)
          (entry as Map)['code'] as String,
      };
      // Codes named explicitly rather than reached through a family.
      const explicit = <String>[
        'ZUKE-EVIDENCE-STALE',
        'ZUKE-SCENARIO-UNTESTED',
        'ZUKE-SCENARIO-UNEXPECTED',
        'ZUKE-PROFILE-UNTESTED',
        'ZUKE-EVIDENCE-006',
        'ZUKE-SCHEMA-002',
        'ZUKE-ID-010',
        'ZUKE-SCHEMA-001',
        'ZUKE-DISCOVERY-001',
        'ZUKE-REF-CYCLE',
        'ZUKE-TRUST-001',
      ];
      for (final code in explicit) {
        expect(
          registered,
          contains(code),
          reason: '$code has a hand-written remedy but is not a real code',
        );
      }
    });
  });

  group('renderValidationMessages', () {
    ValidationMessage message(
      String code,
      String text, {
      String? remediation,
    }) => ValidationMessage(
      code: code,
      message: text,
      severity: Severity.error,
      remediation: remediation,
    );

    test('keeps a single finding on one line with its default remedy', () {
      final rendered = renderValidationMessages([
        message('ZUKE-CARD-001', 'Binding "a" is undeclared'),
      ], label: 'ERROR');
      expect(rendered.lines.first, startsWith('  ERROR: [ZUKE-CARD-001] '));
      expect(rendered.lines, hasLength(2));
      expect(rendered.lines.last, startsWith('      HINT: '));
      expect(rendered.hasHints, isTrue);
    });

    test('lets a validator remedy override the table', () {
      final rendered = renderValidationMessages([
        message(
          'ZUKE-CARD-001',
          'Binding "a" is undeclared',
          remediation: 'Declare the binding in the feature metadata.',
        ),
      ], label: 'ERROR');
      expect(
        rendered.lines.last,
        '      HINT: Declare the binding in the feature metadata.',
      );
    });

    test('groups equal shapes, samples distinct findings, and says what '
        'was withheld', () {
      final rendered = renderValidationMessages([
        for (var i = 0; i < 5; i++)
          message('ZUKE-REF-001', 'Binding "b$i" has unknown target "t$i"'),
      ], label: 'ERROR');
      expect(rendered.lines.first, contains('(5 findings)'));
      final samples = rendered.lines[1];
      expect(samples, startsWith('      e.g. '));
      expect(samples.split(' | '), hasLength(3));
      expect(rendered.lines[2], contains('(+2 more findings not shown'));
      expect(rendered.lines[2], contains('--format json'));
    });

    test('does not claim withholding when every finding is sampled', () {
      final rendered = renderValidationMessages([
        for (var i = 0; i < 2; i++)
          message('ZUKE-REF-001', 'Binding "b$i" has unknown target "t$i"'),
      ], label: 'WARNING');
      expect(rendered.lines, hasLength(3));
      expect(rendered.lines.first, contains('(2 findings)'));
      expect(
        rendered.lines.any((line) => line.contains('more findings')),
        isFalse,
      );
    });

    test('reports no hints when no group has a remedy', () {
      final rendered = renderValidationMessages([
        message('SOME-UNKNOWN-CODE', 'Nothing actionable here'),
      ], label: 'ERROR');
      expect(rendered.hasHints, isFalse);
      expect(rendered.lines, hasLength(1));
    });

    test('is empty for no messages', () {
      expect(renderValidationMessages(const [], label: 'ERROR').lines, isEmpty);
      expect(
        renderValidationMessages(const [], label: 'ERROR').hasHints,
        isFalse,
      );
    });
  });

  group('unprintedReasons', () {
    ValidationMessage message(String code, String text) =>
        ValidationMessage(code: code, message: text, severity: Severity.error);

    test('drops reasons the grouped output already printed, once each', () {
      final messages = [message('ZUKE-REF-001', 'reason A')];
      expect(
        unprintedReasons(messages, [
          'reason A',
          'reason B',
          'reason B',
          'reason C',
        ]),
        ['reason B', 'reason C'],
      );
    });
  });
}
