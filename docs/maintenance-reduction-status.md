# Zuke maintenance-reduction status

Updated: 2026-09-09

## Second scan implementation

All nine follow-up items are implemented:

1. Registration aliases require immutable bindings, respect block and parameter
   scope, and use cached analyzer line information instead of rereading files.
2. Crunch's lock proposal workflow delegates generation, managed execution,
   validation, and transactional lock publication to `lock --refresh`.
3. Ordinary Flutter coverage runs once with managed Zuke environment variables
   cleared; managed gates and platform/package jobs remain separate.
4. `CustomerJourney` replaces the string-keyed scenario state with typed fields.
5. Consumer-local fixtures share signed-in/dashboard setup, HTTP transport,
   browser page builders, store construction, and temporary-directory cleanup.
   Existing timeout values and optional response fields are preserved.
6. `WorkspaceRegistrationAudit` owns configured source discovery and integrity
   checks, including malformed specifications, missing cases, and overlapping
   runner roots. Crunch's integrity test calls this API.
7. `init --editor vscode` merges the refresh task and launch entry into JSONC
   files, with pub.dev-compatible commands, dry-run, and preflight protection.
8. All-profile gates forward runner mode. Release summaries retain the trust
   failure's specific message, project ownership, and actionable remediation.
   Trust paths normalize relative roots and dot segments while still rejecting
   paths outside the workspace.
9. The unused backend dependency-override script is removed; the release
   workflow already uses `doctor --check-overrides`.

Verification includes the focused consumer fixture suite, framework regression
and failure-path tests, clean targeted analysis, and all four managed profile
refreshes in both consumers. The new framework suites are included in the Linux
and Windows maintenance-parity matrix. Hosted CI has not been run locally.

## Six worthwhile follow-ups completed

The second optimization pass closed the remaining maintenance gaps:

1. Generated class aliases are resolved only from `final` or `const` fields, so
   a mutable alias cannot make static audit evidence disagree with runtime.
2. `dartTooling`, `policies.protectedSeverities`, and
   `lock.requireCleanGeneration` are validated and retained in typed
   configuration fields instead of being silently discarded.
3. Crunch provider and journey tests no longer assert counters or screen flags
   initialized by their own fixtures; external navigation now calls the real
   `ExternalHandoff` seam with a typed URI.
4. `lock --refresh --diff-output` owns lock-change receipts and
   `artifacts package` owns safe bundle assembly. Both consumer workflows use
   those commands instead of repeating copy loops and hardcoded lock lists.
5. Workspace registration audits parse their union of source files once and
   reuse the analyzer snapshot for each configured runner target.
6. `init --editor vscode` now generates the complete Zuke task set, including
   selected-profile refresh, verification, gate, generation, alignment, and
   doctor coverage, while preserving user JSONC entries.

## Independent verification of the six follow-ups (2026-09-09)

The review corrected five gaps in the earlier implementation:

- Generated aliases must be immutable static fields, not instance fields or
  local variables inside an unused class method.
- Snapshot selection matches normalized file paths, so independently created
  `File` objects still select their previously parsed units.
- Editor presets now define the referenced `zukeProfile` input. Both consumers
  received the complete preset; existing custom tasks remain preserved.
- Artifact package reports cannot be written inside the audited bundle.
- Lock receipts must use new files outside the lock directory, preventing a
  receipt from overwriting locks or an existing file.

Verification: 47 focused CLI tests, five configuration tests, 44 Crunch journey,
provider and streaming cases, and Crunch's registration integrity test passed.
Three backend registration/artifact integration tests also passed.
Targeted Dart analysis passed. Both consumers passed doctor and generation
checks after regenerating seven stale backend contract files. These are local
checks, not hosted certification or live platform evidence.
The initial read-only lock checks found stale/missing evidence in both consumers.
Both then passed `lock --refresh --runner-mode auto` (generation, managed tests,
validation and transactional publication) and the subsequent read-only lock
checks for all four profiles. Release trust gates were not rerun in this pass.

## Further opportunities found during verification

