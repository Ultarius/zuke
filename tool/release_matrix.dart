import 'dart:io';

import 'package:yaml/yaml.dart';

/// The single parser for the repository release matrix.
///
/// Documentation checks and publication tooling must consume the same
/// package inventory and release actions. Keeping this parser here prevents
/// the two entry points from silently accepting different matrices.
final class ReleaseMatrix {
  const ReleaseMatrix({
    required this.schemaVersion,
    required this.sdk,
    required this.operatingSystems,
    required this.compatibilityIds,
    required this.contracts,
    required this.packages,
    required this.publicationOrder,
    required this.retiredPackages,
  });

  const ReleaseMatrix.empty()
    : schemaVersion = 0,
      sdk = const {},
      operatingSystems = const [],
      compatibilityIds = const {},
      contracts = const {},
      packages = const {},
      publicationOrder = const [],
      retiredPackages = const {};

  final int schemaVersion;
  final Map<String, Object?> sdk;
  final List<String> operatingSystems;
  final Map<String, String> compatibilityIds;
  final Map<String, String> contracts;
  final Map<String, PackageRelease> packages;
  final List<String> publicationOrder;
  final Set<String> retiredPackages;

  Map<String, String> get versions => {
    for (final entry in packages.entries) entry.key: entry.value.version,
  };

  Map<String, String> get publicPackageVersions => {
    for (final entry in packages.entries)
      if (entry.value.releaseAction == 'publish' ||
          entry.value.releaseAction == 'reuse')
        entry.key: entry.value.version,
  };
}

final class PackageRelease {
  const PackageRelease({
    required this.name,
    required this.version,
    required this.previousVersion,
    required this.publish,
    required this.releaseAction,
    required this.tier,
    required this.supportStatement,
    required this.bumpReason,
  });

  final String name;
  final String version;
  final String previousVersion;
  final bool publish;
  final String releaseAction;
  final String tier;
  final String supportStatement;
  final String bumpReason;
}

