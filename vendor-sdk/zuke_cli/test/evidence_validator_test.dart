import 'dart:io';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/proof_engine.dart';

const _backendDomainSlot = <String, String>{
  'type': 'domain-unit',
  'target': 'backend',
  'sourcePackage': 'backend',
  'sourceAdapter': 'dart-test',
  'variant': 'default',
};
const _flutterWidgetSlot = <String, String>{
  'type': 'flutter-widget',
  'target': 'flutter',
  'sourcePackage': 'flutter',
  'sourceAdapter': 'flutter-test',
  'variant': 'default',
};
const _backendApiSlot = <String, String>{
  'type': 'api-contract',
  'target': 'backend',
  'sourcePackage': 'backend',
  'sourceAdapter': 'dart-test',
  'variant': 'default',
};
const _backendSecuritySlot = <String, String>{
  'type': 'security-integration',
  'target': 'backend',
  'sourcePackage': 'backend',
  'sourceAdapter': 'dart-test',
  'variant': 'default',
};
const _flutterAccessibilitySlot = <String, String>{
  'type': 'accessibility-integration',
  'target': 'flutter',
  'sourcePackage': 'flutter',
  'sourceAdapter': 'flutter-test',
  'variant': 'default',
};
const _backendPerformanceSlot = <String, String>{
  'type': 'performance',
  'target': 'backend',
  'sourcePackage': 'backend',
  'sourceAdapter': 'dart-test',
  'variant': 'default',
};
const _backendGherkinSlot = <String, String>{
  'type': 'gherkin-api',
  'target': 'backend',
  'sourcePackage': 'backend',
  'sourceAdapter': 'dart-test',
  'variant': 'default',
};
const _flutterGherkinSlot = <String, String>{
  'type': 'gherkin-ui',
  'target': 'flutter',
  'sourcePackage': 'flutter',
  'sourceAdapter': 'flutter-test',
  'variant': 'default',
};

