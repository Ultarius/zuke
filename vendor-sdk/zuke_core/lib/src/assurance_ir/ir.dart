/// Canonical stack-neutral assurance graph model.

import 'canonical_json.dart';

class SourceSpan {
  final String path;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;

  const SourceSpan({
    required this.path,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  });

  factory SourceSpan.fromJson(Map<String, Object?> json) {
    final path = json['path'] as String?;
    if (path == null ||
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        path.startsWith('\\\\') ||
        path.startsWith('file:') ||
        path.split('/').contains('..')) {
      throw const FormatException('SourceSpan path must be workspace-relative');
    }
    final start = (json['start'] as Map?)?.cast<String, Object?>() ?? const {};
    final end = (json['end'] as Map?)?.cast<String, Object?>() ?? start;
    final startLine = start['line'] as int;
    final startColumn = start['column'] as int;
    final endLine = end['line'] as int;
    final endColumn = end['column'] as int;
    if (startLine < 1 ||
        startColumn < 1 ||
        endLine < startLine ||
        (endLine == startLine && endColumn < startColumn) ||
        endColumn < 1) {
      throw const FormatException(
        'SourceSpan positions must be one-based and ordered',
      );
    }
    return SourceSpan(
      path: path.replaceAll('\\', '/'),
      startLine: startLine,
      startColumn: startColumn,
      endLine: endLine,
      endColumn: endColumn,
    );
  }

  Map<String, Object?> toJson() {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
        normalized.startsWith('//') ||
        normalized.startsWith('file:') ||
        normalized.split('/').contains('..')) {
      throw const FormatException('SourceSpan path must be workspace-relative');
    }
    return {
      'path': normalized,
      'start': {'line': startLine, 'column': startColumn},
      'end': {'line': endLine, 'column': endColumn},
    };
  }
}

enum NodeKind {
  requirement,
  capability,
  implementation,
  entryPoint,
  enforcementPoint,
  provider,
  sink,
  evidence,
  attestation,
  externalBoundary,
  policy,
  release,
}

enum EdgeKind {
  requires_,
  implements_,
  provides,
  verifies,
  routesTo,
  invokes,
  precedes,
  flowsTo,
  appliesTo,
  attestsTo,
  excludes,
  supersedes,
}

enum CoverageSemantics {
  ingressDominance,
  failureToPublicEgress,
  sensitiveDataToLogSink,
  externalAttestation,
  verificationBacked,
}

enum CompletenessValue { complete, indeterminate, notVisible, notApplicable }

class GraphCompleteness {
  final CompletenessValue routeRegistration;
  final CompletenessValue middlewareOrder;
  final CompletenessValue failureFlow;
  final CompletenessValue logFlow;
  final CompletenessValue dynamicRegistration;
  final CompletenessValue externalVisibility;

  const GraphCompleteness({
    this.routeRegistration = CompletenessValue.notApplicable,
    this.middlewareOrder = CompletenessValue.notApplicable,
    this.failureFlow = CompletenessValue.notApplicable,
    this.logFlow = CompletenessValue.notApplicable,
    this.dynamicRegistration = CompletenessValue.notApplicable,
    this.externalVisibility = CompletenessValue.notApplicable,
  });

  String value(CompletenessValue value) => switch (value) {
    CompletenessValue.complete => 'complete',
    CompletenessValue.indeterminate => 'indeterminate',
    CompletenessValue.notVisible => 'notVisible',
    CompletenessValue.notApplicable => 'notApplicable',
  };

  Map<String, String> toJson() => {
    'routeRegistration': value(routeRegistration),
    'middlewareOrder': value(middlewareOrder),
    'failureFlow': value(failureFlow),
    'logFlow': value(logFlow),
    'dynamicRegistration': value(dynamicRegistration),
    'externalVisibility': value(externalVisibility),
  };
}

class IrNode {
  final String id;
  final NodeKind kind;
  final String? target;
  final String? role;
  final String? variant;
  final String? slot;
  final Map<String, Object?> properties;
  final SourceSpan? source;

