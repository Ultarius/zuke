---
name: zuke-pr-ci-fix
description: Diagnose and repair failing GitHub Actions checks for a Zuke pull request. Use when the user supplies a PR URL or number, asks to inspect a PR's failed CI, or reports cross-platform failures involving Zuke assurance, generated files, Flutter launchers, profile-specific locks, or signed assurance history.
---

# Zuke pull-request CI repair

Use this skill to turn a failing Zuke pull request into a verified, reviewable patch. Treat the GitHub run as evidence: identify the exact failing command and shared root cause first, then make the smallest repository change that fixes the contract without weakening assurance or changing signed history.

## Workflow

### 1. Locate the PR and establish the exact revision

- Accept a PR URL, `owner/repository#number`, a number plus repository, or infer the current repository only when it is unambiguous.
- Read the PR metadata before editing: title, state, base branch/SHA, head branch/SHA, mergeability, changed files, and changed workflow files.
- Use the connected GitHub app for PR metadata, changed-file patches, workflow-run jobs, and job logs. If the `gh` CLI is available, it can supplement this with `gh pr checks`, `gh run view`, and `gh run view --log`; do not assume `gh` exists.
- Confirm that local source is the PR head or clearly report when it is not. Never diagnose a local checkout as the PR without comparing its revision.

### 2. Read all failed matrix jobs

- Fetch the jobs for the relevant workflow run and list every failed OS/job/step. A job-name change or a renamed matrix entry only changes presentation; it does not prove the underlying command is fixed.
- Fetch logs for every failed job, not only the first URL. Compare the first failing command and the terminal diagnostic across Ubuntu, macOS, and Windows.
- Treat aggregate commands such as `melos run coverage:check` as wrappers, not root causes. Inspect the nested command and package summaries (`[package] failed`, `FAIL`, `Expected`, `Actual`, `ScriptException`) until the first failing test/assertion is found.
- If the log is large or truncated, fetch each job log separately and extract failure markers plus surrounding lines. Download job artifacts when the failure depends on generated reports, coverage summaries, or lock files.
- Classify the failure:
  - the same command and message on every OS means a shared workflow, generated artifact, profile, dependency, or assurance-state problem;
  - different messages per OS means a genuine platform issue and requires separate reproduction;
  - failures after an earlier failed step are symptoms until the earliest failure is fixed.
- Capture expected and actual hashes, paths, profile names, exit codes, and whether a file was generated or merely checked. Do not rely on a generic "exit code 1" summary.
- For test assertions, record the source file and line number. Compare the assertion's expected contract with the active configuration, generated lock, schema, or fixture before editing either side.
- Treat a package result such as `[vendor-sdk/zuke_cli] failed (300000ms)` as a distinct diagnostic. Compare the duration with the package runner timeout and inspect the worker-budget line before blaming a test assertion. In this repository, `ZUKE_TEST_WORKERS` controls the total Dart test budget; a four-package coverage pass with budget four runs one isolate per package and can hit the five-minute package timeout on Linux or Windows while the tests themselves have passed.

### 3. Apply Zuke-specific diagnosis

For assurance jobs, inspect the workspace's `zuke.yaml`, lock file, generated manifests, profile tag expressions, runner definitions, and the workflow that invokes the CLI.

Zuke assurance profiles are not interchangeable. `pullRequest`, `merge`, and `release` can select different scenarios and therefore produce different validation and lock digests. A single committed `zuke.lock.json` cannot be assumed to satisfy all profiles.

If CI runs `zuke check --profile <profile>` and reports a stale lock:

1. Confirm that `generate` is clean.
2. Run the selected profile's `test` so evidence is current.
3. Run `validate --profile <profile>` and require an eligible report.
4. Run `lock --profile <profile>` before the final `check`.
5. Decide deliberately whether the generated lock is a committed artifact for that workflow. If the repository intentionally keeps a merge lock while PR/release jobs use other profiles, prepare the profile lock inside that job and do not replace the committed merge lock accidentally.

Do not "fix" an assurance failure by removing controls, broadening profile tags, bypassing `lock --check`, accepting stale generated files, or disabling the build hook. Do not edit, resign, or fabricate signed JSON. If a signed record is invalid, determine whether the correct fix is a trusted release workflow or a non-signed local demonstration.

Other recurring Zuke diagnoses:

