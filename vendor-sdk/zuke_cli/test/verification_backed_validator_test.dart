import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:test/test.dart';

void main() {
  test(
    'verifies a provider and current passing evidence without dominance',
    () {
      const workspace = _verificationWorkspace;
      final output = IrAdapterOutput(
        adapter: const AdapterDescriptor(id: 'fixture', version: '1'),
        inputDigest: 'fixture',
        completeness: const IrAdapterCompleteness(),
        symbols: const [
          ExtractedSymbol(
            kind: 'controlProvider',
            role: 'provider',
            symbolId: 'package:fixture/provider.dart#verified',
            controlIds: ['CTRL-VERIFIED'],
            providerKind: 'applicationValidator',
            layer: 'presentation',
            target: 'flutter',
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
      final digest = 'sha256:${List.filled(64, 'a').join()}';
      final evidence = EvidenceRecord(
        requirementId: 'RULE-VERIFIED',
        evidenceType: 'domain-unit',
        target: 'flutter',
        executionId: 'execution-verified',
        profile: 'pullRequest',
        controlIds: const ['CTRL-VERIFIED'],
        digests: {
          'source': digest,
          'contract': digest,
          'mapping': digest,
          'specificationIndex': digest,
          'result': digest,
        },
      );

      final result = VerificationBackedValidator().validate(
        workspace,
        [output],
        [evidence],
      );

      final proof = result.controlProofs.single;
      expect(result.errors, isEmpty);
      expect(proof.status, ProofStatus.verified);
      expect(proof.semantics, CoverageSemantics.verificationBacked);
      expect(
        proof.providerIds,
        contains('package:fixture/provider.dart#verified'),
      );
      expect(proof.evidenceDigests, isNotEmpty);
    },
  );

  test('fails verification-backed assurance when the provider is absent', () {
    const workspace = _verificationWorkspace;
    final result = VerificationBackedValidator().validate(
      workspace,
      const [],
      const [],
    );

    final proof = result.controlProofs.single;
    expect(proof.status, ProofStatus.missing);
    expect(
      proof.diagnostics,
      contains(
        'No resolved provider matches control kind, layer, target, and variant',
      ),
    );
    expect(
      proof.diagnostics,
      contains('No current passing evidence references this control'),
    );
  });

  test('rejects competing proof owners for one control obligation', () {
    final result = ValidatorEngine().validate(
      _verificationWorkspace,
      verifiedAttestationProofs: const [
        ControlProofResult(
          controlId: 'CTRL-VERIFIED',
          requirementId: 'RULE-VERIFIED',
          status: ProofStatus.verified,
          semantics: CoverageSemantics.externalAttestation,
          target: 'flutter',
        ),
      ],
    );

    expect(
      result.errors.map((error) => error.code),
      contains('ZK-PROOF-OWNER-CONFLICT'),
    );
    expect(result.controlProofs.single.status, ProofStatus.failed);
  });

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

const _verificationWorkspace = WorkspaceDiscoveryResult(
  config: ZukeConfig(),
  data: MetadataExtractorResult(
    controls: {
      'CTRL-VERIFIED': {
        'coverageSemantics': 'verification-backed',
        'acceptableProviderKinds': ['application-validator'],
        'requiredLayers': ['presentation'],
      },
    },
    features: [
      ParsedFeature(
        metadata: ParsedMetadata(
          id: 'FEAT-VERIFIED',
          source: SourceLocation(file: 'verified.feature', line: 1),
        ),
        tags: [],
        featureElement: GherkinElement(
          keyword: GherkinKeyword.feature,
          title: 'Verification-backed control',
          source: SourceLocation(file: 'verified.feature', line: 1),
        ),
        rules: [
          ParsedRule(
            metadata: ParsedMetadata(
              id: 'RULE-VERIFIED',
              requires: [
                ParsedControlRef(id: 'CTRL-VERIFIED', target: 'flutter'),
              ],
              source: SourceLocation(file: 'verified.feature', line: 2),
            ),
            tags: [],
            ruleElement: GherkinElement(
              keyword: GherkinKeyword.rule,
              title: 'A verified control',
              source: SourceLocation(file: 'verified.feature', line: 2),
            ),
            scenarios: [],
          ),
        ],
      ),
    ],
  ),
);
