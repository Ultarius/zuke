import 'dart:io';

import 'package:adapter_sdk/adapter_sdk.dart';
import 'package:assurance_ir/assurance_ir.dart';

/// Conservative source package extractor used by adapter coordinators.
///
/// Framework topology is deliberately not inferred here. This package only
/// owns Dart source/package identity and leaves framework-specific resolution
/// to first-party adapters such as `zuke_adapter_dart_frog`.
final class DartPackageExtractor {
  const DartPackageExtractor();

  Future<AdapterOutputV2> extract(AdapterRequest request) async {
    final root = Directory(request.packageRoot);
    if (!root.existsSync()) {
      return AdapterOutputV2(
        targetId: request.targetId,
        packageId: request.packageId,
        sourceAdapter: 'dart-source',
        compatibilityId: 'dart-source-package-v1',
        completeness: const AdapterCompletenessV2(
          routeRegistration: CompletenessStatus.indeterminate,
          dynamicRegistration: CompletenessStatus.incomplete,
        ),
        nodes: const [],
        diagnostics: [
          DiagnosticV2(
            code: 'ZK-DART-SOURCE-001',
            stage: 'extract',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.environment,
            message: 'Configured Dart package root does not exist.',
            remediation: 'Correct the target package path.',
          ),
        ],
      );
    }
    final files = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final nodes = files
        .map(
          (file) => TopologyNode(
            id: '${request.targetId}/${request.packageId}/source/${file.path}',
            kind: 'dart-source',
            name: file.uri.pathSegments.last,
            path: file.path,
          ),
        )
        .toList();
    return AdapterOutputV2(
      targetId: request.targetId,
      packageId: request.packageId,
      sourceAdapter: 'dart-source',
      compatibilityId: 'dart-source-package-v1',
      completeness: const AdapterCompletenessV2(
        routeRegistration: CompletenessStatus.indeterminate,
        dynamicRegistration: CompletenessStatus.complete,
      ),
      nodes: nodes,
    );
  }
}
