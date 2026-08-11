# Zuke Flutter integration guide

`examples/todo_app` is the recommended beginner Flutter integration.
`examples/shopping_cart` expands that setup with additional UI coverage, and
`examples/calculator-product` is the advanced mixed Flutter, Dart HTTP,
security-attestation, and release-history reference. The existing specialized
SDK packages are coordinated by the V2 release matrix in
`docs/release-matrix.yaml`; analyzer-dependent extraction is isolated from the
analyzer-free IR and adapter contracts.

---

## 1. Dependencies and setup

For a Flutter-only application, add the minimum dependencies to your `pubspec.yaml`:

```yaml
name: my_app
environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  zuke_annotations: ^0.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  zuke_cli: ^0.4.0
  zuke_runner_flutter: ^0.3.0
  # Optional edit-time/build-time checks:
  # zuke_analyzer: ^0.1.0
  # zuke_dart_build_hook: ^0.1.0
```

Application and generated code should use `zuke_annotations` when they only
need requirement, control, or binding metadata. Flutter test code should
import `zuke_runner_flutter`; it supplies the `testWidgets` harness, Flutter
binding keys, drivers, and vendor steps. Pure-Dart and backend tests should keep
`zuke` in `dev_dependencies` when parsing and execution are test-only.
`zuke` owns the deterministic runner and HTTP test helpers while re-exporting
the supported frontend and annotation APIs. This does not remove the narrower
`zuke_annotations` production boundary. `zuke_http_runtime` remains an opt-in
normal dependency for application-side HTTP registration. `zuke_runner` is a
source-compatible transition package for existing `0.1.x` consumers.

For development from this repository, use `dart pub get` at the workspace root;
the Pub workspace resolves these hosted constraints to the local packages.

### Compatibility matrix

| Component | Supported configuration | How to check |
| --- | --- | --- |
| Dart SDK | `>=3.10.0 <4.0.0` | `dart --version` |
| Flutter SDK | A Flutter SDK whose bundled Dart satisfies the Dart row | `flutter --version` |
| Flutter test integration | Flutter application with `flutter_test` and `zuke_runner_flutter` | `flutter pub get` |
| CLI, parser, generation, analyzer, and build-hook packages | Same Dart range as the application | `dart run zuke_cli:zuke doctor` |

The repository intentionally does not declare a separate Flutter lower bound:
Flutter supplies the Dart runtime that resolves these packages. Pin a Flutter
SDK in CI or your version manager, then verify that its bundled Dart version is
within the supported range above.

If you started with `flutter create`, update or delete its default
`test/widget_test.dart` when replacing the generated `MyApp`. Leaving that test
in place makes `flutter analyze` fail before Zuke runs.

### Support tiers

| Tier | Packages | Contract |
| --- | --- | --- |
| Primary SDK | `zuke` | Pure-Dart parser, execution, runtime event, and HTTP scenario-test SDK. |
| Specialized SDK | `zuke_runner_flutter`, `zuke_http_runtime`, `zuke_dart_build_hook`, `zuke_cli` | Platform, runtime, build, and workflow extensions. |
| Narrow SDK | `zuke_annotations`, `zuke_frontend` | Directly supported for strict production/test separation and custom integrations. |
| Compatibility | `zuke_runner` | Existing imports forward to `zuke`; new Dart execution code should use `zuke`. |
| Shared infrastructure | `zuke_core` | Published Zuke infrastructure dependency; applications normally depend on a primary SDK package instead. |
| Workspace tooling | `zuke_analyzer`, `zuke_conformance`, `zuke_verifier`, `zuke_test_support` | Repository-only tooling; not published to pub.dev. |

Each package README carries its tier-specific support contract. The release
surface checks in `vendor-sdk/check_docs.dart` are the authoritative package
inventory and support boundary.

---

## 2. Directory structure & configuration (`zuke.yaml`)

Zuke expects a structured workspace layout. The standard project layout is:

```text
.
|-- .zuke/                    # Local extraction cache (not committed)
|-- assurance-history/              # Optional advanced release-history data
|-- generated/
|   `-- evidence/records/           # Scenario evidence output
|-- lib/
|   |-- main.dart
|   `-- src/
|       |-- bindings.dart
|       |-- controllers.dart
|       `-- generated/              # Contract generation output
|-- policies/
|-- specs/
|   |-- controls/
|   |-- epics/
|   |-- features/
|   `-- registry/
|-- test/
|   |-- support/
|   `-- widget_test.dart
|-- pubspec.yaml
`-- zuke.yaml
```
Create `zuke.yaml` at the root of your project:

