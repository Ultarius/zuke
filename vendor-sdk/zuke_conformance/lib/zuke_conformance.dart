/// Supported adapter extension API for current Zuke JSON schemas.
library;

/// Package URIs for schemas used by the public conformance corpus.
abstract final class ZukeSchemaPaths {
  /// Behavioral assurance manifest schema.
  static const behavioralAssuranceManifest =
      'package:zuke_conformance/schemas/'
      'behavioral-assurance-manifest.schema.json';

  /// Exported behavioral assurance release schema.
  static const behavioralAssuranceRelease =
      'package:zuke_conformance/schemas/'
      'behavioral-assurance-release.schema.json';

  /// Ed25519 trust-bundle schema.
  static const ed25519Trust =
      'package:zuke_conformance/schemas/ed25519-trust.schema.json';

  /// Zuke profile lock schema.
  static const lock = 'package:zuke_conformance/schemas/zuke.lock.schema.json';

  /// All current schema package URIs.
  static const all = <String>[
    behavioralAssuranceManifest,
    behavioralAssuranceRelease,
    ed25519Trust,
    lock,
  ];
}