- `STALE` or `ZUKE-INDEX-STALE`: regenerate with `dart run zuke_cli:zuke generate --root <example>` and commit generated outputs when the project contract requires them.
- Flutter cache/launcher errors: distinguish an unwritable SDK cache, missing Flutter snapshot/package configuration, batch-file argument parsing, and a failing test. Check `FLUTTER_ROOT`, SDK preparation, runner mode, and the actual first launcher diagnostic.
- Windows-only `pub get` conflicts: inspect workspace-level dependency overrides and Flutter SDK-pinned `test_api` versions; do not add a broad override that breaks Flutter packages.
- Melos "Cannot override workspace packages": inspect example `pubspec.yaml` and `pubspec_overrides.yaml` together with the root workspace package list. Use workspace-compatible path/hosted dependency structure and preserve intentional example isolation.
- Formatting failures: run the repository's exact format command locally, then inspect `git diff --check`. Do not relax a formatting gate unless the user explicitly wants policy changed.
- Coverage-suite failures: run the failing package test directly before changing coverage thresholds. A conformance fixture that still expects a retired semantic is a stale test contract; update it to the active Zuke schema/configuration, while retaining legacy values only in deliberate negative tests.
- Dart test worker timeouts: distinguish a real failed test from the repository runner timing out after five minutes. If the log has no failing test summary, but the package duration is approximately `300000ms`, first rerun the affected package with `dart test -j 2` and, for the coverage workflow, set a deliberate positive `ZUKE_TEST_WORKERS` override so the package receives at least two isolates. Keep the package timeout fail-closed; do not turn a timeout into a success or treat expected negative-test diagnostics as failures.
- Cross-platform parity failures: inspect the complete expected/actual diff, not just the test name. Separate semantic fields from environment-specific metadata such as temporary roots, absolute paths, drive letters, path casing, or 8.3 Windows spellings. Normalize or omit only the non-semantic metadata in the parity fixture; never normalize away real source, graph, digest, or behavior differences.

### 4. Patch minimally and preserve boundaries

- Edit with `apply_patch`; preserve unrelated user changes and existing package separation.
- When a fix changes a generator, schema, configuration, or specification, regenerate through the project CLI rather than hand-editing generated Dart, indexes, manifests, or locks.
- When a changed control or schema invalidates a conformance assertion, update the executable conformance test and run the targeted test plus the aggregate coverage command. Do not alter signed assurance JSON merely to satisfy a test.
- Keep normal dependencies and `dev_dependencies` in their intended layers. Do not collapse specialized packages into a facade just to make a CI command pass.
- Keep local/mock demonstrations honest: label them as local evidence and document how a production integration such as APIM would enforce the corresponding control. A GitHub Actions pipeline proves the checked-in application behavior and assurance workflow; it does not prove an external gateway that is not present.
- For a matrix that should appear as one collapsible example in GitHub Actions, put the matrix inside a reusable workflow with an internal `verify` job, then call it from the parent workflow. Renaming direct matrix jobs does not create a collapsible group; reusable-workflow callers render as `example-assurance / verify (os)` like the other example checks.
- A reusable-workflow refactor can invalidate repository conformance tests even when the workflow is correct. If every OS reaches coverage and `zuke_conformance` reports one failure such as `Expected: contains '--profile pullRequest'`, inspect the test before changing the workflow: callers may pass `profile: pullRequest` through `with:` while the reusable workflow contains the eventual `--profile` command. The contract test should accept and validate both direct CLI flags and reusable-workflow inputs.

### 5. Verify before handoff

Run the narrowest reproducer first, then the relevant repository gates:

- exact failing CLI command and its prerequisite profile preparation;
- the failing package-level test extracted from any aggregate command;
- `dart format --output=none --set-exit-if-changed` for the affected Dart paths;
- `dart analyze`/`flutter analyze` and affected tests;
- `generate --check`, `validate`, `lock --check`, `check`, and `gate` for the affected example/profile;
- `git diff --check` and a final generated-file status check.
- For line-ending/path fixes, run the parity test on Windows when possible and run the same test on at least one Unix runner; a Unix pass does not prove Windows path canonicalization.
- For worker-budget changes, verify the effective `Dart test worker budget` and `workers/package` values in the CI log, then confirm every package reports `passed` before the aggregate coverage command proceeds.

For multi-OS failures, prove whether the fix is shared by checking the same command path and expected hash on each matrix job. If local Windows cannot run the Flutter launcher because its SDK cache is unwritable, report that limitation separately and use the GitHub runner result as the platform evidence; never silently claim the full local suite passed.

After the patch, re-read the PR checks and residual logs when GitHub access is available. If checks cannot be rerun from the current environment, state exactly what was verified locally and what remains pending on GitHub.

## Reporting format

End with:

1. root cause, including the earliest failed step and whether it was shared across OSes;
2. files changed and why;
3. verification performed and its result;
4. any environment limitation or required signer/release workflow;
5. whether the change has been committed or pushed (never imply either happened unless it did).
