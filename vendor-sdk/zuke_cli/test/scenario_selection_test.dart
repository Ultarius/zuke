import 'dart:convert';
import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:test/test.dart';

void main() {
  WorkspaceDiscoveryResult workspace(
    String expression,
  ) => WorkspaceDiscoveryResult(
    config: ZukeConfig(
      executionConfig: {
        'release': {'tagExpression': expression},
      },
    ),
    data: MetadataExtractorResult(
      features: [
        ParsedFeature(
          metadata: const ParsedMetadata(
            id: 'FEAT-SELECT',
            source: SourceLocation(file: 'select.feature', line: 1),
          ),
          tags: const [
            GherkinTag(
              name: 'feature',
              source: SourceLocation(file: 'select.feature', line: 1),
            ),
          ],
          featureElement: const GherkinElement(
            keyword: GherkinKeyword.feature,
            title: 'Selection',
            source: SourceLocation(file: 'select.feature', line: 1),
          ),
          rules: [
            ParsedRule(
              metadata: const ParsedMetadata(
                id: 'RULE-SELECT',
                source: SourceLocation(file: 'select.feature', line: 2),
              ),
              tags: const [],
              ruleElement: const GherkinElement(
                keyword: GherkinKeyword.rule,
                title: 'Selection rule',
                source: SourceLocation(file: 'select.feature', line: 2),
              ),
              scenarios: [
                _scenario('SCN-PR', 'pr'),
                _scenario('SCN-MERGE', 'merge'),
                _scenario('SCN-NIGHTLY', 'nightly', secondTag: 'performance'),
                _scenario(
                  'SCN-OUTLINE',
                  'outline',
                  examples: const [
                    GherkinExamples(
                      title: 'release values',
                      tags: [
                        GherkinTag(
                          name: 'release',
                          source: SourceLocation(
                            file: 'select.feature',
                            line: 3,
                          ),
                        ),
                      ],
                      headers: ['value'],
                      rows: [
                        ['1'],
                      ],
                      source: SourceLocation(file: 'select.feature', line: 3),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  test('selects governed scenarios with or, and, and parentheses', () {
    final selected = const ScenarioSelector().select(
      workspace('(@pr or @merge) and @feature'),
      'release',
    );

    expect(selected, ['SCN-MERGE', 'SCN-PR']);
  });

  test('produces a deterministic, digest-bound selection artifact', () {
    final selection = const ScenarioSelector().resolve(
      workspace('@merge or @pr'),
      'release',
    );
    final again = const ScenarioSelector().resolve(
      workspace('@merge or @pr'),
      'release',
    );
    expect(selection.scenarioIds, ['SCN-MERGE', 'SCN-PR']);
    expect(selection.digest, startsWith('sha256:'));
    expect(selection.digest, again.digest);

    final temporary = Directory.systemTemp.createTempSync('zuke-selection-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final file = File(
      '${temporary.path}${Platform.pathSeparator}selection.json',
    );
    selection.writeAtomic(file);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(json['schemaVersion'], ScenarioSelection.schemaVersion);
    expect(json['digest'], selection.digest);
    expect(json['scenarioIds'], selection.scenarioIds);
  });

  test('supports unary not with higher precedence than and/or', () {
    final selected = const ScenarioSelector().select(
      workspace('@feature and not (@nightly or @performance)'),
      'release',
    );

    expect(selected, ['SCN-MERGE', 'SCN-OUTLINE', 'SCN-PR']);
  });

  test('includes tags inherited from matching Examples blocks', () {
    expect(const ScenarioSelector().select(workspace('@release'), 'release'), [
      'SCN-OUTLINE',
    ]);
  });

  test('rejects not without an operand', () {
    expect(
      () =>
          const ScenarioSelector().select(workspace('@pr and not'), 'release'),
      throwsFormatException,
    );
  });

  test('rejects malformed tag expressions even when a branch is false', () {
    expect(
      () =>
          const ScenarioSelector().select(workspace('@missing and'), 'release'),
      throwsFormatException,
    );
  });

  test('rejects an expression that selects no governed scenarios', () {
    expect(
      () => const ScenarioSelector().select(
        workspace('@does-not-exist'),
        'release',
      ),
      throwsFormatException,
    );
  });

  test('leaves runner-owned legacy workspaces unfiltered', () {
    const legacy = WorkspaceDiscoveryResult(
      config: ZukeConfig(executionConfig: {'runners': []}),
      data: MetadataExtractorResult(),
    );

    expect(const ScenarioSelector().select(legacy, 'pullRequest'), isEmpty);
  });

  test(
    'rejects tag expressions with invalid characters, unexpected tokens, or unclosed parens',
    () {
      expect(
        () => const ScenarioSelector().select(
          workspace('@pr invalid#char'),
          'release',
        ),
        throwsFormatException,
      );
      expect(
        () =>
            const ScenarioSelector().select(workspace('@pr @merge'), 'release'),
        throwsFormatException,
      );
      expect(
        () => const ScenarioSelector().select(workspace('(@pr'), 'release'),
        throwsFormatException,
      );
    },
  );
}

GherkinScenario _scenario(
  String id,
  String firstTag, {
  String? secondTag,
  List<GherkinExamples> examples = const [],
}) => GherkinScenario(
  tags: [
    GherkinTag(
      name: id,
      source: const SourceLocation(file: 'select.feature', line: 3),
    ),
    GherkinTag(
      name: firstTag,
      source: const SourceLocation(file: 'select.feature', line: 3),
    ),
    if (secondTag != null)
      GherkinTag(
        name: secondTag,
        source: const SourceLocation(file: 'select.feature', line: 3),
      ),
  ],
  scenarioElement: GherkinElement(
    keyword: GherkinKeyword.scenario,
    title: id,
    source: const SourceLocation(file: 'select.feature', line: 3),
  ),
  examples: examples,
);
