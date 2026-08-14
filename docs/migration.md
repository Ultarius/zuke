# Migrating to the Current Zuke Release

This guide is for existing Zuke users upgrading package versions. New projects
should use the normal installation guide in `docs/integration-guide.md`.

The current release is the single supported Zuke product on `main`. Migration
is managed by semver on pub.dev: users who are not ready can keep their
previous package versions pinned, while users who upgrade must apply the steps
below and regenerate derived artifacts.

## 1. Bump the hosted dependencies

Replace the previous coordinated package set with the current hosted set. The
exact versions are authoritative in `docs/release-matrix.yaml`.

An illustrative migration is:

```yaml
dev_dependencies:
  # Previous coordinated set (last published tuple):
  # zuke_core: ^0.3.0
  # zuke_annotations: ^0.3.0
  # zuke_frontend: ^0.2.1
  # zuke: ^0.3.1
  # zuke_runner: ^0.3.1
  # zuke_runner_flutter: ^0.3.1
  # zuke_http_runtime: ^0.1.1
  # zuke_cli: ^0.4.1
  # zuke_dart_build_hook: ^0.3.0

  # Current coordinated set:
  # zuke_core: ^0.4.0
  # zuke_annotations: ^0.4.0
  # zuke_frontend: ^0.2.1
  zuke: ^0.4.0
  zuke_runner: ^0.4.0
  zuke_runner_flutter: ^0.4.0
  zuke_http_runtime: ^0.1.1
  zuke_cli: ^0.5.0
  zuke_dart_build_hook: ^0.4.0
```

Keep the versions in the same coordinated row. Do not add path dependencies
or dependency overrides to make a hosted consumer resolve.

The coordinated release removes placement `target` from `ImplementsRequirement`,
`PresentsRequirement`, `ZukeBinding`, and `VerifiesRequirement` as well as
`ProvidesControl`. Placement is resolved from workspace package membership and
the active extraction target. Standalone extraction with multiple applicable
targets fails closed; pass the target explicitly. If two implementations share
one requirement, give them distinct stable slots such as `create` and `join`;
all slots are required by default. Verification-backed controls are validated
by their provider and current evidence, while structural controls remain owned
by graph dominance.

## 2. Remove retired package dependencies

Implementation modules are now folded into the supported hosted packages:

| Retired package | Current owner |
| --- | --- |
| `assurance_ir` | `zuke_core` and `zuke_cli` |
| `adapter_sdk` | `zuke_core` and `zuke` |
| `evidence_ledger` | `zuke_cli` |
| `dart_extractor` | `zuke_cli` |
| `proof_engine` | `zuke_cli` |
| `zuke_generator` | `zuke_cli` |
| `zuke_reporter` | `zuke_cli` |
| `zuke_adapter_dart_frog` | `zuke_cli` |
| `zuke_flutter_runtime` | `zuke_runner_flutter` |
| `zuke_analyzer`, `zuke_conformance`, `zuke_verifier`, `zuke_test_support` | repository-only tooling |

Applications should depend on the public facades and should not import these
retired package names.

## 3. Update `zuke.yaml`

The current CLI accepts schema 3 only. Add stable target and package identity
where execution or evidence is configured:

```yaml
schemaVersion: 3

targets:
  backend:
    language: dart
    framework: dart-frog
    packages:
      - id: backend
        path: .
        roots: [lib, routes]

execution:
  runners:
    - id: backend-tests
      target: backend
      sourcePackage: backend
      sourceAdapter: dart-frog
      sourceCompatibilityId: dart-frog-gen-2-route-topology-v1
      runnerCompatibilityId: backend-runner-v1
```

Schema 2 and older configurations fail closed with a structured diagnostic
and a pointer to this document. The current CLI does not infer missing
identities or partially normalize an old configuration.

## 4. Regenerate current artifacts

After upgrading packages and configuration, regenerate all derived state:

```bash
dart run zuke_cli:zuke generate --root .
for profile in pullRequest merge release nightly; do
  dart run zuke_cli:zuke test --root . --profile "$profile"
  dart run zuke_cli:zuke lock --root . --profile "$profile"
  dart run zuke_cli:zuke lock --root . --profile "$profile" --check
done
dart run zuke_cli:zuke gate --root . --profile pullRequest
# Release/nightly verification can cover every configured profile:
dart run zuke_cli:zuke gate --root . --all-profiles --format json
# Coverage is a separate quality gate:
dart run zuke_cli:zuke coverage --root . --format json --output coverage/report.json
```

The profile test must immediately precede its lock operation because the
current evidence publication is replaceable and profile selections are
deliberately different. `zuke lock --all-profiles` is available as a
convenience when a workflow retains current evidence for every profile; in a
replaceable single-output workflow, use the explicit sequence above so a
single profile cannot be mistaken for all-profile proof.