  const IrNode({
    required this.id,
    required this.kind,
    this.target,
    this.role,
    this.variant,
    this.slot,
    this.properties = const {},
    this.source,
  });

  factory IrNode.fromJson(Map<String, Object?> json) => IrNode(
    id: json['id'] as String,
    kind: NodeKind.values.byName(json['kind'] as String),
    target: json['target'] as String?,
    role: json['role'] as String?,
    variant: json['variant'] as String?,
    slot: json['slot'] as String?,
    properties: ((json['properties'] as Map?) ?? const {})
        .cast<String, Object?>(),
    source: json['source'] is Map
        ? SourceSpan.fromJson((json['source'] as Map).cast<String, Object?>())
        : null,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    if (target != null) 'target': target,
    if (role != null) 'role': role,
    if (variant != null) 'variant': variant,
    if (slot != null) 'slot': slot,
    if (properties.isNotEmpty) 'properties': properties,
    if (source != null) 'source': source!.toJson(),
  };
}

class IrEdge {
  final String sourceId;
  final String targetId;
  final EdgeKind kind;
  final Map<String, Object?> properties;
  final SourceSpan? source;

  const IrEdge({
    required this.sourceId,
    required this.targetId,
    required this.kind,
    this.properties = const {},
    this.source,
  });

  factory IrEdge.fromJson(Map<String, Object?> json) => IrEdge(
    sourceId: json['source'] as String,
    targetId: json['target'] as String,
    kind: EdgeKind.values.byName(json['kind'] as String),
    properties: ((json['properties'] as Map?) ?? const {})
        .cast<String, Object?>(),
    source: json['location'] is Map
        ? SourceSpan.fromJson((json['location'] as Map).cast<String, Object?>())
        : null,
  );

  Map<String, Object?> toJson() => {
    'source': sourceId,
    'target': targetId,
    'kind': kind.name,
    if (properties.isNotEmpty) 'properties': properties,
    if (source != null) 'location': source!.toJson(),
  };
}

class IrGraph {
  final List<IrNode> nodes;
  final List<IrEdge> edges;
  final GraphCompleteness completeness;

  const IrGraph({
    this.nodes = const [],
    this.edges = const [],
    this.completeness = const GraphCompleteness(),
  });

