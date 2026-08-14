# Changelog

## 0.4.0

- Coordinated runner identity and result emission with the target-aware
  provider and proof-routing release.

## 0.3.1

- Include the managed test case identity when emitting suite and scenario
  results so distinct cases and sequential profile runs cannot collide during
  validation.

## 0.3.0

- Coordinated the compatibility facade with the current result identity contract.
- Declared the annotation and core contracts used by the managed test wrapper as
  direct hosted dependencies.

## 0.2.0

- Raised the `zuke` dependency floor for the analyzer-compatible SDK release.

## 0.1.1

- Moved the runner implementation into the primary `zuke` package.
- Preserved `zuke_runner.dart`, `runtime.dart`, and `http.dart` as forwarding
  compatibility entry points.
- Deprecated `zuke_runner` as the package new projects add directly.

## 0.1.0

- Initial public preview release.
