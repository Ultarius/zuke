import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:test/test.dart';

void main() {
  test('reports incomplete, unknown, prohibited, and missing mappings', () {
    const location = SourceLocation(file: 'fixture.feature', line: 1);
    const workspace = WorkspaceDiscoveryResult(
      config: ZukeConfig(),
      data: MetadataExtractorResult(
        controls: {
          'CTRL-KNOWN': {
            'acceptableProviderKinds': ['request-middleware'],
            'prohibitedProviderTargets': ['forbidden-role'],
          },
          'CTRL-MISSING': {},
        },
        features: [
          ParsedFeature(
            metadata: ParsedMetadata(
              id: 'FEAT-MAPPING',
              bindings: [
                ParsedBinding(id: 'calculator.input', target: 'flutter'),
              ],
              source: location,
            ),
            tags: [],
            featureElement: GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Mapping fixture',
              source: location,
            ),
            rules: [
              ParsedRule(
                metadata: ParsedMetadata(
                  id: 'RULE-MAPPING',
                  requires: [ParsedControlRef(id: 'CTRL-MISSING')],
                  source: location,
                ),
                tags: [],
                ruleElement: GherkinElement(
                  keyword: GherkinKeyword.rule,
                  title: 'Mapping rule',
                  source: location,
                ),
                scenarios: [],
              ),
            ],
          ),
        ],
      ),
    );
    const output = AdapterOutput(
      adapter: AdapterDescriptor(id: 'fixture', version: '1'),
      inputDigest: 'fixture',
      completeness: AdapterCompleteness(
        annotationTargets: CompletenessValue.indeterminate,
      ),
      diagnostics: [
        Diagnostic(
          code: 'EXTRACT-FIXTURE',
          message: 'resolver did not finish',
          severity: DiagnosticSeverity.error,
        ),
      ],
      symbols: [
        ExtractedSymbol(
          kind: 'controlProvider',
          role: 'forbidden-role',
          symbolId: 'package:fixture/mapping.dart#provider',
          requirementIds: ['RULE-UNKNOWN'],
          controlIds: ['CTRL-KNOWN', 'CTRL-UNKNOWN'],
          bindingId: 'calculator.unknown',
          providerKind: 'wrongKind',
          source: ExtractedSourceLocation(
            uri: 'package:fixture/mapping.dart',
            offset: 0,
            length: 0,
            line: 1,
            column: 1,
          ),
        ),
      ],
    );

    final result = SourceMappingValidator().validate(workspace, [output]);
    final codes = result.errors.map((error) => error.code).toSet();

    expect(
      codes,
      containsAll({
        'ZUKE-EXTRACT-001',
        'ZUKE-EXTRACT-INCOMPLETE',
        'ZUKE-MAP-UNKNOWN-REQUIREMENT',
        'ZUKE-MAP-UNKNOWN-CONTROL',
        'CONTROL-PROVIDER-002',
        'CONTROL-PROVIDER-003',
        'ZUKE-MAP-UNKNOWN-BINDING',
        'ZUKE-MAP-MISSING-BINDING',
        'CONTROL-CARDINALITY-001',
        'CONTROL-PROVIDER-001',
      }),
    );
  });
}