```yaml
schemaVersion: 3

workspace:
  name: my-app-product
  root: .

specifications:
  features: [specs/features/**/*.feature]
  epics: [specs/epics/**/*.yaml]
  controls: [specs/controls/**/*.yaml]
  registries: [specs/registry/**/*.yaml]

targets:
  flutter:
    language: dart
    framework: flutter
    packages:
      - id: my-app
        path: .
        roots: [lib, test]
    contractOutput: lib/src/generated
    extractor: zuke-dart-resolved

dartTooling:
  extraction:
    authority: cli
    cache: .zuke/cache/dart
    requireResolvedAnnotations: true
    rejectIncompleteFragments: true
  analyzerPlugin:
    enabled: true
  buildHooks:
    default: disabled
    enabledPackages: [.]
  generation:
    driver: zuke-cli
    commitGeneratedSource: true
    watchCommand: dart run zuke_cli:zuke watch --generate --validate

policies:
  preset: secure-product-v1
  project: policies/project-policy.yaml
  profiles: [policies/security-profiles.yaml]
  protectedSeverities:
    duplicateId: error
    ambiguousBinding: error
    missingSecurityEvidence: error
    staleLock: error

execution:
  runners:
    - id: my-app-flutter-tests
      kind: gherkin
      target: flutter
      sourcePackage: my-app
      evidenceTypes: [gherkin-ui]
      executable: flutter
      args: [test, --no-pub, --reporter, expanded]
      # auto (default), cli, or directSnapshot
      runnerMode: auto
      workingDirectory: .
      timeoutSeconds: 300
  pullRequest:
    tagExpression: '@pr'
  merge:
    tagExpression: '@pr or @merge'
  release:
    tagExpression: '@pr or @release'

evidence:
  output: generated/evidence/records
  records: generated/evidence/records
  observations: generated/evidence/runs
  includeSourceCode: false

trust:
  bundle: assurance-history/trust/ed25519-v2.json
  algorithm: ed25519

lock:
  directory: assurance/locks
  profiles: [pullRequest, merge, release, nightly]
  requireCleanGeneration: true
```

On Windows, a configured `flutter` runner bypasses the batch launcher and
executes the cached Flutter tool snapshot with the SDK's Dart executable. This
shell-free path requires a prepared and writable SDK cache: run the official
`flutter doctor`, `flutter precache`, or `flutter pub get` command after
installing or upgrading Flutter, and ensure the account running Zuke can
open the SDK cache lock and snapshot files. Linux and macOS continue to use the
official Flutter launcher. Zuke inherits `CI` when the caller sets it but
never creates it, suppresses Flutter analytics for the child process, and stops
a Windows Flutter runner that produces no stdout or stderr within 90 seconds.
`FLUTTER_TOOL_ARGS` is not supported by the Windows shell-free runner; put
supported runner options in the configured `args` list instead.

If the runner reports `ZUKE-FLUTTER-CACHE-UNWRITABLE`, its process cannot open
`<FLUTTER_ROOT>/bin/cache/lockfile` for writing. In an agent sandbox, grant
that SDK cache write access or point `FLUTTER_ROOT` at a separately prepared
writable SDK. Deleting the lockfile and setting `FLUTTER_ALREADY_LOCKED` do
not bypass Flutter's cache-open requirement.

This diagnostic reports effective process access, not just the Windows ACL.
For example, a sandbox can deny writes to `C:\\flutter` even when its NTFS
permissions grant the account `Modify`. Run the integration suite in a host
process with access to the SDK, or install a complete SDK in a user-writable
location and select it explicitly:

```powershell
$env:FLUTTER_ROOT = "$env:USERPROFILE\\develop\\flutter"
flutter doctor
flutter precache
flutter pub get
$env:ZUKE_RUN_PROCESS_INTEGRATION = 'true'
dart test
```

`PUB_CACHE` only relocates Dart package downloads; it does not relocate
Flutter's SDK lock. A partial workspace copy or junction overlay is not a
supported SDK because Flutter's private cache bootstrap may require additional
stamps and artifacts. Use a fully prepared SDK instead. The repository's
diagnostic is intentionally fail-closed so a denied cache write cannot turn
into a silent Flutter startup hang.

