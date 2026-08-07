import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_cli/src/proof_engine.dart';

void main() {
  group('Profile expansion', () {
    test('calculator-public-endpoint expands to CTRL-CALC-LOG-REDACTION', () {
      final discovery = WorkspaceDiscoveryResult(
        config: const ZukeConfig(targetsConfig: {'backend': {}}),
        data: MetadataExtractorResult(
          controls: {
            'CTRL-CALC-LOG-REDACTION': {'id': 'CTRL-CALC-LOG-REDACTION'},
          },
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Feature 1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-CALC-001',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'Rule 1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-CALC-ADDITION',
                    securityProfile: 'calculator-public-endpoint',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
          policies: {
            'security-policy': {
              'securityProfiles': {
                'calculator-public-endpoint': {
                  'requires': [
                    {'id': 'CTRL-CALC-LOG-REDACTION', 'target': 'backend'},
                  ],
                },
              },
            },
          },
        ),
      );
      final result = ValidatorEngine().validate(discovery);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'CONTROL-PROOF-MISSING' &&
              e.message.contains('CTRL-CALC-LOG-REDACTION'),
        ),
        isTrue,
      );
    });
  });

  test('reports the complete fail-closed reference and provider matrix', () {
    const source = SourceLocation(file: 'invalid.feature', line: 1);
    final discovery = WorkspaceDiscoveryResult(
      config: const ZukeConfig(targetsConfig: {'backend': {}}),
      data: MetadataExtractorResult(
        epics: const {},
        controls: const {},
        registries: {
          'ENDPOINT-REGISTERED': {
            'id': 'ENDPOINT-REGISTERED',
            'ownerFeature': 'FEAT-OTHER',
            'target': 'backend',
            'method': 'POST',
            'contract': 'request-v1',
          },
        },
        policies: {
          'providers': {
            'providers': [
              {'id': 'invalid', 'assurance': 'decorative'},
              {
                'id': 'expired',
                'assurance': 'attested',
                'expiresAt': '2000-01-01T00:00:00Z',
              },
            ],
          },
        },
        features: [
          ParsedFeature(
            tags: const [],
            featureElement: const GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Invalid references',
              source: source,
            ),
            metadata: const ParsedMetadata(
              id: 'FEAT-INVALID',
              epic: 'EPIC-UNKNOWN',
              targets: ['mobile'],
              pbis: ['PBI-UNKNOWN'],
              endpoints: [
                ParsedEndpoint(id: 'ENDPOINT-MISSING', target: 'mobile'),
                ParsedEndpoint(
                  id: 'ENDPOINT-REGISTERED',
                  target: 'mobile',
                  method: 'GET',
                  contract: 'request-v2',
                ),
              ],
              events: ['EVENT-UNKNOWN'],
              featureFlags: ['FLAG-UNKNOWN'],
              performance: [
                ParsedPerformance(
                  id: 'PERF-USE',
                  target: 'backend',
                  threshold: '100ms',
                  percentile: 95,
                  profile: 'PERF-UNKNOWN',
                ),
              ],
              source: source,
            ),
            rules: [
              ParsedRule(
                tags: const [],
                ruleElement: const GherkinElement(
                  keyword: GherkinKeyword.rule,
                  title: 'Invalid rule references',
                  source: source,
                ),
                metadata: const ParsedMetadata(
                  id: 'RULE-INVALID',
                  requires: [
                    ParsedControlRef(
                      id: 'CTRL-UNKNOWN',
                      target: 'mobile',
                      cardinality: 'sometimes',
                    ),
                  ],
                  securityProfile: 'missing-profile',
                  source: source,
                ),
                scenarios: const [],
              ),
            ],
          ),
        ],
      ),
    );

    final result = ReferenceResolver().validate(discovery);
    final codes = result.errors.map((error) => error.code).toSet();

    expect(
      codes,
      containsAll({
        'ZUKE-REF-001',
        'ZUKE-REF-002',
        'ZUKE-REF-003',
        'ZUKE-REF-004',
        'ZUKE-REF-005',
        'ZUKE-REF-006',
        'ZUKE-REF-007',
        'ZUKE-REF-008',
        'ZUKE-REF-009',
        'ZUKE-REF-010',
        'ZUKE-REF-011',
        'ZUKE-REF-012',
        'ZUKE-PROVIDER-001',
        'ZUKE-PROVIDER-002',
        'ZUKE-PROVIDER-003',
      }),
    );
    expect(
      result.errors
          .where((error) => error.code == 'ZUKE-REF-011')
          .map((error) => error.message),
      hasLength(3),
    );
    expect(
      result.errors.where((error) => error.code == 'ZUKE-PROVIDER-002'),
      hasLength(3),
    );
  });

  group('ReferenceResolver PBI back-reference', () {
    test(
      'detects PBI back-reference mismatch between registry and feature',
      () {
        const source = SourceLocation(file: 'mismatch.feature', line: 1);
        final discovery = WorkspaceDiscoveryResult(
          config: const ZukeConfig(),
          data: MetadataExtractorResult(
            features: [
              ParsedFeature(
                tags: [],
                featureElement: const GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'Mismatch feature',
                  source: source,
                ),
                metadata: const ParsedMetadata(
                  id: 'FEAT-MISMATCH-001',
                  pbis: ['PBI-MISMATCH'],
                  source: source,
                ),
                rules: [],
              ),
            ],
            registries: {
              'PBI-MISMATCH': {
                'id': 'PBI-MISMATCH',
                'feature': 'FEAT-OTHER-001',
                '_sourceList': 'pbis',
              },
            },
          ),
        );
        final result = ReferenceResolver().validate(discovery);
        expect(
          result.errors.any(
            (e) =>
                e.code == 'ZUKE-REF-004' &&
                e.message.contains('back-reference'),
          ),
          isTrue,
        );
      },
    );

    test('passes when PBI back-reference matches the declaring feature', () {
      const source = SourceLocation(file: 'match.feature', line: 1);
      final discovery = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Matching feature',
                source: source,
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-MATCH-001',
                pbis: ['PBI-MATCH'],
                source: source,
              ),
              rules: [],
            ),
          ],
          registries: {
            'PBI-MATCH': {
              'id': 'PBI-MATCH',
              'feature': 'FEAT-MATCH-001',
              '_sourceList': 'pbis',
            },
          },
        ),
      );
      final result = ReferenceResolver().validate(discovery);
      expect(result.errors.where((e) => e.code == 'ZUKE-REF-004'), isEmpty);
    });
  });

  group('ReferenceResolver Cycle Detection', () {
    test('passes when there are no cycle references', () {
      final discovery = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          epics: {
            'EPIC-CALC-001': {'title': 'Epic 1'},
          },
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Feature 1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-CALC-001',
                epic: 'EPIC-CALC-001',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [
                    const GherkinTag(
                      name: 'PBI-CALC-001',
                      source: SourceLocation(file: 'a.feature', line: 1),
                    ),
                  ],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'Rule 1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-CALC-ADDITION',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
          registries: {
            'PBI-CALC-001': {
              'id': 'PBI-CALC-001',
              'feature': 'FEAT-CALC-001',
              '_sourceList': 'pbis',
            },
          },
        ),
      );

      final result = ReferenceResolver().validate(discovery);
      expect(result.errors.any((e) => e.code == 'ZUKE-REF-CYCLE'), isFalse);
    });

    test(
      'detects Epic -> Feature -> PBI -> Rule -> Scenario -> Epic cycle',
      () {
        final discovery = WorkspaceDiscoveryResult(
          config: const ZukeConfig(),
          data: MetadataExtractorResult(
            epics: {
              'EPIC-CALC-001': {
                'id': 'EPIC-CALC-001',
                'dependsOn': ['SCN-CALC-SCENARIO'],
              },
            },
            features: [
              ParsedFeature(
                tags: [],
                featureElement: const GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'Feature 1',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                metadata: const ParsedMetadata(
                  id: 'FEAT-CALC-001',
                  epic: 'EPIC-CALC-001',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                rules: [
                  ParsedRule(
                    tags: [],
                    ruleElement: const GherkinElement(
                      keyword: GherkinKeyword.rule,
                      title: 'Rule 1',
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    metadata: const ParsedMetadata(
                      id: 'RULE-CALC-ADDITION',
                      pbis: ['PBI-CALC-001'],
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    scenarios: [
                      GherkinScenario(
                        tags: [
                          const GherkinTag(
                            name: 'SCN-CALC-SCENARIO',
                            source: SourceLocation(file: 'a.feature', line: 8),
                          ),
                        ],
                        scenarioElement: const GherkinElement(
                          keyword: GherkinKeyword.scenario,
                          title: 'Scenario 1',
                          source: SourceLocation(file: 'a.feature', line: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            registries: {
              'PBI-CALC-001': {
                'id': 'PBI-CALC-001',
                'feature': 'FEAT-CALC-001',
                '_sourceList': 'pbis',
              },
            },
          ),
        );

        final result = ReferenceResolver().validate(discovery);
        expect(result.errors.any((e) => e.code == 'ZUKE-REF-CYCLE'), isTrue);
      },
    );

    test('detects Control -> Rule -> Control cycle', () {
      final discovery = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          controls: {
            'CTRL-CALC-INPUT-VALIDATION': {
              'id': 'CTRL-CALC-INPUT-VALIDATION',
              'dependsOn': ['RULE-CALC-ADDITION'],
            },
          },
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Feature 1',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-CALC-001',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'Rule 1',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-CALC-ADDITION',
                    requires: [
                      ParsedControlRef(id: 'CTRL-CALC-INPUT-VALIDATION'),
                    ],
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );

      final result = ReferenceResolver().validate(discovery);
      expect(result.errors.any((e) => e.code == 'ZUKE-REF-CYCLE'), isTrue);
    });
  });
}