ReleaseMatrix readReleaseMatrix(Directory root) {
  final file = File(
    '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}release-matrix.yaml',
  );
  if (!file.existsSync()) throw StateError('Missing docs/release-matrix.yaml');

  final decoded = loadYaml(file.readAsStringSync());
  if (decoded is! Map || decoded['schemaVersion'] != 2) {
    throw const FormatException('release matrix schemaVersion must be 2');
  }

  const allowedRootFields = {
    'schemaVersion',
    'sdk',
    'operatingSystems',
    'packages',
    'retiredPackages',
    'compatibilityIds',
    'contracts',
    'publicationOrder',
  };
  final unknownRootFields = decoded.keys
      .map((key) => key.toString())
      .where((key) => !allowedRootFields.contains(key))
      .toList();
  if (unknownRootFields.isNotEmpty) {
    throw FormatException(
      'release matrix has unknown fields: ${unknownRootFields.join(', ')}',
    );
  }

  final rawPackages = decoded['packages'];
  if (rawPackages is! Map) {
    throw const FormatException('release matrix packages must be a mapping');
  }

  final packages = <String, PackageRelease>{};
  for (final entry in rawPackages.entries) {
    final name = entry.key;
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException(
        'release matrix package names must be non-empty strings',
      );
    }
    final value = entry.value;
    if (value is! Map) {
      throw FormatException('$name release entry must be a mapping');
    }
    const allowedPackageFields = {
      'version',
      'previousVersion',
      'publish',
      'releaseAction',
      'tier',
      'supportStatement',
      'bumpReason',
    };
    final unknownPackageFields = value.keys
        .map((key) => key.toString())
        .where((key) => !allowedPackageFields.contains(key))
        .toList();
    if (unknownPackageFields.isNotEmpty) {
      throw FormatException(
        '$name has unknown release fields: ${unknownPackageFields.join(', ')}',
      );
    }

    String requiredString(String key) {
      final item = value[key];
      if (item is! String || item.trim().isEmpty) {
        throw FormatException('$name is missing non-empty $key');
      }
      return item;
    }

    final publish = value['publish'];
    if (publish is! bool) {
      throw FormatException('$name publish must be true or false');
    }
    final action = requiredString('releaseAction');
    if (!const {'publish', 'reuse', 'internal'}.contains(action)) {
      throw FormatException('$name has unsupported releaseAction $action');
    }
    if (publish != (action == 'publish' || action == 'reuse')) {
      throw FormatException('$name publish/releaseAction disagree');
    }

    final version = requiredString('version');
    final previousVersion = requiredString('previousVersion');
    final versionPattern = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');
    if (!versionPattern.hasMatch(version) ||
        !versionPattern.hasMatch(previousVersion)) {
      throw FormatException('$name has a malformed semantic version');
    }

    packages[name] = PackageRelease(
      name: name,
      version: version,
      previousVersion: previousVersion,
      publish: publish,
      releaseAction: action,
      tier: requiredString('tier'),
      supportStatement: requiredString('supportStatement'),
      bumpReason: requiredString('bumpReason'),
    );
  }

  final rawRetired = decoded['retiredPackages'];
  final retiredPackages = <String>{};
  if (rawRetired != null) {
    if (rawRetired is! Map) {
      throw const FormatException('retiredPackages must be a mapping');
    }
    for (final entry in rawRetired.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.value as String).trim().isEmpty) {
        throw const FormatException(
          'retiredPackages must map package names to non-empty reasons',
        );
      }
      retiredPackages.add(entry.key as String);
    }
  }

  final rawOrder = decoded['publicationOrder'];
  if (rawOrder is! List || rawOrder.any((item) => item is! String)) {
    throw const FormatException('publicationOrder must be a string list');
  }
  final order = rawOrder.cast<String>();
  final expected = packages.values
      .where((release) => release.releaseAction == 'publish')
      .map((release) => release.name)
      .toSet();
  if (order.toSet().length != order.length ||
      order.length != expected.length ||
      !expected.containsAll(order)) {
    throw const FormatException(
      'publicationOrder must contain each publish-action package exactly once',
    );
  }

  final rawCompatibilityIds = decoded['compatibilityIds'];
  if (rawCompatibilityIds is! Map) {
    throw const FormatException(
      'release matrix compatibilityIds must be a mapping',
    );
  }
  final compatibilityIds = <String, String>{};
  for (final entry in rawCompatibilityIds.entries) {
    if (entry.key is! String ||
        entry.value is! String ||
        (entry.value as String).trim().isEmpty) {
      throw const FormatException(
        'release matrix compatibilityIds must contain non-empty strings',
      );
    }
    compatibilityIds[entry.key as String] = entry.value as String;
  }

  final rawContracts = decoded['contracts'];
  if (rawContracts is! Map) {
    throw const FormatException('release matrix contracts must be a mapping');
  }
  final contracts = <String, String>{};
  for (final entry in rawContracts.entries) {
    if (entry.key is! String ||
        entry.value is! String ||
        (entry.value as String).trim().isEmpty) {
      throw const FormatException(
        'release matrix contracts must contain non-empty strings',
      );
    }
    contracts[entry.key as String] = entry.value as String;
  }

  final rawSdk = decoded['sdk'];
  if (rawSdk is! Map) {
    throw const FormatException('release matrix sdk must be a mapping');
  }
  final operatingSystems = decoded['operatingSystems'];
  if (operatingSystems is! List ||
      operatingSystems.any((value) => value is! String || value.isEmpty)) {
    throw const FormatException(
      'release matrix operatingSystems must be a non-empty string list',
    );
  }

  return ReleaseMatrix(
    schemaVersion: decoded['schemaVersion'] as int,
    sdk: Map<String, Object?>.from(rawSdk),
    operatingSystems: List<String>.from(operatingSystems),
    compatibilityIds: Map.unmodifiable(compatibilityIds),
    contracts: Map.unmodifiable(contracts),
    packages: Map.unmodifiable(packages),
    publicationOrder: List.unmodifiable(order),
    retiredPackages: Set.unmodifiable(retiredPackages),
  );
}