The same setting may be placed on a target-level `runner`. The command-line
override `--runner-mode=<auto|cli|directSnapshot>` is accepted by `test`,
`gate`, and `check` and takes precedence over YAML. `auto` selects the
shell-free cached snapshot only for Windows Flutter runners; POSIX defaults to
the official launcher. `directSnapshot` is available on any platform, but it
is an internal entry point that requires a prepared, compatible, writable SDK
and still uses Flutter's startup lock. It is shell-free and more diagnosable,
not lock-free or guaranteed to be faster. `cli` explicitly restores the
official launcher (including its Windows batch/shell argument and process-tree
risks).

Do not point concurrent Flutter runners at the same SDK cache when using
`--jobs > 1`: Flutter serializes those processes through the shared
`bin/cache/lockfile`. For genuine parallel Flutter execution, provision one
prepared SDK/cache root per concurrent process (or serialize runners that share
one root). Each isolated root must have its own writable cache lockfile and
compatible snapshot/package configuration; read-only artifact directories may
be shared only when the SDK contract permits it.

Generic `.bat` and `.cmd` runners continue to use `cmd.exe`. Arguments with
Windows shell metacharacters such as `&`, `|`, `<`, `>`, `^`, `%`, `!`, quotes,
or newlines are rejected with `ZUKE-BATCH-UNSAFE-ARGUMENT`; use a native
executable or a shell-free runner when those values are required.

---

## 3. Specification ecosystem and policy files

Zuke validation requires an interconnected graph of Epics, PBIs, Controls, Features, and Policies.

### A. Feature File (`specs/features/shopping_cart.feature`)
Every `.feature` file **must** begin with a `# spec-begin` header declaring its metadata and binding dependencies. Every `Rule` must have a `# rule-spec-begin` header.

```gherkin
# spec-begin
# schemaVersion: 1
# id: FEAT-CART-001
# epic: EPIC-SHOPPING-001
# owner: shopping-team
# status: active
# targets:
#   - flutter
# pbis:
#   - PBI-CART-001
# bindings:
#   required:
#     - id: shopping.promoInput
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: shopping.applyPromoButton
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: shopping.discountStatusDisplay
#       target: flutter
#       cardinality: zeroOrOne
#       interaction: output
# spec-end

@EPIC-SHOPPING-001 @FEAT-CART-001
Feature: E-Commerce Shopping Cart & Checkout

  # rule-spec-begin
  # id: RULE-CART-PROMO-DISCOUNT
  # requiredEvidence: [gherkin-ui]
  # securityProfile: promo-validation-profile
  # rule-spec-end
  @RULE-CART-PROMO-DISCOUNT
  Rule: RULE-CART-PROMO-DISCOUNT Promo Code Application and Validation

    @SCN-CART-APPLY-PROMO @pr @merge
    Scenario: Apply valid discount code and recalculate grand total
      Given the shopping application is open
      When the user enters "SAVE20" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      Then element "shopping.discountStatusDisplay" displays "Discount Applied: 20%"
```

### B. Epic Definition (`specs/epics/EPIC-SHOPPING-001.yaml`)
```yaml
schemaVersion: 1
id: EPIC-SHOPPING-001
title: E-Commerce Shopping Cart & Checkout Experience
owner: shopping-team
strategicGoal: Provide an advanced frontend shopping cart experience.
businessContext: Demonstrates BDD testing with state controllers and promo codes.
successMetrics:
  - id: KPI-SHOP-COVERAGE
    target: 100
    unit: percent
scope:
  in: [promo code validation]
  out: [payment processing]
```

### C. Controls Definition (`specs/controls/shopping-controls.yaml`)
```yaml
schemaVersion: 1
controls:
  - id: CTRL-PROMO-VALIDATION
    title: Promo Code & Discount Eligibility Validation
    description: Validates discount codes before applying to order subtotal.
    acceptableProviderKinds: [application-validator]
    coverageSemantics: verification-backed
    requiredLayers: [presentation]
```

### D. PBI Registry (`specs/registry/pbis.yaml`)
```yaml
version: zuke.pbi.v1
pbis:
  - id: PBI-CART-001
    title: Shopping Cart UI & Discounts
    epic: EPIC-SHOPPING-001
```

