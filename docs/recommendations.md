# Recommendations

Actionable follow-ups for Zuke, ordered by impact. The **Done** table lists
items completed either in the hardening pass that introduced this document or
in the later CI/docs follow-up pass.

## Done

| Area | Change |
| --- | --- |
| Release gating | `release.yml` now gates the todo app at `profile: release` (was `merge`). |
| Release scoping | Tag pushes pass `changed-since: ''` so `zuke affected` selects the full suite instead of diffing against an all-zero `event.before`. |
| Token permissions | Top-level `permissions: contents: read` on `pr`, `merge`, `nightly`, `release`, and both reusable assurance workflows. |
| Dependency updates | Added `.github/dependabot.yml` for `pub` and `github-actions` (weekly). |
| Static analysis | Root config includes `package:lints/recommended.yaml` and enables `strict-casts`; `dart analyze` / `flutter analyze` run with `--fatal-infos` in Melos and assurance workflows. |
| Example lint parity | Calculator example analysis options now include a real ruleset (`lints` / `flutter_lints`) instead of only `avoid_print`. |
| Path hygiene | Removed absolute local machine paths from `docs/consumer-maintenance-audit-2026-09-07.md`. |
| Tree hygiene | Deleted untracked CI logs (`run1.txt`, `run2.txt`), empty placeholder directories, and the empty duplicate `skills/` tree; dropped the CODEOWNERS entry for the removed empty `manifest_schema` directory. |
| Typed test helper | `runInProcessCli` returns a record with `String` stdout/stderr so tests type-check under `strict-casts`. |
| Public API surface | `zuke_core` exports `atomic_file_writer.dart`; internal `package:.../src/` imports in first-party code were removed. |
| Strict analysis modes | Root `analysis_options.yaml` enables `strict-inference` and `strict-raw-types` alongside `strict-casts`. |
| Security scanning | Added `.github/workflows/dependency-review.yml` (fails on moderate+ severity) and `.github/workflows/secret-scan.yml` (gitleaks on PRs and `main`), both SHA-pinned; GitHub push protection and optional CodeQL remain repository settings. |
| Workflow setup deduplication | Added the `.github/actions/setup-zuke` composite action (checkout + Flutter 3.44.8 + `pub get`); every job that used to inline those steps now calls it, so version bumps are single-touch. |
| PR parity coverage | `pr.yml` maintenance-parity runs the full `vendor-sdk/zuke_cli` package suite with a 20-minute timeout instead of a thirteen-file list, so new regression tests are never missed. |
| Community docs | Added `SECURITY.md` (private advisory reporting), `CONTRIBUTING.md`, and `docs/release-runbook.md`; the README links the runbook. |
| Coverage depth | Line-coverage gate remains; branch/mutation testing deferred and documented as optional future work. |
| God file split | `zuke_cli.dart` reduced to thin dispatch (~335 lines); parser, help, doctor, lock refresh, init/adopt, test runner, and hosted certify live in dedicated modules under `lib/src/`. |
| Test import hygiene | Workspace script/tool imports in `zuke_cli` tests go through `test/support/` re-export shims; no cross-package relative imports remain in test sources. |
| Catch-site hardening | `gate_record`, `owner_handoff`, and `policy_command` attach `FormatException` messages or `error.runtimeType` when degrading (no secret-bearing dumps). |
| Logging guidance | `CONTRIBUTING.md` documents the stdout/stderr channel policy for CLI, tooling, and workspace scripts. |
| Diagnostic registry | `ZUKE-COV-*` / `ZUKE-PACKAGE-TIMEOUT` migrated to `ZK-COVERAGE-*` / `ZK-PACKAGE-TIMEOUT` (legacy codes kept as `aliases`); artifact finding codes emit hyphenated `ZK-ARTIFACT-<CATEGORY>` and every category is registered; closed `ZK-GATE-*-FAILED` family registered. |
| Evidence digests | Mapping + specification-index digests use one pruned workspace walk (`WorkspaceDigest.computeEvidenceIndexDigests`); filtered digests skip the same ignored tool/platform directories as the full workspace digest, with equality and safety tests. |

## Recommended next

### High impact

3. **Finish the hosted release path**  
   Track the open gates in `docs/maintenance-reduction-status.md`: pin a
   hosted revision, run the Linux/Windows parity matrix on the final revision,
   and publish the coordinated package tuple so consumers can drop Git
   overrides. Publishing requires explicit maintainer approval.

### Medium impact

8. **Remove one-shot bootstrap workflows after genesis**  
   No genesis records exist yet (`assurance-history/records/` is empty for all
   examples). Keep `bootstrap-zuke-*-history.yml` until the first signed record
   is committed. The full plan—prerequisites (`release-signing` env, OIDC vars,
   trust key id), preflight gates, triggers, landing records, verification, and
   cleanup (workflow + tag deletion)—is in
   [release-runbook.md](release-runbook.md#bootstrap-history-workflows-temporary).

### Lower impact / polish

11. **Commit hygiene** — `CONTRIBUTING.md` documents the conventional
    prefixes; keep applying them — prefer `fix:` / `feat:` / `ci:` over
    blanket `chore:` for substantive changes, and tag releases so `v*` /
    `sdk-v*` workflows match real history.

