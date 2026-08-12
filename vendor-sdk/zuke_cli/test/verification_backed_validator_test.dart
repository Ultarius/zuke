import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:test/test.dart';

void main() {
  test('requires every configured defense-in-depth layer', () {
    const workspace = WorkspaceDiscoveryResult(
      config: ZukeConfig(),
      data: MetadataExtractorResult(
        controls: {
          'CTRL-LAYERED': {
            'coverageSemantics': 'verification-backed',
            'acceptableProviderKinds': ['request-middleware'],
            'requiredLayers': ['edge', 'application'],
          },
        },
        features: [
          ParsedFeature(
            metadata: ParsedMetadata(
              id: 'FEAT-LAYERED',
              source: SourceLocation(file: 'layered.feature', line: 1),
            ),
            tags: [],
            featureElement: GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Layered control',
              source: SourceLocation(file: 'layered.feature', line: 1),
            ),
            rules: [
              ParsedRule(
                metadata: ParsedMetadata(
                  id: 'RULE-LAYERED',
                  requires: [ParsedControlRef(id: 'CTRL-LAYERED')],
                  source: SourceLocation(file: 'layered.feature', line: 2),
                ),
                tags: [],
                ruleElement: GherkinElement(
                  keyword: GherkinKeyword.rule,
                  title: 'Layered control is required',
                  source: SourceLocation(file: 'layered.feature', line: 2),
                ),
                scenarios: [],
              ),
            ],
          ),
        ],
      ),
    );
    const output = IrAdapterOutput(
      adapter: AdapterDescriptor(id: 'fixture', version: '1'),
      inputDigest: 'fixture',
      completeness: IrAdapterCompleteness(),
      symbols: [
        ExtractedSymbol(
          kind: 'controlProvider',
          role: 'provider',
          symbolId: 'package:fixture/provider.dart#edge',
          controlIds: ['CTRL-LAYERED'],
          providerKind: 'requestMiddleware',
          layer: 'edge',
          target: 'backend',
          source: ExtractedSourceLocation(
            uri: 'package:fixture/provider.dart',
            offset: 0,
            length: 0,
            line: 1,
            column: 1,
          ),
        ),
      ],
    );

    final proof = VerificationBackedValidator()
        .validate(workspace, const [output], const [])
        .controlProofs
        .single;

    expect(proof.status, ProofStatus.missing);
    expect(
      proof.diagnostics,
      contains(
        'Required defense-in-depth layers have no qualifying provider: application',
      ),
    );
  });
}