### E. Policies (`policies/project-policy.yaml` & `policies/security-profiles.yaml`)
`policies/project-policy.yaml`:
```yaml
schemaVersion: 1
id: shopping-cart-project-policy
description: Project policy overlay.
scenarioCoverage:
  securityRulesRequireNegativeScenario: false
  accessibilityRulesRequireFlutterEvidence: false
documentationOnly:
  requireReason: true
```

`policies/security-profiles.yaml`:
```yaml
schemaVersion: 1
securityProfiles:
  promo-validation-profile:
    requires:
      - kind: control
        id: CTRL-PROMO-VALIDATION
        target: flutter
        cardinality: oneOrMore
    requiredEvidence: [gherkin-ui]
```

---

## 4. Generate contracts before application code

After specifications and `zuke.yaml` are in place, run generation before
creating bindings, drivers, widgets, or tests that import a generated contract:

```sh
flutter pub get
dart run zuke_cli:zuke doctor
dart run zuke_cli:zuke generate
```

Do not create a placeholder `*_contracts.g.dart` file. Generation owns these
files and intentionally refuses to overwrite handwritten output. Contract class
names derive from stable feature and rule IDs, and every declared binding adds a
binding getter and an interaction-specific driver method, even when no current
Gherkin step uses it.

### Binding cardinality

`cardinality` counts annotated code providers for a logical binding; it does
not describe how many widgets appear at runtime. Use `exactlyOne`,
`zeroOrOne`, `oneOrMore`, or `many`. `zeroOrMore` is accepted as an alias for
`many`.

Use `instanceCardinality` for runtime multiplicity. It has the same values and
defaults to `exactlyOne`. A repeated Flutter binding uses
`instanceCardinality: zeroOrMore` plus a `FlutterBindingKey.collection`; every
row mounts `binding.instance(stableItemId)`. The runner can safely read a
collection assertion across all rows while interactions still require one
explicit row. Flutter only requires local-key uniqueness among siblings, but
typed instance keys remain stable and safe when layouts are refactored.

`FlutterBindingKey` and `FlutterBindingInstanceKey` are exported by the
application-facing `zuke_runner_flutter` package. Keep that Flutter runtime
dependency in application code; generated contracts stay Flutter-free and use
only the `ZukeBindingDescriptor` metadata from `zuke_annotations`.

---

## 5. Layout, annotations, and generated contracts

Application code uses `zuke_annotations` to map Flutter UI keys and controllers to specifications:

1. **`@ZukeBinding`**: Annotates `Key` properties. Pass only the binding ID string as a positional argument.
2. **`@ImplementsRequirement` & `@ProvidesControl`**: Placed on controllers/validators to bind business logic to rules and controls.
3. **`@PresentsRequirement`**: Placed on UI widgets.

Example (`lib/src/shopping_bindings.dart` & `lib/src/cart_controller.dart`):

```dart snippet=bindings
import 'package:flutter/foundation.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'generated/feat_cart_001_contracts.g.dart';

class ShoppingBindings implements FeatCart001FlutterBindings<Key> {
  @override
  @ZukeBinding('shopping.addToCartHeadphones')
  Key get addToCartHeadphones => const Key('shopping.addToCartHeadphones');

  @override
  @ZukeBinding('shopping.promoInput')
  Key get promoInput => const Key('shopping.promoInput');

  @override
  @ZukeBinding('shopping.applyPromoButton')
  Key get applyPromoButton => const Key('shopping.applyPromoButton');

  @override
  @ZukeBinding('shopping.checkoutButton')
  Key get checkoutButton => const Key('shopping.checkoutButton');

  @override
  @ZukeBinding('shopping.cartBadge')
  Key get cartBadge => const Key('shopping.cartBadge');

  @override
  @ZukeBinding('shopping.subtotalDisplay')
  Key get subtotalDisplay => const Key('shopping.subtotalDisplay');

  @override
  @ZukeBinding('shopping.discountStatusDisplay')
  Key get discountStatusDisplay => const Key('shopping.discountStatusDisplay');

  @override
  @ZukeBinding('shopping.totalDisplay')
  Key get totalDisplay => const Key('shopping.totalDisplay');

  @override
  @ZukeBinding('shopping.statusMessageDisplay')
  Key get statusMessageDisplay => const Key('shopping.statusMessageDisplay');

  @override
  @ZukeBinding('shopping.catalogItemName')
  Key get catalogItemName => const Key('shopping.catalogItemName');

  @override
  @ZukeBinding('shopping.catalogItemPrice')
  Key get catalogItemPrice => const Key('shopping.catalogItemPrice');
}
```

