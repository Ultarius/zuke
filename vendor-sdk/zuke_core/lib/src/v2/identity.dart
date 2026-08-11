/// Stable target/package identity used by V2 extraction and evidence.
final class TargetIdentity {
  final String id;
  final String language;
  final String framework;
  final List<PackageIdentity> packages;

  const TargetIdentity({
    required this.id,
    required this.language,
    required this.framework,
    this.packages = const [],
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'language': language,
        'framework': framework,
        'packages': packages.map((package) => package.toJson()).toList(),
      };
}

final class PackageIdentity {
  final String id;
  final String path;
  final List<String> roots;

  const PackageIdentity({
    required this.id,
    required this.path,
    this.roots = const [],
  });

  Map<String, Object?> toJson() => {'id': id, 'path': path, 'roots': roots};
}

final class SourceIdentity {
  final String target;
  final String sourcePackage;
  final String sourceAdapter;
  final String compatibilityId;

  const SourceIdentity({
    required this.target,
    required this.sourcePackage,
    required this.sourceAdapter,
    required this.compatibilityId,
  });

  String get key => '$target|$sourcePackage|$sourceAdapter';

  Map<String, Object?> toJson() => {
        'target': target,
        'sourcePackage': sourcePackage,
        'sourceAdapter': sourceAdapter,
        'sourceCompatibilityId': compatibilityId,
      };
}

final class ExecutionSourceIdentity {
  final String sourcePackage;
  final String sourceAdapter;
  final String sourceCompatibilityId;

  const ExecutionSourceIdentity({
    required this.sourcePackage,
    required this.sourceAdapter,
    required this.sourceCompatibilityId,
  });

  factory ExecutionSourceIdentity.fromEnvironment(
    Map<String, String> environment,
  ) {
    String required(String key) {
      final value = environment[key];
      if (value == null || value.isEmpty) {
        throw FormatException('Missing execution identity: $key');
      }
      return value;
    }

    return ExecutionSourceIdentity(
      sourcePackage: required('ZUKE_SOURCE_PACKAGE'),
      sourceAdapter: required('ZUKE_SOURCE_ADAPTER'),
      sourceCompatibilityId: required('ZUKE_SOURCE_COMPATIBILITY_ID'),
    );
  }

  Map<String, Object?> toJson() => {
        'sourcePackage': sourcePackage,
        'sourceAdapter': sourceAdapter,
        'sourceCompatibilityId': sourceCompatibilityId,
      };
}

class EvidenceSlot {
  final String requirementId;
  final String evidenceType;
  final String target;
  final String variant;
  final String sourcePackage;
  final String sourceAdapter;

  const EvidenceSlot({
    required this.requirementId,
    required this.evidenceType,
    required this.target,
    this.variant = 'default',
    required this.sourcePackage,
    required this.sourceAdapter,
  });

  String get exactKey =>
      '$requirementId|$evidenceType|$target|$variant|$sourcePackage|$sourceAdapter';

  Map<String, Object?> toJson() => {
        'requirementId': requirementId,
        'evidenceType': evidenceType,
        'target': target,
        'variant': variant,
        'sourcePackage': sourcePackage,
        'sourceAdapter': sourceAdapter,
      };
}
