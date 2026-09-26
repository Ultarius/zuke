# Zuke release runbook

End-to-end release procedure for the solo maintainer. There are two independent
tracks: **SDK packages** to pub.dev (triggered by `sdk-v*` tags) and **signed
example releases** (triggered by `v*` tags). Flutter **3.44.8** (stable) is the
pinned toolchain for every step. Local package versions and the publish order
are defined by [release-matrix.yaml](release-matrix.yaml).

## SDK package release

1. **Bump versions in the release matrix.** Edit
   [release-matrix.yaml](release-matrix.yaml): set `version`,
   `previousVersion`, and `bumpReason` for every changed package. Keep
   `publicationOrder` equal to the packages with `releaseAction: publish`
   (the docs check enforces both, plus pubspec/matrix version parity).
2. **Regenerate the release contract:**

   ```bash
   dart --suppress-analytics run tool/generate_release_contract.dart
   dart --suppress-analytics run tool/generate_release_contract.dart --check
   ```

   This writes `vendor-sdk/zuke_cli/lib/src/generated/release_contract.dart`
   from the matrix; `release_contract_test` fails if it is stale.
3. **Refresh locks if specifications, profiles, or generated contracts
   changed** (otherwise CI fails on stale locks):

   ```bash
   dart run zuke_cli:zuke lock --refresh --all-profiles
   ```

   Commit the matrix, the generated contract, and the refreshed
   `assurance/locks/` files together.
4. **Run the full quality gate:**

   ```bash
   dart --suppress-analytics run melos run zuke:check
   ```
5. **Tag the SDK release** and push it:

   ```bash
   git tag sdk-v<version>
   git push origin sdk-v<version>
   ```

   The [sdk-release.yml](../.github/workflows/sdk-release.yml) workflow runs
   framework-boundary, dependency-firewall, and analyzer-resolution checks,
   `melos run zuke:check`, and `dart pub publish --dry-run` for every
   publishable package, and uploads the `zuke-json-schemas` artifact. Do not
   continue until it is green. The tag can also be verified manually with
   `workflow_dispatch`.
6. **Dry-run the publisher locally:**

   ```bash
   dart --suppress-analytics run tool/publish_packages.dart --dry-run
   ```

   Add `--ignore-warnings` only for the expected dirty-worktree warning.
   The script preflights the docs checks, the generated release contract, and
   framework boundaries before touching pub.
7. **Publish** (dependency order, `zuke_core` first; confirms interactively):

   ```bash
   dart --suppress-analytics run tool/publish_packages.dart --publish
   ```

   Versions that already exist on pub.dev are skipped; `previousVersion` must
   match pub.dev's current latest for each package. To retry one package after
   a partial release, pass `--package <name>` (repeatable).
8. **Certify the hosted tuple.** Trigger
   [hosted-consumer.yml](../.github/workflows/hosted-consumer.yml)
   (`workflow_dispatch`, or publish a GitHub Release). It certifies the exact
   published versions across dart/flutter on Linux and Windows and builds the
   hosted compatibility manifest artifact.

## Example app release (signed assurance)

1. Start from a clean `main` with current locks (see step 3 above if specs
   changed). Verify before tagging:

   ```bash
   dart run zuke_cli:zuke lock --root examples/calculator-product --profile release --check
   dart run zuke_cli:zuke lock --root examples/shopping_cart --profile release --check
   dart run zuke_cli:zuke lock --root examples/todo_app --profile release --check
   ```
2. **Tag and push:**

   ```bash
   git tag v<version>
   git push origin v<version>
   ```
3. [release.yml](../.github/workflows/release.yml) runs the calculator,
   shopping-cart, and todo-app assurance workflows at `profile: release`
   (the calculator regenerates its lock first), then the `release-sign` job:
   - downloads the assurance artifacts,
   - exchanges GitHub OIDC for a short-lived Azure signer token in the
     `release-signing` environment,
   - revalidates evidence (`validate`, lock `--check`, `--all-profiles` gate),
   - creates, verifies, and exports the signed records for the calculator and
     shopping cart,
   - uploads the `zuke-signed-assurance-release` artifact (90-day retention).
4. **Commit the signed records.** Download the artifact and merge the new
   `assurance-history/records/` entries for
   `examples/calculator-product` and `examples/shopping_cart` back into `main`
   through a normal PR so the next release appends to the same chain.

## Bootstrap history workflows (temporary)

These exist only until each example has its first signed record. No genesis
records exist yet, so **do not delete them before that happens**. Open item 8
in [recommendations.md](recommendations.md).

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `bootstrap-zuke-shopping-history.yml` | `workflow_dispatch` or tag `zuke-assurance-bootstrap-shopping-*` | Produces release-profile evidence, signs the shopping-cart genesis record, and opens a PR containing it. |
| `bootstrap-zuke-calculator-history.yml` | tag `zuke-assurance-bootstrap-calculator-*` only | Produces release-profile evidence, signs the calculator genesis record, and uploads it as an artifact to download and commit (workflow has `contents: read`, so it does not push). |

