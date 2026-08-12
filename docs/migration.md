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
  # Previous coordinated set:
  # zuke_cli: ^0.3.1
  # zuke_runner_flutter: ^0.2.1

  # Current set:
  zuke: ^0.3.0
  zuke_cli: ^0.4.0
  zuke_runner_flutter: ^0.3.0
```

Keep the versions in the same coordinated row. Do not add path dependencies
or dependency overrides to make a hosted consumer resolve.

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
```

The profile test must immediately precede its lock operation because the
current evidence publication is replaceable and profile selections are
deliberately different. `zuke lock --all-profiles` is available as a
convenience when a workflow retains current evidence for every profile; in a
replaceable single-output workflow, use the explicit sequence above so a
single profile cannot be mistaken for all-profile proof.

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

## 6. Update CI

CI should run direct project tests independently of Zuke, then run the current
generation, validation, profile-lock checks, and gate. Verify that checks do
not rewrite locks. Hosted compatibility fixtures must run outside both the
application and framework workspaces with no path dependencies or overrides.

Run the exact package tuple on every supported operating-system lane before
closing the migration.

## 7. If you are not ready yet

Remain on the previous hosted package versions. Previous releases remain
available as historical versions and do not receive new features. Do not mix
the previous CLI with current generated artifacts, or the current CLI with
legacy configuration and lock files. Upgrade when you can apply this guide in
one controlled change.
