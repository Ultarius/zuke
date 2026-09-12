// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: docs/release-matrix.yaml

/// Compatibility identity for the first-party Dart Frog topology adapter.
const releaseDartFrogCompatibilityId = 'dart-frog-gen-2-route-topology-v1';

/// Compatibility identity for resolved Dart source extraction.
const releaseDartSourceCompatibilityId = 'dart-source-package-v1';

/// Exact versions for the currently supported hosted public packages.
const releasePublicPackageVersions = <String, String>{
  'zuke_core': '0.4.0',
  'zuke_annotations': '0.4.0',
  'zuke_frontend': '0.2.2',
  'zuke': '0.4.0',
  'zuke_runner': '0.4.0',
  'zuke_runner_flutter': '0.4.0',
  'zuke_http_runtime': '0.1.1',
  'zuke_cli': '0.5.0',
  'zuke_dart_build_hook': '0.4.0',
};

/// Packages retained only as historical names and never published by current Zuke.
const releaseRetiredPackages = <String>{
  'adapter_sdk',
  'assurance_ir',
  'dart_extractor',
  'evidence_ledger',
  'proof_engine',
  'zuke_adapter_dart_frog',
  'zuke_flutter_runtime',
  'zuke_generator',
  'zuke_reporter',
};

/// Operating systems covered by the release certification lanes.
const releaseSupportedOperatingSystems = <String>['linux', 'windows'];

/// Exact Flutter host versions covered by hosted certification.
const releaseFlutterCertification = <String, Object?>{
  'minimum': '3.44.8',
  'current': '3.44.8',
  'channels': <String>['stable'],
};

/// Compatibility identities selected by the release matrix.
const releaseCompatibilityIds = <String, String>{
  'dart-frog': 'dart-frog-gen-2-route-topology-v1',
  'dart-source': 'dart-source-package-v1',
  'runner-dart': 'hosted-dart-runner-v1',
  'runner-flutter': 'hosted-flutter-runner-v1',
};
