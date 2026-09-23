# Contributing to Zuke

Thanks for contributing. This document covers local setup, the quality gates CI
runs, and the expectations for pull requests.

## Development setup

- Install **Flutter 3.44.8** (stable). Dart ships with Flutter, so
  `flutter doctor` and `dart --version` must both work.
- From the repository root, bootstrap the pub workspace:

  ```bash
  dart run --suppress-analytics melos bootstrap
  ```

  `melos` is a workspace `dev_dependency`, so no global install is needed.

## Quality gates

Run the umbrella gate before opening a PR — CI runs the same checks:

```bash
dart run --suppress-analytics melos run zuke:check
```

That chains format check, docs check, workspace analysis, the Dart and Flutter
test suites, and the Zuke assurance gates for all three examples. Individual
gates when you want a faster loop:

```bash
dart run --suppress-analytics melos run format:check
dart run --suppress-analytics melos run docs:check
dart run --suppress-analytics melos run analyze:dart
dart run --suppress-analytics melos run analyze:flutter
```

- Analysis runs with `--fatal-infos`; warnings and infos fail the build.
- The docs check validates README links, release-matrix/pubspec version
  parity, support-tier statements, and current product language across
  `docs/` and `.github/`.
- If you change specifications, profiles, or generated contracts, refresh the
  locks in the same change: `dart run zuke_cli:zuke lock --refresh --all-profiles`
  and commit the updated `assurance/locks/` files.

## Commit messages

Use conventional commit prefixes:

| Prefix | Use for |
| --- | --- |
| `fix:` | Bug fixes |
| `feat:` | New functionality |
| `ci:` | Workflow and CI changes |
| `docs:` | Documentation only |
| `test:` | Test-only changes |
| `chore:` | Mechanical maintenance (formatting, dependency bumps, cleanup) |

Substantive work should not be labeled a blanket `chore:` — pick the prefix
that describes the change.

## Pull requests

- All CI checks must be green: the PR parity suite, dependency firewall,
  dependency review, secret scan, and the three example assurance workflows.
- Keep the diff focused; separate unrelated refactors into their own PR.
- If specifications or generated contracts changed, include the refreshed
  locks so `zuke lock --profile <name> --check` passes on a clean checkout.
- Update `docs/` when behavior, configuration, or release surface changes.

## Code style

- The root `analysis_options.yaml` enables `strict-casts`,
  `strict-inference`, and `strict-raw-types` on top of
  `package:lints/recommended`. Fix the code, do not weaken the analysis.
- Do not add `// ignore:` / `// ignore_for_file:` suppressions to make
  analysis pass. If a diagnostic is genuinely wrong, fix the underlying code or
  remove the lint in a reviewed change.
- Braces are required in flow-control structures (enforced by the linter).
- Prefer `package:` imports (or local `test/support/` re-export shims) over
  cross-package relative imports in tests.

### Output channels

- User-facing result output (CLI `run()` prints) → stdout.
- Diagnostics, progress, tooling errors → stderr.
- Prefer `stderr.writeln` for failures in CLI code; avoid bare `print` for
  errors.
- Scripts under `tool/` and `vendor-sdk/*.dart` (workspace tasks) may use
  stderr for failures and stdout for machine-readable payloads only.

## Running tests

```bash
# All Dart packages in the workspace
dart run --suppress-analytics melos run test:dart

# Flutter example apps
dart run --suppress-analytics melos run test:flutter

# Everything, including the Zuke gates
dart run --suppress-analytics melos run test:all

# A single package
cd vendor-sdk/zuke_cli
dart --suppress-analytics test
dart --suppress-analytics test test/lock_parity_test.dart

# Coverage gate
dart run --suppress-analytics melos run coverage:check
```

The process-integration tests (`flutter_toolchain_integration_test`,
`process_supervisor_integration_test`) only run when
`ZUKE_RUN_PROCESS_INTEGRATION=true` is set; assurance workflows set it, and the
tests skip otherwise.
