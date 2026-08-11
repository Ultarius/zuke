/// Stable identities prevent evidence from being matched to the first
/// adapter output that happens to mention the same requirement.
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

  const PackageIdentity({required this.id, required this.path, this.roots = const []});

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