The same annotations bind the controller implementation and its control
provider declaration:

```dart snippet=controller
import 'package:flutter/foundation.dart';
import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement([
  FeatCart001RequirementIds.promoDiscount,
], target: 'flutter')
@ProvidesControl(
  ['CTRL-PROMO-VALIDATION'],
  kind: ControlProviderKind.applicationValidator,
  layer: EnforcementLayer.presentation,
  target: 'flutter',
)
class CartController extends ChangeNotifier {}
```

The generic key interface keeps generated packages Flutter-free while allowing
Flutter UI code to receive `FeatCart001FlutterBindings<Key>` and pass getters
directly to `key:` without casts. The generated
`FeatCart001FlutterBinding` sealed hierarchy separately turns logical Gherkin
IDs into exhaustive finder-mapping obligations in the test harness.

---

## 6. Regeneration and generated artifacts

Run `zuke generate` to produce contract interfaces in `lib/src/generated/` and update `.zuke/analyzer-index.json`:

```sh
dart run zuke_cli:zuke generate
```

Generation is transactional. It refuses to delete a stale file unless it has
the generated-file marker, confines output to `contractOutput`, formats Dart
before hashing it, and creates the sealed binding hierarchy, typed contract
interfaces (`FeatCart001FlutterBindings`, `FeatCart001FlutterDriver`), and
`.zuke/analyzer-index.json`.

---

## 7. Test runner setup & reusable step vocabulary

Widget tests execute scenarios using `ScenarioExecutor<W>` and register vendor or project step vocabulary.

### World Setup
The world class **must** extend `ScenarioWorld`:

```dart snippet=world
class ShoppingCartWorld extends ScenarioWorld {
  final WidgetTester tester;
  final CartController controller;
  final ShoppingBindings bindings;

  ShoppingCartWorld({
    required this.tester,
    required this.controller,
    required this.bindings,
  });
}
```

### Reusable Step Vocabulary (`flutterVendorSteps`)
Register reusable Flutter vendor steps by decoding logical binding IDs into the
generated sealed hierarchy and resolving its generated binding key:

```dart snippet=vendor-steps
for (final step
    in flutterVendorSteps<ShoppingCartWorld, FeatCart001FlutterBinding>(
      testerFor: (world) => world.tester,
      bindingFromId: FeatCart001FlutterBinding.fromId,
      keyFor: (world, binding) => binding.keyIn(world.bindings),
    )) {
  registry.register(step);
}
```

*Note: `flutterVendorSteps` already provides steps for tapping bindings (e.g. `the user taps "shopping.applyPromoButton"`) and entering text (`the user enters "..." into "shopping.promoInput"`). Do not register duplicate custom project steps for these patterns.*
The generated `keyIn` method is exhaustive: regenerating after a new binding is
declared requires its generated subtype to supply the matching binding member.

### Scenario Execution & Evidence Reporting
Use `ScenarioExecutor` and `ExecutionResultWriter` to record test evidence for zuke:

```dart snippet=executor
final executor = ScenarioExecutor<ShoppingCartWorld>(
  registry: registry(),
  evidenceType: 'gherkin-ui',
  target: 'flutter',
  profile: profile,
  candidateId: contract.id,
  controlIds: contract.controlIds,
  runnerId: 'my-app-flutter-tests',
  runnerCompatibilityId: 'my-app-flutter-tests-v1',
  digests: const {'runner': 'zuke-runner-flutter-v1'},
);
final result = await executor.executeScenario(
  feature,
  rule,
  scenario,
  () => world,
);
expect(result.status, ScenarioStatus.passed);

const writer = ExecutionResultWriter();
writer.writeScenarioToEnvironment(result);
```

### Profile and tag selection

`execution.<profile>.tagExpression` selects scenarios using Gherkin tags. The
expression supports tag names (for example `@release`), `not`, `and`, `or`,
and parentheses. Tags inherited from the Feature, Rule, Scenario, and an
`Examples` block participate in selection.

