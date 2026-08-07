import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:test/test.dart';

void main() {
  group('CardinalityValidator boundaries', () {
    for (final fixture in <({String cardinality, int providers, String? code})>[
      (cardinality: 'exactlyOne', providers: 0, code: 'ZUKE-CARD-001'),
      (cardinality: 'exactlyOne', providers: 2, code: 'ZUKE-CARD-002'),
      (cardinality: 'oneOrMore', providers: 0, code: 'ZUKE-CARD-003'),
      (cardinality: 'zeroOrOne', providers: 2, code: 'ZUKE-CARD-004'),
      (cardinality: 'many', providers: 3, code: null),
      (cardinality: 'zeroOrMore', providers: 0, code: null),
    ]) {
      test('${fixture.cardinality} with ${fixture.providers} provider(s)', () {
        final result = CardinalityValidator().validate(
          _workspace(cardinality: fixture.cardinality),
          extractedSymbols: _providers(fixture.providers),
        );
        final codes = _codes(result);
        if (fixture.code == null) {
          expect(codes.where((code) => code.startsWith('ZUKE-CARD-')), isEmpty);
        } else {
          expect(codes, contains(fixture.code));
        }
      });
    }

    test('isolates declarations and providers by target and variant', () {
      final workspace = _workspace(
        bindings: const [
          ParsedBinding(id: 'list.item', target: 'flutter', variant: 'phone'),
          ParsedBinding(id: 'list.item', target: 'flutter', variant: 'tablet'),
        ],
      );
      final result = CardinalityValidator().validate(
        workspace,
        extractedSymbols: [
          ..._providers(1, variant: 'phone'),
          ..._providers(1, variant: 'tablet'),
          ..._providers(1, target: 'backend'),
        ],
      );

      expect(_codes(result), isNot(contains('ZUKE-CARD-001')));
      expect(_codes(result), isNot(contains('ZUKE-CARD-002')));
      expect(_codes(result), isNot(contains('ZUKE-CARD-008')));
    });

    test('rejects duplicate declarations with the same composite identity', () {
      final result = CardinalityValidator().validate(
        _workspace(
          bindings: const [
            ParsedBinding(id: 'list.item', target: 'flutter', variant: 'phone'),
            ParsedBinding(id: 'list.item', target: 'flutter', variant: 'phone'),
          ],
        ),
        extractedSymbols: _providers(1, variant: 'phone'),
      );

      expect(_codes(result), contains('ZUKE-CARD-008'));
    });

    test('rejects declarations for an unknown configured target', () {
      final result = CardinalityValidator().validate(
        _workspace(
          targets: const {'flutter': {}},
          bindings: const [ParsedBinding(id: 'list.item', target: 'backend')],
        ),
        extractedSymbols: _providers(1, target: 'backend'),
      );

      expect(_codes(result), contains('ZUKE-CARD-009'));
    });

    test('reports missing rules and scenarios', () {
      final noRules = CardinalityValidator().validate(
        _workspace(rules: const []),
      );
      final noScenarios = CardinalityValidator().validate(
        _workspace(rules: [_rule(const [])]),
      );

      expect(_codes(noRules), contains('ZUKE-CARD-006'));
      expect(_codes(noScenarios), contains('ZUKE-CARD-007'));
    });
  });

  test('zeroOrMore is accepted as the many binding cardinality alias', () {
    final workspace = WorkspaceDiscoveryResult(
      config: const ZukeConfig(),
      data: MetadataExtractorResult(
        features: [
          ParsedFeature(
            metadata: const ParsedMetadata(
              id: 'FEAT-CARDINALITY-ALIAS',
              bindings: [
                ParsedBinding(
                  id: 'list.item',
                  target: 'flutter',
                  cardinality: 'zeroOrMore',
                ),
              ],
              source: SourceLocation(file: 'alias.feature', line: 1),
            ),
            tags: const [],
            featureElement: const GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Alias',
              source: SourceLocation(file: 'alias.feature', line: 1),
            ),
            rules: const [],
          ),
        ],
      ),
    );

    final result = CardinalityValidator().validate(workspace);

    expect(
      result.errors.where((message) => message.code == 'ZUKE-CARD-005'),
      isEmpty,
    );
    expect(
      result.warnings.where((message) => message.code == 'ZUKE-CARD-005'),
      isEmpty,
    );
  });

  test('unknown cardinality names list the supported vocabulary', () {
    final workspace = WorkspaceDiscoveryResult(
      config: const ZukeConfig(),
      data: MetadataExtractorResult(
        features: [
          ParsedFeature(
            metadata: const ParsedMetadata(
              id: 'FEAT-CARDINALITY-UNKNOWN',
              bindings: [
                ParsedBinding(
                  id: 'list.item',
                  target: 'flutter',
                  cardinality: 'unsupported',
                ),
              ],
              source: SourceLocation(file: 'unknown.feature', line: 1),
            ),
            tags: const [],
            featureElement: const GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Unknown cardinality',
              source: SourceLocation(file: 'unknown.feature', line: 1),
            ),
            rules: const [],
          ),
        ],
      ),
    );

    final warning = CardinalityValidator()
        .validate(workspace)
        .warnings
        .singleWhere((message) => message.code == 'ZUKE-CARD-005');

    expect(warning.message, contains('exactlyOne'));
    expect(warning.message, contains('zeroOrOne'));
    expect(warning.message, contains('oneOrMore'));
    expect(warning.message, contains('many'));
    expect(warning.message, contains('zeroOrMore'));
  });
}

