# Changelog

## 0.5.0

- Coordinated with `zuke_cli` 0.6.
- `workspaceRoot` now accepts relative and native absolute paths, including folder names with `#` or `%`, and selects the workspace used for both target placement and index validation.
- An invalid `workspaceRoot` is now reported as `ZUKE-HOOK-CONFIG-001`, and a malformed `zuke.yaml` as a hook diagnostic, instead of crashing the hook.

## 0.4.0

- Propagated the active workspace extraction target to the analyzer-backed
  build hook and rejected ambiguous or invalid target membership.

## 0.3.0

- Consume the published CLI tooling boundary for coordinated current validation.

## 0.2.0

- Updated the `zuke_core` dependency for the analyzer-compatible SDK release.

## 0.1.0

- Initial public preview release.
