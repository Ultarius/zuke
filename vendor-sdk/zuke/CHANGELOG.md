# Changelog

## 0.4.0

- Coordinated the current facade with target-aware provider extraction and the
  verification-backed versus structural proof ownership boundary.
- Added managed `zukeTest` and `zukeUnit` registration helpers, including stable
  case identities and evidence emission for ordinary Dart tests; `package:test`
  is now declared as their runtime dependency.
- Consumers using these helpers should keep `zuke` in `dev_dependencies`;
  application code that only references generated contracts should depend on
  `zuke_annotations` instead.
- Extended suite and scenario result identities with optional case IDs so
  distinct examples cannot collide across retained evidence.

## 0.3.1

- Include profile, runner, target, and case identity in emitted suite result
  and scenario result execution IDs so retained evidence from sequential
  profile runs cannot collide during validation.

## 0.3.0

- Emit deterministic scenario and suite results with complete source
  identity and reject legacy V1 artifacts.

## 0.2.0

- Raised the supported `zuke_core` and `zuke_annotations` dependency floors
  for the analyzer-compatible SDK release.

## 0.1.0

- Added the canonical pure-Dart Zuke SDK.
- Made `zuke` the implementation owner of deterministic execution, runtime
  events, feature flags, and HTTP scenario-driver APIs.
- Re-exported the supported annotation and specification parsing APIs.