WorkspaceDiscoveryResult _workspace({
  String cardinality = 'exactlyOne',
  List<ParsedBinding>? bindings,
  Map<String, Object?> targets = const {},
  List<ParsedRule>? rules,
}) => WorkspaceDiscoveryResult(
  config: ZukeConfig(targetsConfig: targets),
  data: MetadataExtractorResult(
    features: [
      ParsedFeature(
        metadata: ParsedMetadata(
          id: 'FEAT-CARDINALITY',
          bindings:
              bindings ??
              [
                ParsedBinding(
                  id: 'list.item',
                  target: 'flutter',
                  cardinality: cardinality,
                ),
              ],
          source: const SourceLocation(file: 'cardinality.feature', line: 1),
        ),
        tags: const [],
        featureElement: const GherkinElement(
          keyword: GherkinKeyword.feature,
          title: 'Cardinality',
          source: SourceLocation(file: 'cardinality.feature', line: 1),
        ),
        rules:
            rules ??
            [
              _rule([_scenario()]),
            ],
      ),
    ],
  ),
);

ParsedRule _rule(List<GherkinScenario> scenarios) => ParsedRule(
  tags: const [],
  ruleElement: const GherkinElement(
    keyword: GherkinKeyword.rule,
    title: 'Rule',
    source: SourceLocation(file: 'cardinality.feature', line: 2),
  ),
  metadata: const ParsedMetadata(
    id: 'RULE-CARDINALITY',
    source: SourceLocation(file: 'cardinality.feature', line: 2),
  ),
  scenarios: scenarios,
);

GherkinScenario _scenario() => const GherkinScenario(
  tags: [],
  scenarioElement: GherkinElement(
    keyword: GherkinKeyword.scenario,
    title: 'Scenario',
    source: SourceLocation(file: 'cardinality.feature', line: 3),
  ),
);

List<ExtractedSymbol> _providers(
  int count, {
  String target = 'flutter',
  String variant = 'default',
}) => List.generate(
  count,
  (index) => ExtractedSymbol(
    kind: 'binding',
    role: target,
    symbolId: 'test.dart#Provider$index',
    bindingId: 'list.item',
    target: target,
    variant: variant,
    source: const ExtractedSourceLocation(
      uri: 'test.dart',
      offset: 0,
      length: 0,
      line: 1,
      column: 1,
    ),
  ),
);

Set<String> _codes(ValidationResult result) => {
  ...result.errors.map((message) => message.code),
  ...result.warnings.map((message) => message.code),
  ...result.infos.map((message) => message.code),
};
