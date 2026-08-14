import 'package:test/test.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  group('DominanceValidator', () {
    test('passes when provider dominates implementation', () {
      const graph = IrGraph(
        nodes: [
          IrNode(id: 'fixture:request-ingress', kind: NodeKind.entryPoint),
          IrNode(
            id: 'provider:mw',
            kind: NodeKind.provider,
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:ctrl',
            kind: NodeKind.implementation,
            properties: {
              'requiredControls': ['CTRL-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'fixture:request-ingress',
            targetId: 'provider:mw',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:mw',
            targetId: 'implementation:ctrl',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final result = DominanceValidator().validate(graph);
      expect(result.passed, isTrue);
      expect(result.errors, isEmpty);
    });

    test('preserves target and variant in an application proof key', () {
      const graph = IrGraph(
        nodes: [
          IrNode(id: 'ingress', kind: NodeKind.entryPoint, target: 'backend'),
          IrNode(
            id: 'provider:mw',
            kind: NodeKind.provider,
            target: 'backend',
            variant: 'default',
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:ctrl',
            kind: NodeKind.implementation,
            target: 'backend',
            variant: 'default',
            properties: {
              'requirementIds': ['RULE-CALC-BODY-SIZE'],
              'requiredControls': ['CTRL-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'ingress',
            targetId: 'provider:mw',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:mw',
            targetId: 'implementation:ctrl',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final proof = DominanceValidator().validate(graph).controlProofs.single;
      expect(proof.target, 'backend');
      expect(proof.variant, 'default');
    });

    test('does not prove ingress when dynamic registration is incomplete', () {
      const graph = IrGraph(
        completeness: GraphCompleteness(
          routeRegistration: CompletenessValue.complete,
          middlewareOrder: CompletenessValue.complete,
          dynamicRegistration: CompletenessValue.indeterminate,
        ),
        nodes: [
          IrNode(id: 'ingress', kind: NodeKind.entryPoint),
          IrNode(
            id: 'provider:middleware',
            kind: NodeKind.provider,
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:controller',
            kind: NodeKind.implementation,
            properties: {
              'requiredControls': ['CTRL-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'ingress',
            targetId: 'provider:middleware',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:middleware',
            targetId: 'implementation:controller',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final proof = DominanceValidator().validate(graph).controlProofs.single;

      expect(proof.status, ProofStatus.indeterminate);
    });

    test('requires external visibility for an edge-target ingress proof', () {
      const graph = IrGraph(
        completeness: GraphCompleteness(
          routeRegistration: CompletenessValue.complete,
          middlewareOrder: CompletenessValue.complete,
          dynamicRegistration: CompletenessValue.complete,
          externalVisibility: CompletenessValue.notVisible,
        ),
        nodes: [
          IrNode(id: 'ingress', kind: NodeKind.entryPoint, target: 'edge'),
          IrNode(
            id: 'provider:edge-policy',
            kind: NodeKind.provider,
            target: 'edge',
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:edge-route',
            kind: NodeKind.implementation,
            target: 'edge',
            properties: {
              'requiredControls': ['CTRL-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'ingress',
            targetId: 'provider:edge-policy',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:edge-policy',
            targetId: 'implementation:edge-route',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final proof = DominanceValidator().validate(graph).controlProofs.single;

      expect(proof.status, ProofStatus.indeterminate);
    });

    test('fails CONTROL-DOMINANCE-002 when bypass route exists (MVP #10)', () {
      const graph = IrGraph(
        nodes: [
          IrNode(id: 'fixture:request-ingress', kind: NodeKind.entryPoint),
          IrNode(
            id: 'provider:mw',
            kind: NodeKind.provider,
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:ctrl',
            kind: NodeKind.implementation,
            properties: {
              'requiredControls': ['CTRL-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          // Protected route
          IrEdge(
            sourceId: 'fixture:request-ingress',
            targetId: 'provider:mw',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:mw',
            targetId: 'implementation:ctrl',
            kind: EdgeKind.routesTo,
          ),
          // Unprotected bypass route directly to implementation!
          IrEdge(
            sourceId: 'fixture:request-ingress',
            targetId: 'implementation:ctrl',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final result = DominanceValidator().validate(graph);
      expect(result.passed, isFalse);
      expect(
        result.errors.any((msg) => msg.code == 'CONTROL-DOMINANCE-002'),
        isTrue,
      );
    });

    test('rejects a dangling governed-graph edge', () {
      const graph = IrGraph(
        nodes: [
          IrNode(id: 'implementation:ctrl', kind: NodeKind.implementation),
        ],
        edges: [
          IrEdge(
            sourceId: 'missing:provider',
            targetId: 'implementation:ctrl',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final result = DominanceValidator().validate(graph);

      expect(
        result.errors.map((error) => error.code),
        contains('IR-GRAPH-001'),
      );
    });

    test('does not accept a provider from another target or variant', () {
      const graph = IrGraph(
        nodes: [
          IrNode(id: 'ingress', kind: NodeKind.entryPoint, target: 'backend'),
          IrNode(
            id: 'provider:flutter-phone',
            kind: NodeKind.provider,
            target: 'flutter',
            variant: 'phone',
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:backend-default',
            kind: NodeKind.implementation,
            target: 'backend',
            variant: 'default',
            properties: {
              'requiredControls': ['CTRL-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'ingress',
            targetId: 'provider:flutter-phone',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:flutter-phone',
            targetId: 'implementation:backend-default',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final proof = DominanceValidator().validate(graph).controlProofs.single;

      expect(proof.status, ProofStatus.missing);
    });

    test('does not evaluate a control declared for another target', () {
      const workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(),
        data: MetadataExtractorResult(
          controls: {
            'CTRL-BACKEND-ONLY': {'coverageSemantics': 'ingress-dominance'},
          },
          features: [
            ParsedFeature(
              tags: [],
              featureElement: GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Target isolation',
                source: SourceLocation(file: 'target.feature', line: 1),
              ),
              metadata: ParsedMetadata(
                id: 'FEAT-TARGET',
                source: SourceLocation(file: 'target.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'Backend control',
                    source: SourceLocation(file: 'target.feature', line: 2),
                  ),
                  metadata: ParsedMetadata(
                    id: 'RULE-BACKEND-ONLY',
                    requires: [
                      ParsedControlRef(
                        id: 'CTRL-BACKEND-ONLY',
                        target: 'backend',
                      ),
                    ],
                    source: SourceLocation(file: 'target.feature', line: 2),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );
      const graph = IrGraph(
        nodes: [
          IrNode(
            id: 'implementation:flutter-domain',
            kind: NodeKind.implementation,
            target: 'flutter',
            properties: {
              'requirementIds': ['RULE-BACKEND-ONLY'],
            },
          ),
        ],
      );

      final result = DominanceValidator().validate(graph, workspace: workspace);

      expect(result.errors, isEmpty);
      expect(result.controlProofs, isEmpty);
    });

    test('does not send verification-backed controls through dominance', () {
      const workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(),
        data: MetadataExtractorResult(
          controls: {
            'CTRL-VERIFIED': {'coverageSemantics': 'verification-backed'},
          },
          features: [
            ParsedFeature(
              tags: [],
              featureElement: GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Verification-backed control',
                source: SourceLocation(file: 'verified.feature', line: 1),
              ),
              metadata: ParsedMetadata(
                id: 'FEAT-VERIFIED',
                source: SourceLocation(file: 'verified.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [],
                  ruleElement: GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'A verified control',
                    source: SourceLocation(file: 'verified.feature', line: 2),
                  ),
                  metadata: ParsedMetadata(
                    id: 'RULE-VERIFIED',
                    requires: [
                      ParsedControlRef(id: 'CTRL-VERIFIED', target: 'flutter'),
                    ],
                    source: SourceLocation(file: 'verified.feature', line: 2),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );
      const graph = IrGraph(
        nodes: [
          IrNode(
            id: 'implementation:flutter-controller',
            kind: NodeKind.implementation,
            target: 'flutter',
            properties: {
              'requirementIds': ['RULE-VERIFIED'],
            },
          ),
        ],
      );

      final result = DominanceValidator().validate(graph, workspace: workspace);

      expect(result.errors, isEmpty);
      expect(result.controlProofs, isEmpty);
    });

    test(
      'does not compose disjoint partial providers into a dominance proof',
      () {
        const graph = IrGraph(
          nodes: [
            IrNode(id: 'ingress:a', kind: NodeKind.entryPoint),
            IrNode(id: 'ingress:b', kind: NodeKind.entryPoint),
            IrNode(
              id: 'provider:a',
              kind: NodeKind.provider,
              properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
            ),
            IrNode(
              id: 'provider:b',
              kind: NodeKind.provider,
              properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
            ),
            IrNode(
              id: 'implementation:ctrl',
              kind: NodeKind.implementation,
              properties: {
                'requiredControls': ['CTRL-CALC-BODY-SIZE'],
              },
            ),
          ],
          edges: [
            IrEdge(
              sourceId: 'ingress:a',
              targetId: 'provider:a',
              kind: EdgeKind.precedes,
            ),
            IrEdge(
              sourceId: 'provider:a',
              targetId: 'implementation:ctrl',
              kind: EdgeKind.routesTo,
            ),
            IrEdge(
              sourceId: 'ingress:b',
              targetId: 'provider:b',
              kind: EdgeKind.precedes,
            ),
            IrEdge(
              sourceId: 'provider:b',
              targetId: 'implementation:ctrl',
              kind: EdgeKind.routesTo,
            ),
          ],
        );

        final result = DominanceValidator().validate(graph);

        expect(result.controlProofs.single.status, ProofStatus.failed);
        expect(
          result.errors.map((error) => error.code),
          contains('CONTROL-DOMINANCE-002'),
        );
      },
    );

    test('requires an explicit known coverage semantic in a workspace', () {
      const graph = IrGraph(
        nodes: [
          IrNode(id: 'ingress', kind: NodeKind.entryPoint),
          IrNode(
            id: 'provider:mw',
            kind: NodeKind.provider,
            properties: {'controlId': 'CTRL-CALC-BODY-SIZE'},
          ),
          IrNode(
            id: 'implementation:ctrl',
            kind: NodeKind.implementation,
            properties: {
              'requirementIds': ['RULE-CALC-BODY-SIZE'],
            },
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'ingress',
            targetId: 'provider:mw',
            kind: EdgeKind.precedes,
          ),
          IrEdge(
            sourceId: 'provider:mw',
            targetId: 'implementation:ctrl',
            kind: EdgeKind.routesTo,
          ),
        ],
      );

      final result = DominanceValidator().validate(
        graph,
        workspace: _workspaceWithoutCoverageSemantics(),
      );

      expect(result.controlProofs.single.status, ProofStatus.indeterminate);
      expect(
        result.errors.map((error) => error.code),
        contains('CONTROL-SEMANTICS-001'),
      );
    });

    test(
      'fails CONTROL-ERROR-FLOW-003 when error path bypasses mapper (MVP #11)',
      () {
        const graph = IrGraph(
          nodes: [
            IrNode(id: 'fixture:request-ingress', kind: NodeKind.entryPoint),
            IrNode(
              id: 'implementation:ctrl',
              kind: NodeKind.implementation,
              properties: {
                'requiredControls': ['CTRL-CALC-ERROR-REDACTION'],
                'coverageSemantics': 'failure-to-public-egress',
              },
            ),
            IrNode(
              id: 'egress:public-http-response',
              kind: NodeKind.entryPoint,
            ),
          ],
          edges: [
            // Unprotected failure path directly to public egress without error mapper
            IrEdge(
              sourceId: 'implementation:ctrl',
              targetId: 'egress:public-http-response',
              kind: EdgeKind.routesTo,
            ),
          ],
        );

        final result = DominanceValidator().validate(graph);
        expect(result.passed, isFalse);
        expect(
          result.errors.any((msg) => msg.code == 'CONTROL-ERROR-FLOW-003'),
          isTrue,
        );
      },
    );

    test(
      'fails CONTROL-LOG-FLOW-004 when raw logging bypass exists (MVP #12)',
      () {
        const graph = IrGraph(
          nodes: [
            IrNode(id: 'fixture:request-ingress', kind: NodeKind.entryPoint),
            IrNode(
              id: 'implementation:ctrl',
              kind: NodeKind.implementation,
              properties: {
                'requiredControls': ['CTRL-CALC-LOG-REDACTION'],
                'coverageSemantics': 'sensitive-data-to-log-sink',
              },
            ),
            IrNode(id: 'sink:app-log-sink', kind: NodeKind.entryPoint),
          ],
          edges: [
            // Raw logger path directly to application log sink bypassing log interceptor
            IrEdge(
              sourceId: 'implementation:ctrl',
              targetId: 'sink:app-log-sink',
              kind: EdgeKind.routesTo,
            ),
          ],
        );

        final result = DominanceValidator().validate(graph);
        expect(result.passed, isFalse);
        expect(
          result.errors.any((msg) => msg.code == 'CONTROL-LOG-FLOW-004'),
          isTrue,
        );
      },
    );

    test(
      'fails a disconnected governed failure graph instead of proving it',
      () {
        const graph = IrGraph(
          nodes: [
            IrNode(
              id: 'implementation:ctrl',
              kind: NodeKind.implementation,
              properties: {
                'requiredControls': ['CTRL-CALC-ERROR-REDACTION'],
                'coverageSemantics': 'failure-to-public-egress',
              },
            ),
            IrNode(
              id: 'failure:controller',
              kind: NodeKind.entryPoint,
              properties: {'flow': 'failure'},
            ),
            IrNode(
              id: 'provider:mapper',
              kind: NodeKind.provider,
              properties: {'controlId': 'CTRL-CALC-ERROR-REDACTION'},
            ),
            IrNode(
              id: 'egress:public',
              kind: NodeKind.entryPoint,
              properties: {'flow': 'public-egress'},
            ),
          ],
          edges: [
            IrEdge(
              sourceId: 'failure:controller',
              targetId: 'provider:mapper',
              kind: EdgeKind.flowsTo,
            ),
          ],
        );

        final result = DominanceValidator().validate(graph);
        final proof = result.controlProofs.single;
        expect(proof.status, ProofStatus.failed);
        expect(
          proof.bypassPaths,
          contains('failure:controller -> <no path to> egress:public'),
        );
      },
    );
  });
}

WorkspaceDiscoveryResult _workspaceWithoutCoverageSemantics() =>
    WorkspaceDiscoveryResult(
      config: const ZukeConfig(),
      data: MetadataExtractorResult(
        controls: {
          'CTRL-CALC-BODY-SIZE': {'id': 'CTRL-CALC-BODY-SIZE'},
        },
        features: [
          ParsedFeature(
            tags: const [],
            featureElement: const GherkinElement(
              keyword: GherkinKeyword.feature,
              title: 'Calculator',
              source: SourceLocation(file: 'calculator.feature', line: 1),
            ),
            metadata: const ParsedMetadata(
              id: 'FEAT-CALC',
              source: SourceLocation(file: 'calculator.feature', line: 1),
            ),
            rules: [
              ParsedRule(
                tags: const [],
                ruleElement: const GherkinElement(
                  keyword: GherkinKeyword.rule,
                  title: 'Body size',
                  source: SourceLocation(file: 'calculator.feature', line: 2),
                ),
                metadata: const ParsedMetadata(
                  id: 'RULE-CALC-BODY-SIZE',
                  requires: [ParsedControlRef(id: 'CTRL-CALC-BODY-SIZE')],
                  source: SourceLocation(file: 'calculator.feature', line: 2),
                ),
                scenarios: const [],
              ),
            ],
          ),
        ],
      ),
    );