`zuke test --profile <profile>` passes the selected scenario IDs to the
test process in `ZUKE_SCENARIO_FILTER`, and passes the profile in
`ZUKE_PROFILE`. It also supplies `ZUKE_SELECTION_DIGEST` for the
evidence record. The widget-test harness must consume the filter; otherwise the
underlying `flutter test` command will run every registered scenario.

On success, text output ends with the selected scenario IDs, published evidence
record count, evidence directory, and observation path. This confirms that the
runner results were collected; `validate` remains the authoritative policy
check for those records.

```dart snippet=profile-filter
final selectedScenarioIds = scenarioFilterFromEnvironment(
  Platform.environment,
);

testWidgets(
  '$scenarioId: $name',
  (tester) => runScenario(tester, scenarioId),
  skip: !shouldRunScenario(scenarioId, selectedScenarioIds),
);
```

Use an empty filter as "run all" so that a direct `flutter test` remains useful
locally. `zuke_runner_flutter` exports these helpers and
`ZukeFlutterHarness` applies the same filter automatically.

### End-to-end profile-specific `Examples` selection

Give each independently selectable outline a stable `@SCN-*` tag, then tag its
`Examples` block with the profile that should select it. For example:

```gherkin
# rule-spec-begin
# id: RULE-CHECKOUT-PROFILES
# rule-spec-end
Rule: Checkout profile validation
  @SCN-CHECKOUT-PR
  Scenario Outline: validate checkout in pull requests
    Given the cart contains <quantity> item
    Then checkout is <state>

    @pr
    Examples: fast validation cases
      | quantity | state   |
      | 0        | blocked |
      | 1        | allowed |

  @SCN-CHECKOUT-RELEASE
  Scenario Outline: validate checkout for release
    Given the cart contains <quantity> item
    Then checkout is <state>

    @release
    Examples: release boundary cases
      | quantity | state   |
      | 0        | blocked |
      | 99       | allowed |
```

Configure the matching profile expressions:

```yaml
execution:
  pullRequest:
    tagExpression: '@pr'
  release:
    tagExpression: '@release'
```

Register generated descriptors in the widget-test harness using the filtered
`testWidgets` pattern above:

```dart snippet=registration
void registerScenarios(Object pattern) {
  for (final resolved in resolveScenarioContracts(
    feature,
    FeatCart001Scenarios.all,
    ZukeScenarioPattern.from(pattern),
  )) {
    registerScenario(resolved.contract);
  }
}

// zuke: allow-raw-id -- the guide demonstrates a scoped prefix.
registerScenarios(ZukeScenarioPattern.prefix('SCN-CART-'));
```

#### Choosing a selection expression

Use the enum directly for one scenario: `registerScenario(FeatCart001Scenario.successCheckout)`.
Use a prefix or regular expression for a deliberate family, such as
`registerScenarios(ZukeScenarioPattern.prefix('SCN-CART-PROMO-'))`; this keeps
selection readable while resolving every match against Gherkin before a widget
test is registered. Use `ZukeScenarioPattern.ruleId(FeatCart001RequirementIds.promoDiscount)`
when the rule is the meaningful boundary, and `FeatCart001Scenarios.all` only
when the harness intentionally owns every scenario in the feature. Glob input
is anchored (`SCN-CART-?DD-*`), while `RegExp` retains Dart's normal matching
semantics. An empty match is an error, never a silently empty test suite.

These commands then select the corresponding scenario IDs and expose them to
the test process:

```sh
dart run zuke_cli:zuke test --profile pullRequest
dart run zuke_cli:zuke test --profile release
```

Selection is scenario-level, not row-level: if one outline has multiple
`Examples` blocks and any block matches the profile expression, its `@SCN-*`
scenario is selected and every row in every Examples block executes. Use
separate outlines (as above) when profile-specific example data must execute
independently.

---

## 8. Normal lifecycle & CLI commands