void main() {
  group('Variant/slot propagation', () {
    test(
      'variant-isolated providers satisfy matching variant declarations',
      () {
        final workspace = WorkspaceDiscoveryResult(
          config: const ZukeConfig(),
          data: MetadataExtractorResult(
            features: [
              ParsedFeature(
                tags: [],
                featureElement: const GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'F1',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                metadata: const ParsedMetadata(
                  id: 'FEAT-1',
                  bindings: [
                    ParsedBinding(
                      id: 'BIND-CALC-MATH',
                      target: 'flutter',
                      variant: 'variant-a',
                    ),
                    ParsedBinding(
                      id: 'BIND-CALC-MATH',
                      target: 'flutter',
                      variant: 'variant-b',
                    ),
                  ],
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                rules: [],
              ),
            ],
          ),
        );
        final symbols = [
          ExtractedSymbol(
            kind: 'binding',
            role: 'flutter',
            symbolId: 'a.dart#Provider1',
            bindingId: 'BIND-CALC-MATH',
            target: 'flutter',
            variant: 'variant-a',
            source: const ExtractedSourceLocation(
              uri: 'a.dart',
              offset: 0,
              length: 0,
              line: 1,
              column: 1,
            ),
          ),
          ExtractedSymbol(
            kind: 'binding',
            role: 'flutter',
            symbolId: 'a.dart#Provider2',
            bindingId: 'BIND-CALC-MATH',
            target: 'flutter',
            variant: 'variant-b',
            source: const ExtractedSourceLocation(
              uri: 'a.dart',
              offset: 0,
              length: 0,
              line: 1,
              column: 1,
            ),
          ),
        ];
        final result = CardinalityValidator().validate(
          workspace,
          extractedSymbols: symbols,
        );
        final cardinalityCodes = result.errors
            .where((error) => error.code.startsWith('ZUKE-CARD-'))
            .map((error) => error.code)
            .toSet();
        expect(cardinalityCodes, isNot(contains('ZUKE-CARD-001')));
        expect(cardinalityCodes, isNot(contains('ZUKE-CARD-002')));
        expect(cardinalityCodes, isNot(contains('ZUKE-CARD-008')));
      },
    );

    test('same variant for exactlyOne binding fails with ZUKE-CARD-002', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                bindings: [
                  ParsedBinding(id: 'BIND-CALC-MATH', target: 'flutter'),
                ],
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [],
            ),
          ],
        ),
      );
      final symbols = [
        ExtractedSymbol(
          kind: 'binding',
          role: 'flutter',
          symbolId: 'a.dart#Provider1',
          bindingId: 'BIND-CALC-MATH',
          target: 'flutter',
          variant: 'default',
          source: const ExtractedSourceLocation(
            uri: 'a.dart',
            offset: 0,
            length: 0,
            line: 1,
            column: 1,
          ),
        ),
        ExtractedSymbol(
          kind: 'binding',
          role: 'flutter',
          symbolId: 'a.dart#Provider2',
          bindingId: 'BIND-CALC-MATH',
          target: 'flutter',
          variant: 'default',
          source: const ExtractedSourceLocation(
            uri: 'a.dart',
            offset: 0,
            length: 0,
            line: 1,
            column: 1,
          ),
        ),
      ];
      final result = CardinalityValidator().validate(
        workspace,
        extractedSymbols: symbols,
      );
      expect(result.errors.any((e) => e.code == 'ZUKE-CARD-002'), isTrue);
    });
  });

  group('EvidenceValidator', () {
    test('passes when evidence records match requirements and targets', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(contractOutput: 'lib/generated'),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: ['domain-unit'],
                    evidenceRequirements: [_backendDomainSlot],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-1',
        status: EvidenceStatus.passed,
      );

      final result = EvidenceValidator().validate(workspace, records: [record]);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVID-003'), isFalse);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-005'), isFalse);
    });

    test('rejects unmapped records with ZUKE-EVIDENCE-005', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(features: []),
      );

      final record = SemanticEvidenceRecord(
        requirementId: 'RULE-UNMAPPED',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-1',
        status: EvidenceStatus.passed,
      );

      final result = EvidenceValidator().validate(workspace, records: [record]);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-005'), isTrue);
    });

    test('rejects skipped security evidence with ZUKE-EVIDENCE-006', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [
                const GherkinTag(
                  name: 'security',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
              ],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: ['domain-unit'],
                    evidenceRequirements: [_backendDomainSlot],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-1',
        status: EvidenceStatus.skipped,
      );

      final result = EvidenceValidator().validate(workspace, records: [record]);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-006'), isTrue);
    });

    test('rejects missing required evidence with ZUKE-EVID-003', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: ['domain-unit'],
                    evidenceRequirements: [_backendDomainSlot],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final result = EvidenceValidator().validate(workspace, records: []);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVID-003'), isTrue);
    });

    test('passes all suite types with passing records', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(contractOutput: 'lib/generated'),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: [
                      'domain-unit',
                      'flutter-widget',
                      'api-contract',
                      'security-integration',
                      'accessibility-integration',
                      'performance',
                      'gherkin-api',
                      'gherkin-ui',
                    ],
                    evidenceRequirements: [
                      _backendDomainSlot,
                      _flutterWidgetSlot,
                      _backendApiSlot,
                      _backendSecuritySlot,
                      _flutterAccessibilitySlot,
                      _backendPerformanceSlot,
                      _backendGherkinSlot,
                      _flutterGherkinSlot,
                    ],
                    requires: [ParsedControlRef(id: 'CONTROL-1')],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-domain',
        status: EvidenceStatus.passed,
      );
      final recordFlutter = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'flutter-widget',
        target: 'flutter',
        sourcePackage: 'flutter',
        sourceAdapter: 'flutter-test',
        executionId: 'exec-flutter',
        status: EvidenceStatus.passed,
      );
      final recordApi = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'api-contract',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-api',
        status: EvidenceStatus.passed,
      );
      final recordSecurity = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'security-integration',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-security',
        status: EvidenceStatus.passed,
      );
      final recordAccessibility = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'accessibility-integration',
        target: 'flutter',
        sourcePackage: 'flutter',
        sourceAdapter: 'flutter-test',
        executionId: 'exec-a11y',
        status: EvidenceStatus.passed,
      );
      final recordPerf = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'performance',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-perf',
        status: EvidenceStatus.passed,
      );
      final recordGherkinApi = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'gherkin-api',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-gherkin-api',
        status: EvidenceStatus.passed,
      );
      final recordGherkinUi = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'gherkin-ui',
        target: 'flutter',
        sourcePackage: 'flutter',
        sourceAdapter: 'flutter-test',
        executionId: 'exec-gherkin-ui',
        status: EvidenceStatus.passed,
      );

      final controlProof = ControlProofResult(
        controlId: 'CONTROL-1',
        requirementId: 'RULE-1',
        status: ProofStatus.proven,
        semantics: CoverageSemantics.ingressDominance,
      );

      final result = EvidenceValidator().validate(
        workspace,
        records: [
          record,
          recordFlutter,
          recordApi,
          recordSecurity,
          recordAccessibility,
          recordPerf,
          recordGherkinApi,
          recordGherkinUi,
        ],
        controlProofs: [controlProof],
      );
      expect(result.errors.any((e) => e.code == 'ZUKE-EVID-003'), isFalse);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-005'), isFalse);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-006'), isFalse);
    });

    test('rejects stale records with ZUKE-EVIDENCE-STALE', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(contractOutput: 'lib/generated'),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: ['domain-unit'],
                    evidenceRequirements: [_backendDomainSlot],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-1',
        status: EvidenceStatus.passed,
        digests: {
          'contract':
              'sha256:0000000000000000000000000000000000000000000000000000000000000000',
        },
      );

      final result = EvidenceValidator().validate(workspace, records: [record]);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-STALE'), isTrue);
    });

    test('distinguishes missing from skipped from stale evidence', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(contractOutput: 'lib/generated'),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [
                const GherkinTag(
                  name: 'security',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
              ],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: ['domain-unit'],
                    evidenceRequirements: [_backendDomainSlot],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final skippedRecord = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-skipped',
        status: EvidenceStatus.skipped,
      );

      final staleRecord = SemanticEvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-stale',
        status: EvidenceStatus.passed,
        digests: {
          'contract':
              'sha256:0000000000000000000000000000000000000000000000000000000000000000',
        },
      );

      final resultMissing = EvidenceValidator().validate(
        workspace,
        records: [],
      );
      expect(
        resultMissing.errors.any((e) => e.code == 'ZUKE-EVID-003'),
        isTrue,
      );

      final resultSkipped = EvidenceValidator().validate(
        workspace,
        records: [skippedRecord],
      );
      expect(
        resultSkipped.errors.any((e) => e.code == 'ZUKE-EVIDENCE-006'),
        isTrue,
      );

      final resultStale = EvidenceValidator().validate(
        workspace,
        records: [staleRecord],
      );
      expect(
        resultStale.errors.any((e) => e.code == 'ZUKE-EVIDENCE-STALE'),
        isTrue,
      );
    });
  });

  group('Digest verification (B3)', () {
    test('digest verification rejects edit-after-emission', () {
      final dir = Directory.systemTemp.createTempSync('zuke_test_');
      try {
        final featurePath = '${dir.path}${Platform.pathSeparator}test.feature';
        final featureFile = File(featurePath);
        featureFile.writeAsStringSync('Feature: Test\n  Rule: R1\n');
        final initialDigest =
            'sha256:${sha256.convert(featureFile.readAsBytesSync()).toString()}';

        final workspace = WorkspaceDiscoveryResult(
          config: const ZukeConfig(contractOutput: 'lib/generated'),
          data: MetadataExtractorResult(
            features: [
              ParsedFeature(
                tags: [],
                featureElement: GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'F1',
                  source: SourceLocation(file: featurePath, line: 1),
                ),
                metadata: ParsedMetadata(
                  id: 'FEAT-1',
                  source: SourceLocation(file: featurePath, line: 1),
                ),
                rules: [
                  ParsedRule(
                    tags: [],
                    ruleElement: GherkinElement(
                      keyword: GherkinKeyword.rule,
                      title: 'R1',
                      source: SourceLocation(file: featurePath, line: 2),
                    ),
                    metadata: ParsedMetadata(
                      id: 'RULE-1',
                      requiredEvidence: ['domain-unit'],
                      evidenceRequirements: const [_backendDomainSlot],
                      source: SourceLocation(file: featurePath, line: 2),
                    ),
                    scenarios: [],
                  ),
                ],
              ),
            ],
          ),
        );

        final record = SemanticEvidenceRecord(
          requirementId: 'RULE-1',
          evidenceType: 'domain-unit',
          target: 'backend',
          sourcePackage: 'backend',
          sourceAdapter: 'dart-test',
          executionId: 'exec-1',
          status: EvidenceStatus.passed,
          digests: {
            'contract':
                'sha256:0000000000000000000000000000000000000000000000000000000000000000',
            'specification': initialDigest,
          },
        );

        featureFile.writeAsStringSync('Feature: Test (edited)\n  Rule: R1\n');

        final result = EvidenceValidator().validate(
          workspace,
          records: [record],
        );
        expect(
          result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-STALE'),
          isTrue,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('orphan record with no matching scenario fails', () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'F1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'R1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-1',
                    requiredEvidence: ['domain-unit'],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = SemanticEvidenceRecord(
        requirementId: 'RULE-ORPHAN',
        evidenceType: 'domain-unit',
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-test',
        executionId: 'exec-orphan',
        status: EvidenceStatus.passed,
      );

      final result = EvidenceValidator().validate(workspace, records: [record]);
      expect(result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-005'), isTrue);
    });

    test(
      'editing source code after evidence emission marks source digest stale',
      () {
        final workspace = WorkspaceDiscoveryResult(
          config: const ZukeConfig(contractOutput: 'lib/generated'),
          data: MetadataExtractorResult(
            features: [
              ParsedFeature(
                tags: [],
                featureElement: const GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'F1',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                metadata: const ParsedMetadata(
                  id: 'FEAT-1',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                rules: [
                  ParsedRule(
                    tags: [],
                    ruleElement: const GherkinElement(
                      keyword: GherkinKeyword.rule,
                      title: 'R1',
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    metadata: const ParsedMetadata(
                      id: 'RULE-1',
                      requiredEvidence: ['domain-unit'],
                      evidenceRequirements: [_backendDomainSlot],
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    scenarios: [],
                  ),
                ],
              ),
            ],
          ),
        );

        final adapterOutput = IrAdapterOutput(
          adapter: const AdapterDescriptor(
            id: 'test-adapter',
            version: '1.0.0',
          ),
          completeness: const IrAdapterCompleteness(),
          symbols: [
            ExtractedSymbol(
              kind: 'binding',
              role: 'backend',
              symbolId: 'test.dart#Provider',
              bindingId: 'RULE-1',
              target: 'backend',
              variant: 'default',
              source: const ExtractedSourceLocation(
                uri: 'test.dart',
                offset: 0,
                length: 0,
                line: 1,
                column: 1,
              ),
            ),
          ],
          inputDigest: 'original-digest-value',
        );

        final record = SemanticEvidenceRecord(
          requirementId: 'RULE-1',
          evidenceType: 'domain-unit',
          target: 'backend',
          sourcePackage: 'backend',
          sourceAdapter: 'dart-test',
          executionId: 'exec-1',
          status: EvidenceStatus.passed,
          digests: {
            'source':
                'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'contract':
                'sha256:0000000000000000000000000000000000000000000000000000000000000000',
          },
        );

        final result = EvidenceValidator().validate(
          workspace,
          records: [record],
          outputs: [adapterOutput],
        );
        expect(
          result.errors.any((e) => e.code == 'ZUKE-EVIDENCE-STALE'),
          isTrue,
        );
      },
    );
  });

  test('registered record evidence mode satisfies a custom target slot', () {
    const slot = <String, String>{
      'type': 'dashboard-behavior',
      'target': 'dashboard',
      'sourcePackage': 'dashboard',
      'sourceAdapter': 'jaspr',
      'variant': 'default',
    };
    final workspace = WorkspaceDiscoveryResult(
      config: const ZukeConfig(evidenceTypes: {'dashboard-behavior': 'record'}),
      data: MetadataExtractorResult(
        features: [
          ParsedFeature(
            tags: const [],
            featureElement: const GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Dashboard',
              source: SourceLocation(file: 'dashboard.feature', line: 1),
            ),
            metadata: const ParsedMetadata(
              id: 'FEAT-DASHBOARD',
              source: SourceLocation(file: 'dashboard.feature', line: 1),
            ),
            rules: [
              ParsedRule(
                tags: const [],
                ruleElement: const GherkinElement(
                  keyword: GherkinKeyword.rule,
                  title: 'Dashboard behavior',
                  source: SourceLocation(file: 'dashboard.feature', line: 5),
                ),
                metadata: const ParsedMetadata(
                  id: 'RULE-DASHBOARD-BEHAVIOR',
                  requiredEvidence: ['dashboard-behavior'],
                  evidenceRequirements: [slot],
                  source: SourceLocation(file: 'dashboard.feature', line: 5),
                ),
                scenarios: const [],
              ),
            ],
          ),
        ],
      ),
    );
    final result = EvidenceValidator().validate(
      workspace,
      records: [
        const SemanticEvidenceRecord(
          requirementId: 'RULE-DASHBOARD-BEHAVIOR',
          evidenceType: 'dashboard-behavior',
          target: 'dashboard',
          variant: 'default',
          sourcePackage: 'dashboard',
          sourceAdapter: 'jaspr',
          executionId: 'dashboard-exec',
          status: EvidenceStatus.passed,
        ),
      ],
    );
    expect(
      result.errors.any((error) => error.code == 'ZUKE-EVID-003'),
      isFalse,
    );
  });
}
