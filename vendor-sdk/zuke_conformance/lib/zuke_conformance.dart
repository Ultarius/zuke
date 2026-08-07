/// Supported adapter extension API for versioned Zuke JSON schemas.
library;

/// Package URIs for schemas used by the public conformance corpus.
abstract final class ZukeSchemaPaths {
  /// Behavioral assurance manifest schema, version 1.
  static const behavioralAssuranceManifestV1 =
      'package:zuke_conformance/schemas/'
      'behavioral-assurance-manifest.v1.schema.json';

  /// Exported behavioral assurance release schema, version 2.
  static const behavioralAssuranceReleaseV2 =
      'package:zuke_conformance/schemas/'
      'behavioral-assurance-release.v2.schema.json';

  /// Ed25519 trust-bundle schema, version 2.
  static const ed25519TrustV2 =
      'package:zuke_conformance/schemas/ed25519-trust.v2.schema.json';

  /// Zuke lockfile schema, version 1.
  static const lockV1 =
      'package:zuke_conformance/schemas/zuke.lock.v1.schema.json';

  /// All versioned schema package URIs.
  static const all = <String>[
    behavioralAssuranceManifestV1,
    behavioralAssuranceReleaseV2,
    ed25519TrustV2,
    lockV1,
  ];
}
