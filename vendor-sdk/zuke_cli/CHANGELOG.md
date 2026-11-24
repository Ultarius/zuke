# Changelog

## 0.6.0

- Breaking: specification, lock, and evidence digests are structural, so prose edits no longer move them. Run `zuke lock --refresh --all-profiles` after upgrading.
- Breaking: analyzer index contract 3 records registration variants and runner-audited test files. Run `zuke generate`.
- Binding coverage now reads the same test directories as `zuke test` and matches the variant a harness emits.
- `zuke analyze` works on a first run with an empty plugin cache.
- Generated contracts are excluded from source provenance when `contractOutput` uses its default.
- `resolvePlacement` accepts an `explicitWorkspaceRoot` that takes precedence over the nearest `zuke.yaml`, and reports an unusable configuration as a typed `PlacementFailure`.
- `zuke coverage` matches absolute LCOV paths under relative workspace roots, normalizes source paths before scoping, and compares Windows drive and UNC paths case-insensitively across coverage policies, Git diffs, and baselines.

## 0.5.0

- Materialize resolved requirement and control annotations in the governed
  graph for native Dart Frog and annotation-only packages.
- Keep annotation-only extraction dimensions explicitly non-topology instead
  of claiming route or middleware completeness.
- Made extraction target-aware through typed workspace package membership and
  rejected ambiguous standalone extraction instead of defaulting to a target.
- Routed verification-backed controls exclusively through evidence/provider
  validation and added proof-owner conflict diagnostics.
- Added independent implementation-coverage obligations for every binding
  variant/slot, with topology reachability or explicit managed evidence chosen
  by package authority mode.
- Linked resolved Dart Frog `RequestContext.read<T>()` calls to annotated
  implementations in the extracted topology.
- Kept `dart-source-package-v1` stable; the extraction cache revision is
  internal and independent of the public adapter contract.
- Added typed workspace and consumer-policy validation plus alignment, artifact,
  registration, OpenAPI, and gate diagnostics for CI assurance workflows.
- Added attestation, trust, and owner-handoff commands for signed release
  evidence.
- Made `zuke-cli` the generation authority for typed contracts and explicit
  contract barrels; consumer workflows can keep generated source committed and
  disable build-runner generation.
- Added portable coverage baselines that preserve line comparisons across
  amended or rebased Git history.
- Added generated VS Code presets and lock-refresh support for the current CLI
  workflow.

## 0.4.1

- Retain successfully published evidence from other profiles when sequential
  profile runs share an evidence directory.
- Use the canonical source snapshot digest for projected Dart Frog topology
  outputs so strict evidence serialization accepts native topology evidence.

## 0.4.0

- Consolidated analyzer-backed tooling, typed current contracts, profile locks,
  structured diagnostics, and first-party Dart Frog topology extraction.

## 0.3.0

- Updated extraction cache compatibility for the analyzer-compatible core
  release.
- Raised the `zuke_core` and `zuke` dependency floors.

## 0.2.0

- Generate pure-Dart step support with `package:zuke/zuke.dart`.
- Depend directly on the primary `zuke` execution SDK.
- Continue generating application contracts against the narrow
  `zuke_annotations` package.

## 0.1.0

- Initial public preview release.
