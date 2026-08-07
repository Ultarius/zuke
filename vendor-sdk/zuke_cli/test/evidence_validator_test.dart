import 'dart:io';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/src/proof_engine.dart';

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
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
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

      final record = EvidenceRecord(
        requirementId: 'RULE-UNMAPPED',
        evidenceType: 'domain-unit',
        target: 'backend',
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
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
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

      final record = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        executionId: 'exec-domain',
        status: EvidenceStatus.passed,
      );
      final recordFlutter = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'flutter-widget',
        target: 'flutter',
        executionId: 'exec-flutter',
        status: EvidenceStatus.passed,
      );
      final recordApi = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'api-contract',
        target: 'backend',
        executionId: 'exec-api',
        status: EvidenceStatus.passed,
      );
      final recordSecurity = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'security-integration',
        target: 'backend',
        executionId: 'exec-security',
        status: EvidenceStatus.passed,
      );
      final recordAccessibility = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'accessibility-integration',
        target: 'flutter',
        executionId: 'exec-a11y',
        status: EvidenceStatus.passed,
      );
      final recordPerf = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'performance',
        target: 'backend',
        executionId: 'exec-perf',
        status: EvidenceStatus.passed,
      );
      final recordGherkinApi = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'gherkin-api',
        target: 'backend',
        executionId: 'exec-gherkin-api',
        status: EvidenceStatus.passed,
      );
      final recordGherkinUi = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'gherkin-ui',
        target: 'flutter',
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
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final record = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
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
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final skippedRecord = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
        executionId: 'exec-skipped',
        status: EvidenceStatus.skipped,
      );

      final staleRecord = EvidenceRecord(
        requirementId: 'RULE-1',
        evidenceType: 'domain-unit',
        target: 'backend',
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
                      source: SourceLocation(file: featurePath, line: 2),
                    ),
                    scenarios: [],
                  ),
                ],
              ),
            ],
          ),
        );

        final record = EvidenceRecord(
          requirementId: 'RULE-1',
          evidenceType: 'domain-unit',
          target: 'backend',
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

      final record = EvidenceRecord(
        requirementId: 'RULE-ORPHAN',
        evidenceType: 'domain-unit',
        target: 'backend',
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
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    scenarios: [],
                  ),
                ],
              ),
            ],
          ),
        );

        final adapterOutput = AdapterOutput(
          adapter: const AdapterDescriptor(
            id: 'test-adapter',
            version: '1.0.0',
          ),
          completeness: const AdapterCompleteness(),
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

        final record = EvidenceRecord(
          requirementId: 'RULE-1',
          evidenceType: 'domain-unit',
          target: 'backend',
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
}
