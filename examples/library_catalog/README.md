# Library Catalog Example 🟢 (Beginner · Pure Dart)

Specs-first pure Dart example that shows why the Zuke analyzer plugin is useful.

This package was built **up from `specs/`**: no handwritten application code
existed before `zuke generate` compiled the feature into typed contracts.

## Build order (what we actually did)

1. **Write the specification** — `specs/features/library_catalog.feature`,
   epic, controls, PBIs, policies, and `zuke.yaml`.
2. **Generate contracts from specs alone**:

   ```bash
   dart run zuke_cli:zuke generate --root examples/library_catalog
   ```

   That produced:

   - `lib/src/generated/feat_library_001_contracts.g.dart` (typed bindings,
     requirement IDs, scenario contracts)
   - `lib/zuke_contracts.dart` (barrel)
   - `test/support/generated/feat_library_001_steps.g.dart` (step scaffolds)
   - `.zuke/analyzer-index.json` (what the analyzer plugin validates against)

3. **Implement against the generated types** — `CheckoutController` +
   `CatalogBindings` import generated IDs instead of free-typing strings.
4. **Verify** — unit tests annotate `@VerifiesRequirement` so the analyzer
   can prove every implemented rule has coverage.

## Pure-Dart Gherkin runner + branch peer connection (unique to this example)

Unlike the Flutter examples (which use `flutterVendorSteps` +
`ZukeFlutterHarness`), this package wires the generated step scaffolds into a
plain `StepRegistry` + `ScenarioExecutor` with no Flutter dependency — and
includes a **peer-to-peer branch connection** scenario that no other example has:

```gherkin
Rule: Branches connect peer-to-peer to share loan state

  Scenario: Two branches establish a peer connection
    Given branch "north" is listening for peers
    And branch "south" is listening for peers
    When branch "north" connects to branch "south"
    Then the peer connection between "north" and "south" is established
```

Under the hood, `BranchPeerServer` binds a loopback `ServerSocket`, connects
with a plain TCP client, and exchanges JSON loan-register snapshots — all pure
`dart:io`, no Flutter, no external broker.

```dart
// test/support/library_gherkin_steps.dart
buildLibraryRegistry() => buildStepRegistry([
  ...const FeatLibrary001GeneratedSteps<LibraryWorld>().build(
    theCheckoutDeskIsOpen: (world) { /* ... */ },
    branchIsListeningForPeers: (world, id) async { /* ServerSocket.bind */ },
    branchConnectsToBranch: (world, from, to) async { /* Socket.connect */ },
    // ... other generated callbacks
  ),
  StepDefinition.cucumber(
    expression: CucumberExpression(
      'element {string} displays {string}',
      StepParameterTypeRegistry.standard(),
    ),
    // pure-Dart binding display assertion (no WidgetTester)
  ),
]);
```

`test/library_gherkin_test.dart` loads the feature with `ZukeFeatureLoader`,
resolves each generated scenario contract, and executes it end-to-end —
including `element "library.*" displays "..."` steps that read controller
state instead of a widget tree, and the peer scenarios that open real loopback
sockets. This is the canonical non-Flutter demo of Zuke's pure-Dart scenario
execution path.

## Analyzer plugin (why this example exists)

The package includes the root analysis options (plugin at workspace root), so
VS Code / `dart analyze` report Zuke diagnostics as normal Problems:

| Rule | Severity | What it catches here |
| --- | --- | --- |
| `zuke_annotation` | error | `@ImplementsRequirement` / `@ZukeBinding` on an unsupported target, or empty IDs |
| `zuke_index_stale` | error | You edited `specs/**` or `zuke.yaml` but forgot `zuke generate` |
| `zuke_unknown_index_id` | error | Typo in a binding / control / requirement ID that is not in the index |
| `zuke_missing_test` | warning | `@ImplementsRequirement` with no matching `@VerifiesRequirement` after generate |

### Try each failure (then undo)

1. **Stale index** — change any line in
   `specs/features/library_catalog.feature` and save without regenerating.
   Every file in this workspace should show
   `ZUKE-INDEX-STALE: Run zuke generate before analysis.`
   Fix: `dart run zuke_cli:zuke generate --root examples/library_catalog`.

2. **Unknown ID** — in `lib/src/catalog_bindings.dart`, change
   `'library.isbnInput'` to `'library.isbnInputt'`.
   You get `zuke_unknown_index_id` at the annotation.
   Fix: restore the generated ID (or regenerate after editing the feature).

3. **Missing test** — delete `@VerifiesRequirement` from
   `test/checkout_controller_test.dart`, run `zuke generate`, then analyze.
   `zuke_missing_test` warns that `RULE-LIBRARY-CHECKOUT` /
   `RULE-LIBRARY-BOOK-RETURN` are implemented but unverified.
   Fix: restore the annotation and regenerate so the index records
   `verifiedRequirementIds`.

4. **Bad annotation target** — put `@ImplementsRequirement` on a `field`
   instead of the class. `zuke_annotation` rejects unsupported targets.

Suppression (only when intentional):

```dart
// ignore: zuke/zuke_annotation
```

## Checkout desk TUI

`bin/library_desk.dart` is a pure stdin/stdout terminal UI over the same
`CheckoutController` the tests exercise (no Flutter, no extra packages):

```bash
# From repo root
dart run examples/library_catalog/bin/library_desk.dart
# or from this package
dart run bin/library_desk.dart
```

Commands: `help`, `catalog`, `checkout <isbn>`, `return <isbn>`, `loans`,
`status`, `reset`, `quit`.

Peer simulation is one command (then inspect and tear down):

```text
peer            # north <-> south listen, connect, seed, share, status
peer loans      # view local + received peer loans (ISBN + title)
peer loans north
peer status
peer close      # close peer branches
```

Advanced step-by-step: `peer listen <id>`, `peer connect <from> <to>`,
`peer seed <id> <isbn>`, `peer share <from> <to>`, `peer status`.

In VS Code, launch **Library Catalog (Checkout Desk TUI)** — it opens in an
external terminal window (`"console": "externalTerminal"`).

## Commands

```bash
# From repo root
dart run zuke_cli:zuke generate --root examples/library_catalog
dart run zuke_cli:zuke generate --root examples/library_catalog --check
dart test examples/library_catalog
dart analyze --fatal-infos examples/library_catalog
dart run examples/library_catalog/bin/library_desk.dart
```

Or via Melos scripts: `zuke:library:generate`, `zuke:library:validate`,
`zuke:library:gate`.
