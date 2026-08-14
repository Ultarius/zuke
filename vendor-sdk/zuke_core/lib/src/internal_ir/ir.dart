/// Canonical stack-neutral assurance graph model.
library;

import '../canonical_json.dart';
import '../binding_identity.dart';

/// A workspace-relative source span in a Dart or specification file.
class SourceSpan {
  /// Workspace-relative file path.
  final String path;

  /// One-based start line.
  final int startLine;

  /// One-based start column.
  final int startColumn;

  /// One-based end line.
  final int endLine;

  /// One-based end column.
  final int endColumn;

  /// Creates a source span.
  const SourceSpan({
    required this.path,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  });

  /// Decodes and validates a source span.
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

  /// Encodes this span as a stable JSON object.
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

/// Node roles in the assurance graph.
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

/// Relationship kinds in the assurance graph.
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

/// Proof semantics used to evaluate a control.
enum CoverageSemantics {
  ingressDominance,
  failureToPublicEgress,
  sensitiveDataToLogSink,
  externalAttestation,
  verificationBacked,
}

/// Visibility state for a graph dimension.
enum CompletenessValue { complete, indeterminate, notVisible, notApplicable }

/// Completeness values for runtime graph dimensions.
class GraphCompleteness {
  /// Route-registration completeness.
  final CompletenessValue routeRegistration;

  /// Middleware-order completeness.
  final CompletenessValue middlewareOrder;

  /// Failure-flow completeness.
  final CompletenessValue failureFlow;

  /// Logging-flow completeness.
  final CompletenessValue logFlow;

  /// Dynamic-registration completeness.
  final CompletenessValue dynamicRegistration;

  /// External-visibility completeness.
  final CompletenessValue externalVisibility;

  /// Creates graph completeness metadata.
  const GraphCompleteness({
    this.routeRegistration = CompletenessValue.notApplicable,
    this.middlewareOrder = CompletenessValue.notApplicable,
    this.failureFlow = CompletenessValue.notApplicable,
    this.logFlow = CompletenessValue.notApplicable,
    this.dynamicRegistration = CompletenessValue.notApplicable,
    this.externalVisibility = CompletenessValue.notApplicable,
  });

  /// Returns the stable wire value for [value].
  String value(CompletenessValue value) => switch (value) {
    CompletenessValue.complete => 'complete',
    CompletenessValue.indeterminate => 'indeterminate',
    CompletenessValue.notVisible => 'notVisible',
    CompletenessValue.notApplicable => 'notApplicable',
  };

  /// Encodes completeness metadata.
  Map<String, String> toJson() => {
    'routeRegistration': value(routeRegistration),
    'middlewareOrder': value(middlewareOrder),
    'failureFlow': value(failureFlow),
    'logFlow': value(logFlow),
    'dynamicRegistration': value(dynamicRegistration),
    'externalVisibility': value(externalVisibility),
  };
}

/// A node in the canonical assurance graph.
class IrNode {
  /// Stable node identifier.
  final String id;

  /// Semantic node kind.
  final NodeKind kind;

  /// Optional execution target.
  final String? target;

  /// Optional semantic role.
  final String? role;

  /// Optional variant.
  final String? variant;

  /// Optional binding slot.
  final String? slot;

  /// Additional node properties.
  final Map<String, Object?> properties;

  /// Source location for the node.
  final SourceSpan? source;

  /// Creates a graph node.
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

  /// Decodes a graph node.
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

  /// Encodes this graph node.
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

/// A directed relationship between two graph nodes.
class IrEdge {
  /// Source node identifier.
  final String sourceId;

  /// Target node identifier.
  final String targetId;

  /// Semantic edge kind.
  final EdgeKind kind;

  /// Additional edge properties.
  final Map<String, Object?> properties;

  /// Source location for the edge.
  final SourceSpan? source;

  /// Creates a graph edge.
  const IrEdge({
    required this.sourceId,
    required this.targetId,
    required this.kind,
    this.properties = const {},
    this.source,
  });

  /// Decodes a graph edge.
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

  /// Encodes this graph edge.
  Map<String, Object?> toJson() => {
    'source': sourceId,
    'target': targetId,
    'kind': kind.name,
    if (properties.isNotEmpty) 'properties': properties,
    if (source != null) 'location': source!.toJson(),
  };
}

/// Canonical assurance graph with deterministic validation and encoding.
class IrGraph {
  /// Graph nodes.
  final List<IrNode> nodes;

