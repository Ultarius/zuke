# Consumer maintenance audit — 2026-09-07

This is the original audit snapshot. The 2026-09-08 follow-up in
[maintenance-reduction-status.md](maintenance-reduction-status.md) supersedes
the remaining-work statuses below: duplicate tools and refresh scripts have
been retired, direct registrations migrated, and init presets implemented.

The requested projects are present as sibling directories `dart_backend` and
`crunch_flutter` under `C:/Users/DAMIEN/Documents/GitHub`. The supplied
`dart/_backend` and `crunch/_flutter` paths do not exist. This audit uses the
former directories and the maintenance-reduction guideline supplied with the
request. The Crunch consumer was migrated in this change; unrelated existing
consumer modifications were preserved.

## Findings and priorities

| Priority | Observed maintenance burden | Framework action and adoption condition |
| --- | --- | --- |
| Implemented / adopted in Crunch | Crunch maintained a 148-line scenario catalog and a 47-line barrel. Its server has a further 13-line catalog. Backend already configures `contractExport`. | Generate the aggregate and lookup through `contractExport`. Runtime parity checked against both consumers' existing feature enums. Crunch imports now use the generated barrel; its catalog and root barrel were removed. The server catalog remains a deliberate package boundary. |
| Framework implemented; editor-task adoption complete | Both `tool/regenerate_profile_locks.dart` files are identical, 445 lines each. SHA-256: `01f9f1c35ae4fab330b919075098f3b2afd0816b51592df8c179f2735f09ef0e`. | `zuke lock --refresh --all-profiles` now owns generate → check → managed test → validate → transactional lock publication. The command is covered by Windows lock-parity tests, and both consumers' editor refresh tasks invoke it. Retain the scripts until multi-root, profile selection, Windows launching, early failure, and rollback parity are proven against both consumers; CI workflow removal was intentionally deferred. |
| Cleanup | The alignment, artifact-scan, gate-recorder, and handoff scripts total 416 lines in Crunch and 949 in backend. Active assurance workflows already call framework doctor, artifacts, and gate commands. | Retire unused copies after checking all callers and migrating local tool tests. Backend tests still import/run several copies. Their legacy report formats and history behavior need explicit comparison; line counts alone do not prove replacement parity. |
| Implemented / adopted in Crunch | Crunch's test sources contain 96 `caseId:` occurrences, repeatedly paired with `unit` evidence and primary implementation slots. | Canonical `package:zuke/testing.dart` now exposes `zukeUnit`, which supplies the stable unit evidence and primary implementation-slot defaults while retaining direct registration. Thirteen ordinary Dart test files were migrated; widget tests remain on `zukeTestWidgets` because they require the Flutter host lifecycle. The registration audit recognizes `zukeUnit`, and managed Crunch execution passed after migration. No API was added to the compatibility `zuke_runner` package. |
| Later | Both configurations repeat source adapter compatibility IDs and managed-runner settings. Crunch's widget tests also repeat descriptions despite an existing default. | Keep product evidence kinds, runner roots, timeouts, and profile selection explicit. Generate stock setup through init presets; default only what can be derived unambiguously. Use existing default descriptions where custom wording adds no value. |
| Retain | Backend has a 135-line release risk-acceptance checker, and consumers own product-specific state, provider fixtures, and registration-integrity tests. | Do not replace trusted approvals with a policy boolean, or runtime evidence with a source count. Consolidate product fixtures inside each consumer; harvest only reusable mechanics with proven semantics. |

The Crunch migration removes approximately 195 maintained catalog/barrel lines,
replacing them with generated output and imports. The 13-line server catalog has
its own boundary and remains. The current patch adds framework implementation,
tests, generated example output, and the consumer migration.

The developer-facing lock tasks in both consumers now invoke
`zuke lock --refresh --all-profiles` directly. The checked-in CI workflows still show their
individual stages while the new command accumulates hosted and failure-path
parity evidence; this avoids hiding a stage before the replacement is proven
equivalent in every environment.

## Implemented generator change

`targets.<owner>.contractExport` now produces the public barrel and an immutable
`generatedScenarioContracts` map with the existing consumer lookup name
`zukeScenarioContract(String)`. Entries come from generated enum values, so IDs,
rules, titles, and control declarations have one source. No runner API, test
registration wrapper, or unpublished runtime dependency was introduced.

The audit also exposed defects in the existing barrel generation:

- Imports were hard-coded to `src/generated`, ignoring output/export locations.
- Generated test step files were exported as if they were contract libraries.
- Barrels lacked the generated-file marker, so subsequent edits could be refused.
- Root-package confinement used `lib/src/lib` instead of the actual `lib` directory.
- Repeated legacy rule aliases could create ambiguous exports across features.