Once your specifications, configuration, application annotations, and test runner are in place, follow the standard lifecycle:

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
dart run zuke_cli:zuke doctor
dart run zuke_cli:zuke generate
dart run zuke_cli:zuke generate --check
dart run zuke_cli:zuke test --profile pullRequest
dart run zuke_cli:zuke validate --profile pullRequest
dart run zuke_cli:zuke lock --profile pullRequest
dart run zuke_cli:zuke lock --profile pullRequest --check
dart run zuke_cli:zuke gate --profile pullRequest
# For one or more workspaces, run isolated stages and emit one JSON envelope.
dart run zuke_cli:zuke check --root examples/calculator-product --root examples/shopping_cart --profile pullRequest --jobs 2
```

### Lifecycle Overview
- **`doctor`**: Verifies `zuke.yaml`, feature files, and specification setup.
- **`generate`**: Writes typed contracts and `.zuke/analyzer-index.json`. Use `generate --check` in CI to ensure generated output is up to date.
- **`test`**: Sets `ZUKE_SCENARIO_FILTER`, runs configured test runners, and prints the evidence-record count plus output and observation paths after publication.
- **`validate`**: Validates requirement graphs, binding cardinality, and security evidence policies.
- **`lock`**: Updates the selected `assurance/locks/<profile>.lock.json`
  proof record (`lock --profile <name> --check` verifies no drift; use
  `--all-profiles` for the official four-profile set).
- **`gate`**: Combines validation, clean generation checks, test execution if evidence is missing, lock checking, and release trust checks into a single command.
- **`check`**: Runs generation, configured runners, validation, lock synchronization, and an observational report for each supplied root. Roots can run concurrently; `--format json` emits exactly one `zuke.check.v1` document.

### Pull-request CI example

This GitHub Actions job runs the Flutter analysis first, then delegates the
profile-filtered test, generation, validation, and lock checks to `gate`.
Set the Flutter version to one whose bundled Dart is supported by the
compatibility matrix above.

```yaml
name: Zuke pull-request gate

on:
  pull_request:

jobs:
  zuke:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: examples/shopping_cart
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze --no-pub
      - run: dart run zuke_cli:zuke gate --profile pullRequest
```

Do not add a separate unfiltered `flutter test` step to this job: `gate`
invokes the configured runner through `zuke test`, which supplies the
selection and evidence environment variables.

---

## 9. Analyzer feedback and optional build hook

### Analyzer Plugin
Enable fast developer feedback in `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - zuke_analyzer
```

And add `zuke_analyzer` to `dev_dependencies`:

```yaml
dev_dependencies:
  zuke_analyzer: {path: ../../vendor-sdk/dart_analyzer_plugin}
```

### Dart Build Hook
To enroll a package into diagnostic build hooks:

```sh
dart run zuke_cli:zuke adopt package . --root . --enable-build-hook --dry-run
dart run zuke_cli:zuke adopt package . --root . --enable-build-hook
```

Adoption creates `hook/build.dart`, adds `zuke_dart_build_hook` to `pubspec.yaml`, and scaffolds the `hooks.user_defines` block:

```yaml
hooks:
  user_defines:
    zuke_dart_build_hook:
      mode: warn # onboarding default; choose 'error' once generation is enforced
      workspaceRoot: ../ # Optional explicit workspace root path
```

#### Hooks 2.x Architecture & Capability Assessment
- **`user_defines` Configuration**: The hook receives its package-filtered `mode` and `workspaceRoot` values from `hooks.user_defines.zuke_dart_build_hook`. New adoptions use `warn`; change to `error` once the package's generated index is enforced. This avoids shell environment variables while retaining semi-hermetic build compliance.
- **Link Hooks (`recordedUses` in Dart 3.13)**: Evaluated for symbol auditing; not adopted because Zuke governs specification metadata rather than code-asset linkage.
- **DataAssets for Zuke Models**: Shipping compiled `zuke-model.json` as a native `DataAsset` is deferred until the SDK runtime directly consumes non-code asset bundles.
- **Multi-Package Layouts**: In multi-package workspaces (like `calculator-product`), package build hooks report local dependency declarations while deferring workspace-wide lock and release gates to `zuke gate`.

---

## 10. Trust, signing, and independent release verification

For release profiles, configure trust settings in `zuke.yaml`:

```yaml
trust:
  bundle: assurance-history/trust/ed25519-v2.json
  algorithm: ed25519
```

Release gates require an active key with `release` usage, a clean tracked git workspace, and external signing environment variables (`ZUKE_SIGNING_PROVIDER_URL` and `ZUKE_SIGNING_PROVIDER_BEARER_TOKEN`).

The protected release workflows obtain the short-lived bearer token through
GitHub OIDC and the configured Azure workload identity. Store the Azure client
and tenant identifiers, signing-provider URL and audience, and release key
references in the protected GitHub environment; never commit private keys or
bearer tokens. The workflow authenticates to Azure, requests the short-lived
signing credential, and passes it to Zuke only for the signing operation.

Create and verify history:

```sh
dart run zuke_cli:zuke manifest create \
  --root . --profile release --signer-id <signer> --key-id <key>
