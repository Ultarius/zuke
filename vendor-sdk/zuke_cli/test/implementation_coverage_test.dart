import 'package:test/test.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  test(
    'annotation-governed implementation coverage requires claimed evidence',
    () {
      final output = _output(
        symbols: const [
          ExtractedSymbol(
            kind: 'requirementBoundary',
            role: 'domain',
            symbolId: 'package:fixture/use_case.dart#CreateLobbyUseCase',
            requirementIds: ['RULE-ACCESS-NORMALIZATION'],
            target: 'backend',
            source: ExtractedSourceLocation(
              uri: 'package:fixture/use_case.dart',
              offset: 0,
              length: 1,
              line: 1,
              column: 1,
            ),
          ),
        ],
        graph: IrGraph(
          nodes: [
            IrNode(
              id: 'implementation:package:fixture/use_case.dart#CreateLobbyUseCase',
              kind: NodeKind.implementation,
              target: 'backend',
              role: 'implementation',
              variant: 'default',
              slot: 'primary',
              properties: const {
                'requirementIds': ['RULE-ACCESS-NORMALIZATION'],
              },
            ),
          ],
        ),
      );
      final result = ValidatorEngine().validate(_workspace, outputs: [output]);

      expect(
        result.implementationCoverage.single.mode,
        PlacementMode.annotationGoverned,
      );
      expect(result.implementationCoverage.single.status, ProofStatus.missing);
      expect(
        result.errors.map((error) => error.code),
        contains('ZK-IMPL-EVIDENCE-MISSING'),
      );
    },
  );

  test(
    'annotation-governed implementation coverage accepts current slot evidence',
    () {
      final output = _output(
        symbols: const [
          ExtractedSymbol(
            kind: 'requirementBoundary',
            role: 'domain',
            symbolId: 'package:fixture/use_case.dart#CreateLobbyUseCase',
            requirementIds: ['RULE-ACCESS-NORMALIZATION'],
            target: 'backend',
            source: ExtractedSourceLocation(
              uri: 'package:fixture/use_case.dart',
              offset: 0,
              length: 1,
              line: 1,
              column: 1,
            ),
          ),
        ],
        graph: IrGraph(
          nodes: [
            IrNode(
              id: 'implementation:package:fixture/use_case.dart#CreateLobbyUseCase',
              kind: NodeKind.implementation,
              target: 'backend',
              role: 'implementation',
              variant: 'default',
              slot: 'primary',
              properties: const {
                'requirementIds': ['RULE-ACCESS-NORMALIZATION'],
              },
            ),
          ],
        ),
      );
      const digest =
          'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final result = ValidatorEngine().validate(
        _workspace,
        outputs: [output],
        evidenceRecords: [
          EvidenceRecord(
            requirementId: 'RULE-ACCESS-NORMALIZATION',
            evidenceType: 'domain-unit',
            target: 'backend',
            executionId: 'execution-1',
            profile: 'pullRequest',
            implementationSlots: ['primary'],
            digests: const {
              'source': digest,
              'contract': digest,
              'mapping': digest,
              'specificationIndex': digest,
              'result': digest,
            },
          ),
        ],
      );

      expect(result.implementationCoverage.single.status, ProofStatus.verified);
      expect(result.implementationCoverage.single.evidenceDigests, isNotEmpty);
    },
  );

  test('duplicate semantic bindings fail before proof routing', () {
    const symbol = ExtractedSymbol(
      kind: 'requirementBoundary',
      role: 'domain',
      symbolId: 'package:fixture/use_case.dart#CreateLobbyUseCase',
      requirementIds: ['RULE-ACCESS-NORMALIZATION'],
      target: 'backend',
      source: ExtractedSourceLocation(
        uri: 'package:fixture/use_case.dart',
        offset: 0,
        length: 1,
        line: 1,
        column: 1,
      ),
    );
    final result = ValidatorEngine().validate(
      _workspace,
      outputs: [
        _output(symbols: const [symbol, symbol], graph: const IrGraph()),
      ],
    );

    expect(
      result.errors.map((error) => error.code),
      contains('ZK-BINDING-IDENTITY-DUPLICATE'),
    );
  });

  test('topology-authoritative implementation coverage does not need evidence', () {
    final output = _output(
      symbols: const [
        ExtractedSymbol(
          kind: 'requirementBoundary',
          role: 'domain',
          symbolId: 'package:fixture/use_case.dart#CreateLobbyUseCase',
          requirementIds: ['RULE-ACCESS-NORMALIZATION'],
          target: 'backend',
          source: ExtractedSourceLocation(
            uri: 'package:fixture/use_case.dart',
            offset: 0,
            length: 1,
            line: 1,
            column: 1,
          ),
        ),
      ],
      graph: IrGraph(
        nodes: [
          const IrNode(
            id: 'route',
            kind: NodeKind.entryPoint,
            target: 'backend',
          ),
          IrNode(
            id: 'implementation:package:fixture/use_case.dart#CreateLobbyUseCase',
            kind: NodeKind.implementation,
            target: 'backend',
            role: 'implementation',
            variant: 'default',
            slot: 'primary',
            properties: const {
              'requirementIds': ['RULE-ACCESS-NORMALIZATION'],
            },
          ),
        ],
        edges: const [
          IrEdge(
            sourceId: 'route',
            targetId:
                'implementation:package:fixture/use_case.dart#CreateLobbyUseCase',
            kind: EdgeKind.invokes,
          ),
        ],
      ),
    );
    final result = ValidatorEngine().validate(_workspace, outputs: [output]);

    expect(
      result.implementationCoverage.single.mode,
      PlacementMode.topologyAuthoritative,
    );
    expect(result.implementationCoverage.single.status, ProofStatus.proven);
    expect(result.errors, isEmpty);
  });

  test('implementation slots are independent AND obligations', () {
    final symbols = [
      for (final slot in ['create', 'join'])
        ExtractedSymbol(
          kind: 'requirementBoundary',
          role: 'domain',
          symbolId: 'package:fixture/use_case.dart#${slot}UseCase',
          requirementIds: const ['RULE-ACCESS-NORMALIZATION'],
          target: 'backend',
          slot: slot,
          source: ExtractedSourceLocation(
            uri: 'package:fixture/use_case.dart',
            offset: 0,
            length: 1,
            line: 1,
            column: 1,
          ),
        ),
    ];
    final result = ValidatorEngine().validate(
      _workspace,
      outputs: [
        _output(
          symbols: symbols,
          graph: IrGraph(
            nodes: [
              for (final slot in ['create', 'join'])
                IrNode(
                  id: 'implementation:package:fixture/use_case.dart#${slot}UseCase',
                  kind: NodeKind.implementation,
                  target: 'backend',
                  role: 'implementation',
                  variant: 'default',
                  slot: slot,
                  properties: const {
                    'requirementIds': ['RULE-ACCESS-NORMALIZATION'],
                  },
                ),
            ],
          ),
        ),
      ],
    );

    expect(result.implementationCoverage, hasLength(2));
    expect(
      result.implementationCoverage.map((coverage) => coverage.binding.slot),
      containsAll(['create', 'join']),
    );
    expect(
      result.implementationCoverage.every(
        (coverage) => coverage.status == ProofStatus.missing,
      ),
      isTrue,
    );
  });
}

