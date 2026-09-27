import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/temporary_directory.dart';

void main() {
  group('Implementation coverage validator', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-cov-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// A workspace with two rules: `RULE-COV-ONE` declared for `backend`, and
    /// `RULE-COV-TWO` declared for both.
    WorkspaceDiscoveryResult buildWorkspace() {
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: coverage
  root: .
specifications:
  features:
    - specs/features/example.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: cov_pkg
        path: .
        roots: [lib]
  flutter:
    language: dart
    framework: flutter
    packages:
      - id: cov_app
        path: app
        roots: [lib]
''');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      File('${features.path}/example.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-COV-001
# targets:
#   - backend
#   - flutter
# spec-end
@FEAT-COV-001
Feature: Coverage
  # rule-spec-begin
  # id: RULE-COV-ONE
  # targets:
  #   - backend
  # rule-spec-end
  @RULE-COV-ONE
  Rule: Only the backend owns this
    @SCN-COV-001
    Scenario: Works
      Given a step

  # rule-spec-begin
  # id: RULE-COV-TWO
  # rule-spec-end
  @RULE-COV-TWO
  Rule: Both targets own this
    @SCN-COV-002
    Scenario: Works
      Given a step
''');
      return WorkspaceDiscovery().discover(root.path);
    }

    ExtractedSymbol implementation(
      String requirementId, {
      String? target = 'backend',
      ExtractedSymbolKind kind = ExtractedSymbolKind.requirementBoundary,
    }) => ExtractedSymbol(
      kind: kind,
      role: 'provider',
      symbolId: 'symbol:$requirementId',
      requirementIds: [requirementId],
      target: target,
      source: const ExtractedSourceLocation(
        uri: 'lib/src/provider.dart',
        offset: 0,
        length: 0,
        line: 1,
        column: 1,
      ),
    );

    test('reports a declared requirement that nothing implements', () {
      final workspace = buildWorkspace();
      final result = ImplementationCoverageValidator().validate(workspace);
      final ids = result.warnings.map((message) => message.code).toSet();
      expect(ids, {'ZUKE-IMPL-001'});
      final messages = result.warnings.map((m) => m.message).join('\n');
      expect(messages, contains('RULE-COV-ONE'));
      expect(messages, contains('RULE-COV-TWO'));
      // A warning, not an error: a specs-first workspace must still be
      // validatable before any implementation exists.
      expect(result.errors, isEmpty);
    });

    test('stays silent once every requirement is implemented', () {
      final workspace = buildWorkspace();
      final result = ImplementationCoverageValidator().validate(
        workspace,
        extractedSymbols: [
          implementation('RULE-COV-ONE'),
          implementation('RULE-COV-TWO'),
        ],
      );
      expect(result.warnings, isEmpty);
    });

    test('a presentation counts as an implementation', () {
      final workspace = buildWorkspace();
      final result = ImplementationCoverageValidator().validate(
        workspace,
        extractedSymbols: [
          implementation(
            'RULE-COV-ONE',
            kind: ExtractedSymbolKind.presentationBoundary,
          ),
          implementation('RULE-COV-TWO'),
        ],
      );
      expect(result.warnings, isEmpty);
    });

    test('scopes implementation to the target that owns the requirement', () {
      final workspace = buildWorkspace();
      // RULE-COV-ONE narrows to backend, so only a backend implementation
      // satisfies it. RULE-COV-TWO inherits the feature's targets, so a flutter
      // implementation satisfies it.
      final result = ImplementationCoverageValidator().validate(
        workspace,
        extractedSymbols: [
          implementation('RULE-COV-ONE', target: 'backend'),
          implementation('RULE-COV-TWO', target: 'flutter'),
        ],
      );
      expect(result.warnings, isEmpty);
    });

    test('an implementation in the wrong target does not count', () {
      final workspace = buildWorkspace();
      // RULE-COV-ONE belongs to backend, so implementing it only in the Flutter
      // package must not silence the finding.
      final result = ImplementationCoverageValidator().validate(
        workspace,
        extractedSymbols: [
          implementation('RULE-COV-ONE', target: 'flutter'),
          implementation('RULE-COV-TWO', target: 'backend'),
        ],
      );
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.message, contains('RULE-COV-ONE'));
    });

    test('an untargeted implementation is not attributed away', () {
      final workspace = buildWorkspace();
      // A symbol with no target cannot be pinned to one, so it satisfies every
      // target. Under-reporting would hide a real gap.
      final result = ImplementationCoverageValidator().validate(
        workspace,
        extractedSymbols: [
          implementation('RULE-COV-ONE', target: null),
          implementation('RULE-COV-TWO', target: null),
        ],
      );
      expect(result.warnings, isEmpty);
    });

    test('every finding carries an actionable remediation', () {
      final workspace = buildWorkspace();
      final result = ImplementationCoverageValidator().validate(workspace);
      expect(result.warnings, isNotEmpty);
      for (final warning in result.warnings) {
        expect(warning.remediation, isNotNull);
        expect(warning.remediation, isNotEmpty);
        expect(
          warning.remediation,
          anyOf(contains('ImplementsRequirement'), contains('targets')),
        );
      }
    });

    test('ignores symbols that are not requirement boundaries', () {
      final workspace = buildWorkspace();
      final result = ImplementationCoverageValidator().validate(
        workspace,
        extractedSymbols: [
          implementation(
            'RULE-COV-ONE',
            kind: ExtractedSymbolKind.controlProvider,
          ),
          implementation('RULE-COV-TWO', kind: ExtractedSymbolKind.binding),
        ],
      );
      expect(result.warnings, hasLength(2));
    });
  });
}
