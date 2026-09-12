# Changelog

## 0.4.0

- Removed placement `target` overrides from `ImplementsRequirement`,
  `PresentsRequirement`, `ZukeBinding`, and `VerifiesRequirement` (as well as
  the already target-free `ProvidesControl` API).
- Kept provider kind, layer, variant, and slot metadata unchanged. Binding
  placement now comes from workspace package membership and active extraction.
- Added the stable binding-slot contract; slots such as `create` and `join`
  identify independent implementation occurrences and are validated by the
  CLI.

## 0.3.0

- Coordinated the annotation package with the analyzer-free current core and
  deterministic source-identity contracts.

## 0.2.0

- Updated the `zuke_core` dependency for the analyzer-compatible SDK release.

## 0.1.0

- Initial public preview release.