  factory IrGraph.fromJson(Map<String, Object?> json) {
    final nodes = ((json['nodes'] as List?) ?? const [])
        .map((node) => IrNode.fromJson((node as Map).cast<String, Object?>()))
        .toList(growable: false);
    final edges = ((json['edges'] as List?) ?? const [])
        .map((edge) => IrEdge.fromJson((edge as Map).cast<String, Object?>()))
        .toList(growable: false);
    final c = ((json['completeness'] as Map?) ?? const {})
        .cast<String, Object?>();
    CompletenessValue parse(Object? value) => switch (value) {
      'complete' => CompletenessValue.complete,
      'indeterminate' => CompletenessValue.indeterminate,
      'notVisible' => CompletenessValue.notVisible,
      'notApplicable' => CompletenessValue.notApplicable,
      _ => throw FormatException('Unknown graph completeness value: $value'),
    };
    final graph = IrGraph(
      nodes: nodes,
      edges: edges,
      completeness: GraphCompleteness(
        routeRegistration: parse(c['routeRegistration']),
        middlewareOrder: parse(c['middlewareOrder']),
        failureFlow: parse(c['failureFlow']),
        logFlow: parse(c['logFlow']),
        dynamicRegistration: parse(c['dynamicRegistration']),
        externalVisibility: parse(c['externalVisibility']),
      ),
    );
    final errors = graph.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join('; '));
    return graph;
  }

  Set<String> get nodeIds => nodes.map((node) => node.id).toSet();

  List<String> validate() {
    final diagnostics = <String>[];
    final seen = <String>{};
    final identityKeys = <String>{};
    for (final node in nodes) {
      if (node.id.trim().isEmpty) diagnostics.add('IR node id is empty');
      if (!seen.add(node.id)) diagnostics.add('Duplicate IR node: ${node.id}');
      if (node.kind == NodeKind.provider) {
        final control = node.properties['controlId'];
        if (control is String) {
          final key =
              '$control|${node.target ?? 'backend'}|${node.variant ?? 'default'}|${node.slot ?? 'primary'}';
          if (!identityKeys.add(key))
            diagnostics.add('Duplicate provider identity: $key');
        }
      }
      if (node.kind == NodeKind.implementation) {
        final requirements = node.properties['requirementIds'];
        if (requirements is List) {
          for (final requirement in requirements.whereType<String>()) {
            final key =
                '$requirement|${node.target ?? 'backend'}|${node.role ?? 'implementation'}|${node.variant ?? 'default'}|${node.slot ?? 'primary'}';
            if (!identityKeys.add(key))
              diagnostics.add('Duplicate implementation identity: $key');
          }
        }
      }
    }
    final edges = <String>{};
    for (final edge in this.edges) {
      if (!seen.contains(edge.sourceId) || !seen.contains(edge.targetId)) {
        diagnostics.add('Dangling edge: ${edge.sourceId}->${edge.targetId}');
      }
      final key = '${edge.sourceId}|${edge.targetId}|${edge.kind.name}';
      if (!edges.add(key)) diagnostics.add('Duplicate IR edge: $key');
    }
    for (final cycle in flowCycles()) {
      diagnostics.add('Runtime flow cycle: ${cycle.join(' -> ')}');
    }
    return diagnostics;
  }

  List<List<String>> flowCycles() {
    final adjacency = <String, List<String>>{};
    for (final edge in edges) {
      if (edge.kind == EdgeKind.flowsTo || edge.kind == EdgeKind.routesTo) {
        (adjacency[edge.sourceId] ??= []).add(edge.targetId);
      }
    }
    final cycles = <List<String>>[];
    final visiting = <String>{};
    final visited = <String>{};
    final path = <String>[];
    void visit(String node) {
      if (visiting.contains(node)) {
        final start = path.indexOf(node);
        if (start >= 0) cycles.add([...path.sublist(start), node]);
        return;
      }
      if (!visited.add(node)) return;
      visiting.add(node);
      path.add(node);
      for (final target in adjacency[node] ?? const <String>[]) visit(target);
      path.removeLast();
      visiting.remove(node);
    }

    for (final node in adjacency.keys.toList()..sort()) visit(node);
    return cycles;
  }

  List<String> danglingEdges() => edges
      .where(
        (edge) =>
            !nodeIds.contains(edge.sourceId) ||
            !nodeIds.contains(edge.targetId),
      )
      .map((edge) => '${edge.sourceId}->${edge.targetId}')
      .toList(growable: false);

  Map<String, Object?> toJson() => {
    'nodes': (nodes.map((node) => node.toJson()).toList()
      ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'))),
    'edges': (edges.map((edge) => edge.toJson()).toList()
      ..sort(
        (a, b) => '${a['source']}|${a['target']}|${a['kind']}'.compareTo(
          '${b['source']}|${b['target']}|${b['kind']}',
        ),
      )),
    'completeness': completeness.toJson(),
  };

  String canonicalDigestInput() => canonicalJson(toJson());
}

class Cardinality {
  final String value;
  const Cardinality._(this.value);

  static const exactlyOne = Cardinality._('exactlyOne');
  static const zeroOrOne = Cardinality._('zeroOrOne');
  static const oneOrMore = Cardinality._('oneOrMore');
  static const many = Cardinality._('many');

  static Cardinality parse(String s) => switch (s) {
    'exactlyOne' => exactlyOne,
    'zeroOrOne' => zeroOrOne,
    'oneOrMore' => oneOrMore,
    'many' => many,
    'zeroOrMore' => many,
    _ => throw ArgumentError('Unknown cardinality: $s'),
  };
}