const _workspace = WorkspaceDiscoveryResult(
  config: ZukeConfig(),
  data: MetadataExtractorResult(
    features: [
      ParsedFeature(
        metadata: ParsedMetadata(
          schemaVersion: '1',
          id: 'FEAT-IMPL-001',
          source: SourceLocation(file: 'implementation.feature', line: 1),
        ),
        tags: [
          GherkinTag(
            name: 'FEAT-IMPL-001',
            source: SourceLocation(file: 'implementation.feature', line: 1),
          ),
        ],
        featureElement: GherkinElement(
          keyword: GherkinKeyword.feature,
          title: 'Implementation coverage',
          source: SourceLocation(file: 'implementation.feature', line: 1),
        ),
        rules: [
          ParsedRule(
            metadata: ParsedMetadata(
              id: 'RULE-ACCESS-NORMALIZATION',
              source: SourceLocation(file: 'implementation.feature', line: 2),
            ),
            tags: [
              GherkinTag(
                name: 'RULE-ACCESS-NORMALIZATION',
                source: SourceLocation(file: 'implementation.feature', line: 2),
              ),
            ],
            ruleElement: GherkinElement(
              keyword: GherkinKeyword.rule,
              title: 'Implementation coverage is required',
              source: SourceLocation(file: 'implementation.feature', line: 2),
            ),
            scenarios: [],
          ),
        ],
      ),
    ],
  ),
);

IrAdapterOutput _output({
  required List<ExtractedSymbol> symbols,
  required IrGraph graph,
}) => IrAdapterOutput(
  adapter: const AdapterDescriptor(id: 'fixture', version: '1'),
  completeness: const IrAdapterCompleteness(),
  symbols: symbols,
  inputDigest: 'fixture',
  packageName: 'fixture',
  graph: graph,
);
