import 'diagnostics.dart';
import 'identity.dart';

final class AdapterRequest {
  final String workspaceRoot;
  final String targetId;
  final String packageId;
  final String packageRoot;
  final List<String> configuredRoots;
  final Map<String, Object?> options;

  const AdapterRequest({
    required this.workspaceRoot,
    required this.targetId,
    required this.packageId,
    required this.packageRoot,
    this.configuredRoots = const [],
    this.options = const {},
  });
}

enum CompletenessStatus { complete, incomplete, indeterminate }

final class AdapterCompletenessV2 {
  final CompletenessStatus routeRegistration;
  final CompletenessStatus middlewareOrder;
  final CompletenessStatus dynamicRegistration;
  final CompletenessStatus externalVisibility;
  final CompletenessStatus failureFlow;
  final CompletenessStatus logFlow;

  const AdapterCompletenessV2({
    this.routeRegistration = CompletenessStatus.indeterminate,
    this.middlewareOrder = CompletenessStatus.indeterminate,
    this.dynamicRegistration = CompletenessStatus.indeterminate,
    this.externalVisibility = CompletenessStatus.indeterminate,
    this.failureFlow = CompletenessStatus.indeterminate,
    this.logFlow = CompletenessStatus.indeterminate,
  });

  Map<String, String> toJson() => {
        'routeRegistration': routeRegistration.name,
        'middlewareOrder': middlewareOrder.name,
        'dynamicRegistration': dynamicRegistration.name,
        'externalVisibility': externalVisibility.name,
        'failureFlow': failureFlow.name,
        'logFlow': logFlow.name,
      };
}

final class TopologyNode {
  final String id;
  final String kind;
  final String name;
  final String? path;
  final Map<String, Object?> attributes;

  const TopologyNode({
    required this.id,
    required this.kind,
    required this.name,
    this.path,
    this.attributes = const {},
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        if (path != null) 'path': path,
        if (attributes.isNotEmpty) 'attributes': attributes,
      };
}

final class AdapterOutputV2 {
  final String targetId;
  final String packageId;
  final String sourceAdapter;
  final String compatibilityId;
  final AdapterCompletenessV2 completeness;
  final List<TopologyNode> nodes;
  final List<DiagnosticV2> diagnostics;

  const AdapterOutputV2({
    required this.targetId,
    required this.packageId,
    required this.sourceAdapter,
    required this.compatibilityId,
    required this.completeness,
    required this.nodes,
    this.diagnostics = const [],
  });

  SourceIdentity get source => SourceIdentity(
        target: targetId,
        sourcePackage: packageId,
        sourceAdapter: sourceAdapter,
        compatibilityId: compatibilityId,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': 'zuke.adapter-output.v2',
        ...source.toJson(),
        'completeness': completeness.toJson(),
        'nodes': nodes.map((node) => node.toJson()).toList(),
        'diagnostics': diagnostics.map((diagnostic) => diagnostic.toJson()).toList(),
      };
}

abstract interface class FrameworkAdapter {
  String get id;
  String get compatibilityId;
  Future<AdapterOutputV2> extract(AdapterRequest request);
}
