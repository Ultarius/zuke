import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'generated/release_contract.dart';
import 'ir.dart';

/// A stable failure returned when an evidence record cannot be bound to one
/// configured source extraction.
final class SourceResolveFailure implements Exception {
  final String code;
  final String message;
  final Map<String, Object?> context;

  const SourceResolveFailure({
    required this.code,
    required this.message,
    this.context = const {},
  });

  @override
  String toString() => '$code: $message';
}

final class SourceOutputResolution {
  final SourceIdentity identity;
  final IrAdapterOutput output;

  const SourceOutputResolution({required this.identity, required this.output});
}

/// Indexes extraction outputs once and resolves source identity exactly.
///
/// This deliberately lives in the CLI: it knows how a configured workspace
/// package path maps to an analyzer output. The identity value objects remain
/// framework contracts in zuke_core.
final class SourceOutputCatalog {
  final Map<String, List<SourceOutputResolution>> _byIdentity;
  final Set<String> _knownPackages;
  final Set<String> _missingPackages;
  final Set<String> _outOfRootPackages;

  SourceOutputCatalog._(
    this._byIdentity,
    this._knownPackages,
    this._missingPackages,
    this._outOfRootPackages,
  );

  factory SourceOutputCatalog.build(
    WorkspaceDiscoveryResult workspace,
    Iterable<IrAdapterOutput> outputs,
  ) {
    final indexed = <String, List<SourceOutputResolution>>{};
    final knownPackages = <String>{};
    final missingPackages = <String>{};
    final outOfRootPackages = <String>{};
    final root = workspace.config.root;
    if (root == null || root.isEmpty) {
      return SourceOutputCatalog._(
        indexed,
        knownPackages,
        missingPackages,
        outOfRootPackages,
      );
    }

    for (final targetEntry in workspace.config.workspaceTargets.entries) {
      final targetId = targetEntry.key;
      for (final package in targetEntry.value.packages) {
        final packageId = package.id;
        final packagePath = package.path;
        final packageKey = _packageKey(targetId, packageId);
        knownPackages.add(packageKey);
        final packageRoot = _canonicalPath(path.join(root, packagePath));
        if (!Directory(packageRoot).existsSync()) {
          missingPackages.add(packageKey);
          continue;
        }
        for (final output in outputs) {
          final outputRoot = output.packageRoot;
          if (outputRoot == null || outputRoot.isEmpty) continue;
          final canonicalOutputRoot = _canonicalPath(outputRoot);
          if (!_isWithin(canonicalOutputRoot, packageRoot)) {
            // An output is attributable to an escape only when it explicitly
            // claims this configured package. A missing or different package
            // identity cannot safely be assigned to this root and therefore
            // remains a normal no-match failure.
            if (output.packageName == packageId) {
              outOfRootPackages.add(packageKey);
            }
            continue;
          }
          if (output.packageName != null && output.packageName != packageId) {
            continue;
          }

          final sourceAdapter = _sourceAdapterFor(output);
          final identity = SourceIdentity(
            target: targetId,
            sourcePackage: packageId,
            sourceAdapter: sourceAdapter,
            compatibilityId: output.adapter.compatibilityId,
          );
          final resolution = SourceOutputResolution(
            identity: identity,
            output: output,
          );
          indexed
              .putIfAbsent(_key(identity), () => <SourceOutputResolution>[])
              .add(resolution);
        }
      }
    }
    return SourceOutputCatalog._(
      indexed,
      knownPackages,
      missingPackages,
      outOfRootPackages,
    );
  }

  SourceOutputResolution resolve({
    required String target,
    required String sourcePackage,
    required String sourceAdapter,
    required String sourceCompatibilityId,
  }) {
    final packageKey = _packageKey(target, sourcePackage);
    if (!_knownPackages.contains(packageKey)) {
      throw SourceResolveFailure(
        code: 'ZK-SOURCE-UNKNOWN-PACKAGE',
        message: 'The source identity names an unknown configured package.',
        context: {'target': target, 'sourcePackage': sourcePackage},
      );
    }
    if (_missingPackages.contains(packageKey)) {
      throw SourceResolveFailure(
        code: 'ZK-SOURCE-MISSING-PACKAGE',
        message: 'The configured source package root does not exist.',
        context: {'target': target, 'sourcePackage': sourcePackage},
      );
    }
    if (_outOfRootPackages.contains(packageKey)) {
      throw SourceResolveFailure(
        code: 'ZK-SOURCE-OUT-OF-ROOT',
        message: 'An extracted source output escaped its package root.',
        context: {'target': target, 'sourcePackage': sourcePackage},
      );
    }
    final identity = SourceIdentity(
      target: target,
      sourcePackage: sourcePackage,
      sourceAdapter: sourceAdapter,
      compatibilityId: sourceCompatibilityId,
    );
    final candidates = _byIdentity[_key(identity)] ?? const [];
    if (candidates.length == 1) return candidates.single;
    if (candidates.length > 1) {
      throw SourceResolveFailure(
        code: 'ZK-SOURCE-AMBIGUOUS',
        message: 'Multiple source outputs match the exact source identity.',
        context: identity.toJson(),
      );
    }

    final sameAdapter = _byIdentity.entries
        .where(
          (entry) =>
              entry.key.startsWith('$target|$sourcePackage|$sourceAdapter|'),
        )
        .expand((entry) => entry.value)
        .toList(growable: false);
    if (sameAdapter.isNotEmpty) {
      throw SourceResolveFailure(
        code: 'ZK-SOURCE-COMPATIBILITY-MISMATCH',
        message: 'No source output has the requested compatibility identity.',
        context: {
          ...identity.toJson(),
          'availableCompatibilityIds':
              sameAdapter
                  .map((candidate) => candidate.identity.compatibilityId)
                  .toSet()
                  .toList()
                ..sort(),
        },
      );
    }

    final sameTargetPackage = _byIdentity.entries
        .where((entry) => entry.key.startsWith('$target|$sourcePackage|'))
        .expand((entry) => entry.value)
        .toList(growable: false);
    if (sameTargetPackage.isEmpty) {
      throw SourceResolveFailure(
        code: 'ZK-SOURCE-NO-MATCH',
        message: 'No source output matches the configured source identity.',
        context: identity.toJson(),
      );
    }
    throw SourceResolveFailure(
      code: 'ZK-SOURCE-NO-MATCH',
      message: 'No source output matches the configured source adapter.',
      context: identity.toJson(),
    );
  }

  static String _sourceAdapterFor(IrAdapterOutput output) {
    if (output.adapter.compatibilityId == releaseDartFrogCompatibilityId) {
      return 'dart-frog';
    }
    if (output.adapter.compatibilityId == releaseDartSourceCompatibilityId) {
      return 'dart-source';
    }
    return output.adapter.id;
  }

  static String _key(SourceIdentity identity) =>
      '${identity.target}|${identity.sourcePackage}|'
      '${identity.sourceAdapter}|${identity.compatibilityId}';

  static String _packageKey(String target, String sourcePackage) =>
      '$target|$sourcePackage';

  static String _canonicalPath(String value) {
    final normalized = path
        .normalize(path.absolute(value))
        .replaceAll('\\', '/');
    final trimmed = normalized.replaceFirst(RegExp(r'/$'), '');
    return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
  }

  static bool _isWithin(String candidate, String root) =>
      candidate == root || candidate.startsWith('$root/');
}
