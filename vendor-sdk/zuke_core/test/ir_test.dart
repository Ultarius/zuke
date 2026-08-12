import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/src/internal_ir.dart';
import 'package:test/test.dart';

void main() {
  test('canonical JSON sorts string keys and rejects non-string keys', () {
    expect(
      canonicalJson({
        'nested': {'b': 2, 'a': 1},
        'first': true,
      }),
      '{"first":true,"nested":{"a":1,"b":2}}',
    );
    expect(() => canonicalJson({1: 'numeric'}), throwsFormatException);
    expect(
      () => canonicalJson({
        'nested': {1: 'numeric'},
      }),
      throwsFormatException,
    );
  });

  group('ScenarioId', () {
    test('validates canonical IDs and preserves the v1 string value', () {
      final id = ScenarioId.parse('SCN-IR-ONE');
      expect(id.value, 'SCN-IR-ONE');
      expect(ScenarioId.tryParse('candidate-1'), isNull);
      expect(() => ScenarioId.parse('candidate-1'), throwsFormatException);
    });
  });

  test('canonical graph sorting is independent of insertion order', () {
    const first = IrGraph(
      nodes: [
        IrNode(id: 'b', kind: NodeKind.provider),
        IrNode(id: 'a', kind: NodeKind.entryPoint),
      ],
      edges: [IrEdge(sourceId: 'b', targetId: 'a', kind: EdgeKind.flowsTo)],
    );
    const second = IrGraph(
      nodes: [
        IrNode(id: 'a', kind: NodeKind.entryPoint),
        IrNode(id: 'b', kind: NodeKind.provider),
      ],
      edges: [IrEdge(sourceId: 'b', targetId: 'a', kind: EdgeKind.flowsTo)],
    );
    expect(first.canonicalDigestInput(), second.canonicalDigestInput());
  });

  test('dangling and duplicate graph structure is rejected', () {
    const graph = IrGraph(
      nodes: [
        IrNode(id: 'a', kind: NodeKind.entryPoint),
        IrNode(id: 'a', kind: NodeKind.provider),
      ],
      edges: [
        IrEdge(sourceId: 'a', targetId: 'missing', kind: EdgeKind.flowsTo),
      ],
    );
    expect(graph.validate(), contains('Duplicate IR node: a'));
    expect(graph.validate(), contains('Dangling edge: a->missing'));
  });

  test('typed proof and completeness records serialize', () {
    const result = ControlProofResult(
      controlId: 'CTRL-1',
      status: ProofStatus.proven,
      semantics: CoverageSemantics.ingressDominance,
      completeness: const {'routeRegistration': CompletenessValue.complete},
    );
    expect(result.toJson()['status'], 'proven');
    expect(result.toJson()['semantics'], 'ingress-dominance');
  });

  test('evidence records reject schema and digest lookalikes', () {
    expect(
      () => EvidenceRecord.fromJson({
        'schemaVersion': 'zuke.evidence-record.v1',
        'requirementId': 'RULE-1',
        'evidenceType': 'api-contract',
        'target': 'backend',
        'executionId': 'run-1',
        'status': 'passed',
        'digests': {'source': 'not-a-digest'},
      }),
      throwsFormatException,
    );
  });

  test('source spans normalize paths and reject unsafe or reversed ranges', () {
    final span = SourceSpan.fromJson({
      'path': r'lib\service.dart',
      'start': {'line': 2, 'column': 3},
      'end': {'line': 4, 'column': 5},
    });
    expect(span.toJson()['path'], 'lib/service.dart');
    for (final path in [
      '/absolute.dart',
      r'C:\absolute.dart',
      '../escape.dart',
      'file:///tmp/source.dart',
    ]) {
      expect(
        () => SourceSpan.fromJson({
          'path': path,
          'start': {'line': 1, 'column': 1},
        }),
        throwsFormatException,
      );
    }
    expect(
      () => SourceSpan.fromJson({
        'path': 'lib/source.dart',
        'start': {'line': 2, 'column': 2},
        'end': {'line': 1, 'column': 1},
      }),
      throwsFormatException,
    );
  });

  test('graph JSON round-trips typed nodes, edges, and completeness', () {
    const source = SourceSpan(
      path: 'lib/service.dart',
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: 10,
    );
    const graph = IrGraph(
      nodes: [
        IrNode(
          id: 'entry',
          kind: NodeKind.entryPoint,
          properties: {'route': '/items'},
          source: source,
        ),
        IrNode(id: 'sink', kind: NodeKind.sink),
      ],
      edges: [
        IrEdge(
          sourceId: 'entry',
          targetId: 'sink',
          kind: EdgeKind.flowsTo,
          properties: {'status': 200},
          source: source,
        ),
      ],
      completeness: GraphCompleteness(
        routeRegistration: CompletenessValue.complete,
        failureFlow: CompletenessValue.indeterminate,
        externalVisibility: CompletenessValue.notVisible,
      ),
    );

    final decoded = IrGraph.fromJson(graph.toJson());

    expect(
      decoded.nodes.singleWhere((node) => node.id == 'entry').source,
      isNotNull,
    );
    expect(decoded.edges.single.properties['status'], 200);
    expect(decoded.completeness.routeRegistration, CompletenessValue.complete);
    expect(decoded.validate(), isEmpty);
  });

  test(
    'graph validation detects provider identities, edges, and flow cycles',
    () {
      const graph = IrGraph(
        nodes: [
          IrNode(
            id: 'provider-a',
            kind: NodeKind.provider,
            target: 'backend',
            properties: {'controlId': 'CTRL-1'},
          ),
          IrNode(
            id: 'provider-b',
            kind: NodeKind.provider,
            target: 'backend',
            properties: {'controlId': 'CTRL-1'},
          ),
        ],
        edges: [
          IrEdge(
            sourceId: 'provider-a',
            targetId: 'provider-b',
            kind: EdgeKind.flowsTo,
          ),
          IrEdge(
            sourceId: 'provider-b',
            targetId: 'provider-a',
            kind: EdgeKind.flowsTo,
          ),
          IrEdge(
            sourceId: 'provider-b',
            targetId: 'provider-a',
            kind: EdgeKind.flowsTo,
          ),
        ],
      );

      final diagnostics = graph.validate();

      expect(diagnostics, contains(contains('Duplicate provider identity')));
      expect(diagnostics, contains(contains('Duplicate IR edge')));
      expect(diagnostics, contains(contains('Runtime flow cycle')));
    },
  );

  test('adapter model JSON keeps supported optional fields and ordering', () {
    const source = ExtractedSourceLocation(
      uri: 'lib/service.dart',
      offset: 1,
      length: 2,
      line: 3,
      column: 4,
    );
    const symbol = ExtractedSymbol(
      kind: 'binding',
      role: 'flutter',
      symbolId: 'service.dart#binding',
      requirementIds: ['RULE-B', 'RULE-A'],
      controlIds: ['CTRL-B', 'CTRL-A'],
      bindingId: 'binding-id',
      providerKind: 'applicationValidator',
      layer: 'presentation',
      target: 'flutter',
      evidenceType: 'gherkin-ui',
      scenarioIds: ['SCN-B', 'SCN-A'],
      source: source,
    );
    const diagnostic = IrDiagnostic(
      code: 'TEST-001',
      message: 'failure',
      severity: IrDiagnosticSeverity.error,
      source: 'source',
    );
    const output = IrAdapterOutput(
      adapter: AdapterDescriptor(
        id: 'dart',
        version: '0.1.0',
        compatibilityId: 'dart-v1',
      ),
      completeness: IrAdapterCompleteness(
        annotationTargets: CompletenessValue.indeterminate,
      ),
      symbols: [symbol],
      inputDigest: 'sha256:digest',
      diagnostics: [diagnostic],
      packageName: 'fixture',
      packageRoot: '/fixture',
    );

    final json = output.toJson();

    expect(output.errors, ['failure']);
    expect(diagnostic.toString(), 'TEST-001: failure');
    expect(
      (json['symbols'] as List).single,
      containsPair('bindingId', 'binding-id'),
    );
    expect(json, containsPair('packageName', 'fixture'));
  });
}