1. **Make configuration behavior explicit.** `ZukeConfig.dartTooling` remains
   a dynamic map, and the retained tooling, protected-severity and clean-generation
   fields have no CLI readers yet. Extraction still hardcodes `.zuke/cache`.
   Introduce named configuration types, then either implement supported settings
   or reject contradictory values. Do not imply that parsing a setting enforces it.
2. **Remove repeated bundle scans.** Both consumers still invoke `artifacts audit`
   immediately after `artifacts package`, which already audits the same files.
   Standardize the package result artifact and migrate upload consumers with
   output-schema parity tests before deleting the second invocation.
3. **Migrate legacy editor aliases deliberately.** The backend retains its three
   `dart_backend: zuke ...` lock tasks alongside the generated preset. Add a
   migration that updates launch/dependency references before removing these
   aliases, avoiding another manually maintained command set.

These are additional design/migration opportunities, not claims of completed
implementation. Hosted Linux/Windows parity remains pending.

## Completed maintenance follow-up

- `lock --refresh` discovers nearest Zuke roots from pub workspaces and accepts
  repeated `--roots` and `--profiles`. Windows fixtures verify multiple roots,
  selected profiles, failure before mutation, and rollback after publication
  fails. The three legacy refresh scripts were removed and editor tasks use
  the CLI. Obsolete consumer script launchers were removed.
- The eight duplicate consumer assurance tools were removed. Backend tests
  now exercise framework alignment, safe artifact copying, and gate recording.
  `gate record` preserves append-only history, diagnostic ownership, release
  identity, and the backend record format. `gate handoff` preserves the current
  owner-only handoff. Missing or malformed summaries fail closed. Current
  gate auxiliary JSON remains a separate snapshot format.
- Crunch's 88 unit case-ID defaults were removed and helper lookups replaced
  with generated enums, including server registrations. Its unused server
  catalog was removed. The audit no longer trusts the `contractFor` name and
  resolves omitted unit case IDs consistently with runtime registration.
- `init` now supports auto-detected Dart, Flutter, and Dart Frog presets with
  configured source roots, generation, managed runners and lock profiles.
  Dry-run and existing-config protection are tested. Product policies and
  trust material remain explicit.
- Generated package imports already satisfy the consumer import lint; no
  blanket lint suppression was added. Contract package metadata uses the
  named `ContractPackage` type.

Earlier migration verification: 91 focused framework regression tests, 89 Crunch unit
and integrity tests, and six migrated backend tool tests passed. A Linux and
Windows PR matrix now runs maintenance parity tests. Hosted certification,
trusted release attestations, and real-device proof remain separate gates;
the local results do not certify them.

Both consumers completed generation, managed tests, validation, and refreshed
lock checks for all four profiles. Their pull-request, merge, and nightly gates
pass. The release gate passes those same stages and then fails trust setup:
`dart_backend` has no trust bundle; Crunch has no active release signer. These
require an authorized release identity and public trust metadata.

This document records the implementation state of the shared Zuke changes and
the two consumers. It deliberately separates implementation, parity evidence,
consumer adoption, and CI verification. A passing local suite is not a hosted
certification result.

## Status dimensions