These are corrected. Unambiguous rule aliases remain available. Duplicate aliases
stay accessible from individual feature libraries; canonical feature enums remain
available through the aggregate. Existing manifest placement is preserved.
Exact legacy export-only content is recognized using its existing manifest;
handwritten additions are still refused. Empty workspaces produce an empty
catalog, and duplicate scenario IDs abort generation before output replacement.

## Local evidence and limits

- Both consumer `doctor --format json` runs passed. Backend warned that
  `specs/registry/retired-ids.yaml` is absent. These were configuration doctors,
  not hosted dependency-alignment certifications.
- Generated each consumer's contracts into temporary directories and executed
  Dart probes comparing the new catalog with the existing feature enums:
  backend: **60 scenarios / 9 enums**; Crunch: **90 scenarios / 44 enums**.
  Every ID, rule, title, and sorted control set matched. Temporary outputs were
  removed; no consumer generation or lock files were changed.
- `generate_command_test.dart` and `zuke_generator_test.dart`: **23 tests passed**.
  Fixtures exercise root/nested/custom paths, Windows separators, executing the
  generated lookup, unknown IDs, immutability, duplicate IDs, stale and removed
  features, empty catalogs, barrel collisions, and handwritten-file protection.
- Lock parity, lock manifests, line-ending parity, release determinism, and
  manifest-command regressions: **33 tests passed**. Initial sandbox cache
  denials were resolved by rerunning with the required cache access.
- Targeted static analysis passed for both modified implementation files and
  both test files. The calculator example was regenerated and `generate --check`
  passed, exercising automatic upgrade of its old markerless barrel.
- Calculator managed tests and validation passed for `pullRequest`, `merge`,
  `release`, and `nightly`. Its old locks correctly failed after the manifest
  change. `lock --all-profiles --update` then refreshed them from the prepared
  evidence, and all four lock checks and `gate --all-profiles` passed. The
  configured release trust stage passed; other profiles skipped that stage.
  Signed assurance-history files were not modified.
- Crunch managed tests and validation passed for all four profiles after the
  migration. Its pull-request, merge, release, and nightly locks were refreshed
  from that evidence and each `lock --check` passed. The all-profile gate passed
  doctor, generation, tests, input stability, validation, and locks for all
  profiles; only release trust failed because its existing trusted-attestation
  bundle does not accept this local run.
- Backend generation upgraded its configured barrel and generated manifest. Its
  pull-request gate reached test/validation but failed on unrelated staged source
  extraction and existing evidence errors (including missing `test` imports and
  stale records); backend locks were deliberately not refreshed from ineligible
  evidence.
- `lock --refresh` was exercised by the framework's Windows lock-parity test:
  generation and its check ran first, every configured profile executed through
  the managed test/validation path, and locks were written only after those
  stages succeeded. Contradictory `--check`/`--refresh` flags are rejected.

These checks establish generation and metadata parity on this Windows machine.
They do not establish consumer adoption, direct-registration parity after an
import migration, live backend/provider behavior, device execution, Linux
execution, trusted approval evidence, or hosted certification. The status table
keeps those dimensions separate.

## Consumer migration

Crunch now configures `contractExport: lib/crunch_flutter_contracts.dart`,
imports that generated library from `test/zuke_scenario_support.dart`, and has
removed `test/zuke_contract_catalog.dart` and the handwritten public barrel.
Direct `zukeTest` calls and the existing `contractFor` support adapter remain.
For new direct registrations use feature enums: the current source audit does
not resolve arbitrary `zukeScenarioContract(...)` calls. Matching a helper's
name alone is not execution proof. The server's narrower contract exposure stays
deliberate.

Backend already configures `contractExport` and its public barrel now comes from
the generator. Complete backend lock refresh remains gated on repairing the
pre-existing staged test/extraction failures and regenerating eligible evidence.
Backend ordinary Dart tests now import `package:zuke/zuke.dart`; the
compatibility package remains only where a package still consumes the portable
WebSocket sink or Flutter adapter. The migrated backend subpackages declare
`zuke` directly and no longer declare `zuke_runner` solely for `zukeTest`.

For both projects, use `doctor` → `generate --check` → `test --profile` →
`validate --profile` → `lock --profile --check` → `gate --profile`. When locks
need to be rebuilt, `lock --all-profiles --refresh` owns that sequence and only
publishes after fresh managed evidence is eligible. Keep hosted certification as
a separate gate.
