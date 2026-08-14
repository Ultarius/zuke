# Changelog

## 0.4.0

- Added normalized binding identities with explicit target, role, variant, and
  slot fields, implementation-coverage results, and deterministic proof
  ownership data.
- Kept `dart-source-package-v1` unchanged because the serialized adapter
  contract is unchanged.

## 0.3.0

- Consolidated analyzer-free identities, diagnostics, evidence, digest, and
  adapter contracts into the public core package.
- Removed analyzer and extractor dependencies from the runtime package.
- Coordinated package-family analyzer compatibility so Flutter SDKs can select
  analyzer 8 while Dart-only consumers select analyzer 14.

## 0.2.0

- Added analyzer 8/14 compatibility and bumped extraction/cache compatibility
  identifiers for the updated extractor contract.
- Declared the supported analyzer range so Dart and Flutter SDKs can select
  their compatible analyzer lane.

## 0.1.0

- Initial shared-engine release for the Zuke package family.