| Area | Implemented | Parity-tested | Consumer-adopted | CI-verified |
| --- | --- | --- | --- | --- |
| Portable WebSocket driver and recording sink | Yes | In-memory and VM loopback tests | `dart_backend` product behavior test | Pending clean hosted run |
| Ordinary Flutter `zukeTest` lifecycle | Yes | Existing runner tests plus consumer migration | `dart_backend` non-widget repository case | Pending clean hosted run |
| Flutter `zukeTestWidgets` lifecycle | Yes | Direct widget lifecycle test | Existing Flutter widget registrations remain direct | Pending clean hosted run |
| OpenAPI route topology | Yes | Verifier tests and backend contract case | Backend contract case uses verifier | Pending clean hosted run |
| Artifact scanning | Yes | JSON secret and bundle safety tests | Both workflows scan the exact upload staging directory | Pending clean hosted run |
| Alignment and override diagnostics | Yes | Missing-lock and contradictory-flag coverage | Both workflows use the shared doctor command | Pending clean hosted run |
| Registration audit | Yes | Unused-helper and forged-lookup negative fixtures | Flutter integrity test consumes it | Pending clean hosted run |
| Transactional lock replacement | Yes, full pipeline via `lock --refresh` | Failure/flag parity coverage and managed-pipeline fixture | Consumer tasks use `lock --refresh`; duplicate scripts removed after Windows multi-root and rollback parity | Pending clean hosted run |
| Canonical unit registration preset | Yes, `package:zuke/testing.dart` | Direct-registration audit and managed consumer run | Crunch ordinary Dart tests migrated; widget lifecycle tests remain explicit | Pending clean hosted run |
| Policy structural checks | Yes | Malformed/missing policy checks | Consumer risk-record workflow remains authoritative | Pending trusted-attestation work |
| Generated public barrel and scenario catalog | Yes, through `contractExport` | 23 generator tests; runtime metadata parity for 60 backend and 90 Crunch scenarios; 33 lock/manifest/determinism regressions | Both consumers migrated; all four profile lock checks pass; release trust setup remains | Pending clean hosted run |

The [September consumer audit](consumer-maintenance-audit-2026-09-07.md)
records the inspected paths, concrete reduction opportunities, migration steps,
and limits of the local evidence. Catalog parity compares generated enum metadata
at runtime; it does not certify product behavior or test registration.
The calculator's managed tests, validation, refreshed lock checks, and gates
passed locally for all four profiles on 2026-09-07. Hosted verification remains
pending.

## Corrections to earlier claims

- Counting `contractFor(...)` text, matching a function name, or matching a
  coverage percentage does not prove registration, execution, or equivalent
  behavior. The audit now distinguishes direct registration, managed execution,
  production file/line preservation, and runtime/platform proof.
- The native `lock` command still performs safe replacement and read-only
  checking of prepared locks. `lock --refresh` now supplies the complete
  generate → managed-test → validate pipeline before that transactional write;
  consumer scripts were removed after multi-root, multi-profile, Windows, and
  failure-path parity passed.
- OpenAPI verification checks route topology. It does not prove response
  schemas, authorization, or WebSocket business behavior. Unknown source
  methods fail verification with an explicit incompleteness diagnostic; they
  are never silently converted to `GET`. The Dart Frog adapter resolves leading
  method guards that return 405 and direct aliases that forward the original
  arguments. Unsupported control flow remains unknown.
  Resolved Dart Frog WebSocket handlers expose their HTTP `GET` upgrade method
  separately, including direct route aliases. Framework regression fixtures
  cover missing paths, wrong methods, shadowed symbols, and unused helpers;
  the backend contract test passes without path-specific unknown-method assertions.
  Backend root and health routes now enforce their documented GET-only contract;
  focused route tests cover rejection of every other supported method.
- A policy record's `authenticated` field or proof map is not trusted
  attestation. Trusted approval requires an independently supplied verifier;
  therefore the backend's existing risk-acceptance workflow remains in place.
- Fixture-based provider/WebView tests remain useful contract tests, but they do
  not prove live authentication, DRM, WebView2, Android/iOS, native C++, or
  Chrome execution.

## Package boundary

`zuke_test_support` remains repository-only with `publish_to: none` and is used
only through development dependencies inside the Zuke workspace. Its generic
WebSocket driver was moved to `package:zuke_runner/testing.dart`, so consumers
do not need a runtime dependency on unpublished support. Repository cleanup
helpers such as `deleteTemporaryDirectory` remain in `zuke_test_support`.
Ordinary consumer registrations now use `package:zuke/zuke.dart` or
`package:zuke/testing.dart`; `zuke_runner` remains only for compatibility-only
WebSocket and Flutter adapter surfaces.

## Remaining release gates

1. Pin and verify one published or hosted-compatible Zuke revision before
   removing local path overrides.
2. Run the added Linux and Windows maintenance-parity PR matrix on the final revision.
3. Migrate policy records to independently validated approval evidence before
   replacing the consumer risk checker.
4. Run clean hosted workflows, trusted attestation, and real target/device
   execution separately from local fixture assurance.