For checked-in examples or other workspaces maintained from this repository,
the same safe sequence is available as one repository tool:

```bash
# Discover every Zuke project from the root pubspec.yaml workspace:
dart run tool/regenerate_profile_locks.dart

# Or refresh one project explicitly:
dart run tool/regenerate_profile_locks.dart --root examples/todo_app
```

With no `--root`, the tool reads the root `pubspec.yaml` workspace members and
walks each member upward to its nearest `zuke.yaml`. This discovers nested
projects such as `examples/calculator-product` while ignoring SDK-only package
members that do not own profile locks. It then reads `lock.profiles` from each
project, runs `zuke test` for each profile, generates that profile's lock, and
immediately runs its non-mutating check. It does not edit lock JSON directly.
Multiple roots and selected profiles can be supplied with repeated `--root`
and `--profile` options.

The current lock files are:

```text
assurance/locks/pullRequest.lock.json
assurance/locks/merge.lock.json
assurance/locks/release.lock.json
assurance/locks/nightly.lock.json
```

Regeneration also refreshes generated contracts, evidence records, reports,
manifest inputs, and current signed-history records under
`assurance-history/records/` and `assurance-history/trust/ed25519.json`.

Legacy locks, legacy result markers, and old history paths are rejected rather
than read as current data. Remove or archive them outside the active current
paths before checking in regenerated output.

### Non-portable artifacts

Derived files from the previous release are not inputs to the current CLI.
They must be regenerated after the package and configuration upgrade:

| Previous artifact or identity | Current action |
| --- | --- |
| Old evidence records, including semantic/legacy record shapes | Delete or archive outside active evidence directories, then rerun managed tests. |
| Root `zuke.lock.json` or version-marked lock files | Remove them and generate `assurance/locks/<profile>.lock.json`. |
| `assurance-history/v2`, legacy exports, or `trust/verifier.json` | Keep only as historical material outside current history paths; regenerate current records and trust files. |
| Signatures made with the previous release or attestation signing domains | Re-sign current release/attestation documents; old signatures are not valid for current verification. |
| Runner names used as `sourceAdapter` such as `dart-test` or `flutter-test` | Set the actual extractor adapter (`dart-source` or `dart-frog`) and keep runner semantics in `runnerCompatibilityId`. |

The current CLI rejects these shapes and identities instead of guessing a
conversion. Git history or a separately archived migration bundle is the
rollback path; legacy files must not remain in locations scanned as current
assurance state.

## 5. Update imports and command names

Use the current unversioned public APIs:

```dart
import 'package:zuke/zuke.dart';
import 'package:zuke_core/zuke_core.dart';
```

Use `CommandResult`, `Diagnostic`, `EvidenceRecord`, `AdapterOutput`, and
`AdapterCompleteness`. Remove imports of public versioned barrels and aliases.
The current manifest command is:

```bash
dart run zuke_cli:zuke manifest verify --root .
```

For ordinary Dart and Flutter tests that should publish evidence, use the
managed registration helpers from `zuke_runner` and
`zuke_runner_flutter` (`zukeTest` and `zukeTestWidgets`). They remain ordinary
tests when no managed runner context is present and publish nothing when the
assertions fail. Existing low-level emitters can remain during migration until
the hosted Linux and Windows consumer proof is green.

## 6. Update CI

CI should run direct project tests independently of Zuke, then run the current
generation, validation, profile-lock checks, and gate. Verify that checks do
not rewrite locks. Hosted compatibility fixtures must run outside both the
application and framework workspaces with no path dependencies or overrides.

Run the exact package tuple on every supported operating-system lane before
closing the migration.

The framework repository owns the clean-room hosted check. Run it from the
repository root after the coordinated versions are available:

```bash
dart run tool/check_hosted_consumer.dart --platform linux
dart run tool/check_hosted_consumer.dart --platform windows
```

The check creates its fixture outside the repository, reads exact package
versions from `docs/release-matrix.yaml`, rejects path dependencies and
overrides, and removes the fixture after the run unless `--keep-fixture` is
provided for diagnosis. When the matrix contains Flutter-bound packages, the
checker requires Flutter on the machine, uses `flutter pub get`/`flutter test`,
and reports the Flutter package lane separately. It fails closed rather than
silently claiming the complete hosted tuple was verified with Dart alone.

The framework repository also provides `.github/workflows/hosted-consumer.yml`.
It runs the same checker on Linux and Windows after a published release, and
can be started manually when a hosted package tuple is ready for verification.

## 7. If you are not ready yet

Remain on the previous hosted package versions. Previous releases remain
available as historical versions and do not receive new features. Do not mix
the previous CLI with current generated artifacts, or the current CLI with
legacy configuration and lock files. Upgrade when you can apply this guide in
one controlled change.