When to use: once per example, **before** its first regular `v*` release, while
`<example>/assurance-history/records/` is still empty.

### Prerequisites

| Need | Why |
| --- | --- |
| GitHub environment `release-signing` | Both jobs declare `environment: release-signing`. |
| Env vars `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `ZUKE_SIGNING_PROVIDER_AUDIENCE`, `ZUKE_SIGNING_PROVIDER_URL` | OIDC → short-lived Azure signer token. |
| Var `RELEASE_SIGNER_KEY_ID` | `manifest create --key-id` (shopping defaults to `default` if unset). |
| Matching public key in `assurance-history/trust/ed25519.json` | `manifest verify` fails if the key id does not match the trust bundle. |
| Release-profile gates green for that example | Both workflows run `zuke test` / `validate` / `lock` at `profile: release` before signing. |
| Permission to push tags and merge PRs (shopping) / open PRs (calculator download → PR) | Genesis is useless if never committed to `main`. |

### Execution plan

1. **Preflight locally** (same gates the workflow will run), per example:

   ```bash
   dart run zuke_cli:zuke generate --root examples/<example> --check
   dart run zuke_cli:zuke test     --root examples/<example> --profile release
   dart run zuke_cli:zuke validate --root examples/<example> --profile release
   dart run zuke_cli:zuke lock     --root examples/<example> --profile release --check
   ```

   Repeat for `examples/calculator-product` and `examples/shopping_cart`.

2. **Trigger genesis** (one path per example):

   ```bash
   # Shopping: workflow_dispatch preferred, or:
   git tag zuke-assurance-bootstrap-shopping-genesis-v1
   git push origin zuke-assurance-bootstrap-shopping-genesis-v1

   # Calculator: tag only:
   git tag zuke-assurance-bootstrap-calculator-genesis-v1
   git push origin zuke-assurance-bootstrap-calculator-genesis-v1
   ```

3. **Land records on `main`:**
   - **Shopping:** review and merge bot PR `automation/zuke-shopping-assurance-history`
     (records land under `examples/shopping_cart/assurance-history/records/`).
   - **Calculator:** download artifact `zuke-calculator-genesis-history`, copy
     `examples/calculator-product/assurance-history/records/` into a normal PR.

4. **Verify the chain** on a fresh checkout:

   ```bash
   dart run zuke_cli:zuke manifest verify --root examples/calculator-product --current
   dart run zuke_cli:zuke manifest verify --root examples/shopping_cart --current
   ```

   Confirm `records/` is non-empty and the export matches.

5. **Cleanup (closes item 8)** after each example's record is on `main`:
   - Delete `.github/workflows/bootstrap-zuke-calculator-history.yml`
   - Delete `.github/workflows/bootstrap-zuke-shopping-history.yml`
   - Delete leftover tags:

     ```bash
     git push origin :refs/tags/zuke-assurance-bootstrap-calculator-*
     git push origin :refs/tags/zuke-assurance-bootstrap-shopping-*
     ```

   - Update this runbook (remove or mark historical the bootstrap section) and
     move item 8 to Done in [recommendations.md](recommendations.md).

6. **Regression safety:**
   - Next releases use only `release.yml` + `v*` tags (append-only chain).
   - Optionally add a CI check that fails if `assurance-history/records/` is
     missing for calculator/shopping once genesis is expected, so restoring
     the bootstrap workflows cannot silently re-fork history.

Do **not** invent a genesis record offline; the signature must come from the
real `release-signing` path. Todo-app has no bootstrap workflow; genesis there
would be a separate decision (signed history currently focuses calculator and
shopping in `release.yml`).

### After the first signed record for an example

Delete both workflow files and any leftover `zuke-assurance-bootstrap-*` tags
(tracked as open item 8 in [recommendations.md](recommendations.md)).

## Verification checklist

Before announcing any release:

- [ ] `docs/release-matrix.yaml` versions match every changed package's
      pubspec, and `publicationOrder` matches the `releaseAction: publish` set.
- [ ] Generated release contract regenerated and committed;
      `release_contract_test` passes.
- [ ] Locks refreshed and committed whenever specs or contracts changed.
- [ ] `melos run zuke:check` is green locally.
- [ ] `sdk-release.yml` green on the `sdk-v*` tag (including per-package
      dry-run publishes).
- [ ] `publish_packages.dart --publish` completed; each new version resolves
      on pub.dev.
- [ ] `hosted-consumer.yml` produced certification reports for dart and
      flutter on Linux and Windows, plus the compatibility manifest.
- [ ] `release.yml` green on the `v*` tag: all three assurance jobs and
      `release-sign`.
- [ ] Signed records from the `zuke-signed-assurance-release` artifact are
      committed to `assurance-history/records/`.
- [ ] `dart run zuke_cli:zuke manifest verify --root examples/calculator-product --current`
      and the same for `examples/shopping_cart` pass on a fresh checkout.
- [ ] README and docs that quote the package tuple reflect the new versions.