dart run zuke_cli:zuke manifest verify-v2 \
  --root . --current --require-history
dart run zuke_cli:zuke manifest export \
  --root . --output dist/assurance-history.v2.json
```

Verify exported history independently:

```sh
dart run zuke_verifier:verify \
  dist/assurance-history.v2.json \
  assurance-history/trust/ed25519-v2.json
```

---

## 11. Troubleshooting and common issues

Below is a reference of common issues encountered during integration and how to resolve them:

### 1. `ERROR: specs/features/ directory not found`
- **Cause**: `zuke doctor` expects feature files specifically inside `specs/features/`.
- **Solution**: Ensure your Gherkin `.feature` files are stored in `specs/features/` and configured in `zuke.yaml` (`specifications.features: [specs/features/**/*.feature]`).

### 2. Contracts are generated in `packages/calculator_contracts/` instead of `lib/src/generated/`
- **Cause**: Missing or incomplete `zuke.yaml` configuration.
- **Solution**: Add the `targets.flutter.contractOutput: lib/src/generated` key to `zuke.yaml`.

### 3. `The named parameter 'interaction' isn't defined` during `@ZukeBinding` compilation
- **Cause**: Passing `interaction: input` as a named argument to `@ZukeBinding`.
- **Solution**: Pass only the binding ID string as a single positional argument: `@ZukeBinding('shopping.promoInput')`. The interaction type (`input`, `action`, `output`) is declared inside the `.feature` file header metadata, not on the Dart annotation.

### 4. `FormatException: feature metadata requires exactly one # spec-begin/# spec-end block`
- **Cause**: The `.feature` file lacks mandatory Zuke metadata comments.
- **Solution**: Wrap feature metadata at the top of every `.feature` file between `# spec-begin` and `# spec-end` comments, and rule metadata between `# rule-spec-begin` and `# rule-spec-end`.

### 5. `'MyWorld' doesn't conform to the bound 'ScenarioWorld'` compiler error
- **Cause**: Custom `MyWorld` class does not extend `ScenarioWorld`.
- **Solution**: Inherit from `ScenarioWorld`:
  ```dart
  import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

  class MyWorld extends ScenarioWorld { ... }
  ```

### 6. `Package path escapes the workspace` during `zuke adopt`
- **Cause**: Running `zuke adopt package` with unmatched `--root` or relative package arguments inside a standalone project directory.
- **Solution**: Run `dart run zuke_cli:zuke adopt package . --root . --enable-build-hook` from the package root directory.

### 7. Missing Epics, Controls, or PBIs during `validate` or `test`
- **Cause**: Zuke graph validation requires linked Epics, Controls, and PBIs for every feature and rule.
- **Solution**: Ensure corresponding `.yaml` definitions exist in `specs/epics/`, `specs/controls/`, and `specs/registry/pbis.yaml`, and that policies exist in `policies/project-policy.yaml` and `policies/security-profiles.yaml`.

### 8. `zuke test` or `validate` fails with missing evidence / evidence not recorded
- **Cause**: Test execution did not emit scenario results to the environment.
- **Solution**: Ensure your test runner invokes `ExecutionResultWriter().writeScenarioToEnvironment(result)` after executing each scenario via `ScenarioExecutor`.

### 9. `Multiple project step definitions at priority 100 match...`
- **Cause**: Two matching definitions in the same tier have the same highest priority. Resolution chooses tiers in this order: generated, project, vendor, extension; a project step may intentionally refine a vendor step, but cannot override a generated step.
- **Solution**: Remove or narrow one same-tier pattern, or assign distinct priorities. Use logical binding IDs in feature steps (for example `When the user taps "shopping.applyPromoButton"`) when `flutterVendorSteps` already provides the vocabulary.

### 10. `Error: Release creation requires a clean tracked repository` on `manifest create`
- **Cause**: Uncommitted changes or untracked files present during release manifest creation.
- **Solution**: Commit all changes to Git before running `manifest create`, and ensure `ZUKE_SIGNING_PROVIDER_URL` and `ZUKE_SIGNING_PROVIDER_BEARER_TOKEN` are set.