  /// Graph edges.
  final List<IrEdge> edges;

  /// Graph completeness metadata.
  final GraphCompleteness completeness;

  /// Creates an assurance graph.
  const IrGraph({
    this.nodes = const [],
    this.edges = const [],
    this.completeness = const GraphCompleteness(),
  });

  /// Decodes and validates an assurance graph.
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

  /// Stable identifiers of all graph nodes.
  Set<String> get nodeIds => nodes.map((node) => node.id).toSet();

  /// Returns validation diagnostics for this graph.
  List<String> validate() {
    final diagnostics = <String>[];
    final seen = <String>{};
    final identityKeys = <String>{};
    for (final node in nodes) {
      if (node.id.trim().isEmpty) diagnostics.add('IR node id is empty');
      if (!seen.add(node.id)) diagnostics.add('Duplicate IR node: ${node.id}');
      if (node.kind == NodeKind.provider ||
          node.kind == NodeKind.implementation) {
        if (node.target == null ||
            node.role == null ||
            node.variant == null ||
            node.slot == null) {
          diagnostics.add(
            'Missing binding identity for ${node.kind.name} node: ${node.id}',
          );
          continue;
        }
        if (!isValidBindingSlot(node.slot!)) {
          diagnostics.add(
            'ZK-BINDING-SLOT-INVALID: invalid binding slot "${node.slot}" '
            'for ${node.id}',
          );
        }
      }
      if (node.kind == NodeKind.provider) {
        final control = node.properties['controlId'];
        if (control is String) {
          if (node.target != null &&
              node.role != null &&
              node.variant != null &&
              node.slot != null) {
            final key = BindingIdentity(
              subjectKind: 'control',
              subjectId: control,
              target: node.target!,
              role: node.role!,
              variant: node.variant!,
              slot: node.slot!,
            ).key;
            if (!identityKeys.add(key)) {
              diagnostics.add('ZK-BINDING-IDENTITY-DUPLICATE: $key');
            }
          }
        }
      }
      if (node.kind == NodeKind.implementation) {
        final requirements = node.properties['requirementIds'];
        if (requirements is List) {
          for (final requirement in requirements.whereType<String>()) {
            if (node.target != null &&
                node.role != null &&
                node.variant != null &&
                node.slot != null) {
              final key = BindingIdentity(
                subjectKind: 'requirement',
                subjectId: requirement,
                target: node.target!,
                role: node.role!,
                variant: node.variant!,
                slot: node.slot!,
              ).key;
              if (!identityKeys.add(key)) {
                diagnostics.add('ZK-BINDING-IDENTITY-DUPLICATE: $key');
              }
            }
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

  /// Finds cycles in runtime flow edges.
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
      for (final target in adjacency[node] ?? const <String>[]) {
        visit(target);
      }
      path.removeLast();
      visiting.remove(node);
    }

    for (final node in adjacency.keys.toList()..sort()) {
      visit(node);
    }
    return cycles;
  }

  /// Returns edge descriptions that reference missing nodes.
  List<String> danglingEdges() => edges
      .where(
        (edge) =>
            !nodeIds.contains(edge.sourceId) ||
            !nodeIds.contains(edge.targetId),
      )
      .map((edge) => '${edge.sourceId}->${edge.targetId}')
      .toList(growable: false);

  /// Encodes this graph in deterministic JSON-compatible form.
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

  /// Returns canonical JSON suitable for hashing.
  String canonicalDigestInput() => canonicalJson(toJson());
}

/// A stable provider cardinality value.
class Cardinality {
  /// Serialized cardinality value.
  final String value;
  const Cardinality._(this.value);

  /// Exactly one provider is required.
  static const exactlyOne = Cardinality._('exactlyOne');

  /// Zero or one provider is allowed.
  static const zeroOrOne = Cardinality._('zeroOrOne');

  /// At least one provider is required.
  static const oneOrMore = Cardinality._('oneOrMore');

  /// Multiple providers are allowed.
  static const many = Cardinality._('many');

  /// Parses a supported cardinality spelling.
  static Cardinality parse(String s) => switch (s) {
    'exactlyOne' => exactlyOne,
    'zeroOrOne' => zeroOrOne,
    'oneOrMore' => oneOrMore,
    'many' => many,
    'zeroOrMore' => many,
    _ => throw ArgumentError('Unknown cardinality: $s'),
  };
}
