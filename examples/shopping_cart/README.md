# Shopping Cart Zuke Reference 🟡 (Intermediate)

This is an intermediate Flutter reference application demonstrating state management (`CartController`), promo codes, accessibility constraints, evidence locking, and full CI gate profile validation with Zuke.

---

## Quick Start: How to Run

From this directory (`examples/shopping_cart`):

```bash
# 1. Fetch dependencies & analyze
flutter pub get
flutter analyze --no-pub

# 2. Run standard Flutter tests
flutter test --no-pub

# 3. Generate Zuke contracts, then verify freshness
dart run zuke_cli:zuke generate
dart run zuke_cli:zuke generate --check

# 4. Run test execution with Zuke evidence capture
dart run zuke_cli:zuke test --profile pullRequest

# 5. Validate evidence records against policies
dart run zuke_cli:zuke validate --profile pullRequest

# 6. Write the derived lock, then run the read-only gate
dart run zuke_cli:zuke lock --profile pullRequest
dart run zuke_cli:zuke gate --profile pullRequest
```

From the repository root, run the full shopping cart release gate check:
```bash
dart run melos run zuke:shopping:gate
```

## Generated Traceability

The rule, scenario, and evidence relationships are generated from the
specification model instead of duplicated in this README:

```bash
dart run zuke_cli:zuke report
dart run zuke_cli:zuke trace RULE-CART-PROMO-DISCOUNT
```

`generated/report/zuke-model.json` is an ignored, observational CI artifact;
the `trace` command renders the selected rule's scenarios, implementation
links, controls, and observed evidence.

---

## How to Add a New Scenario or Step

To extend this application with new BDD specifications:

1. **Edit Feature Specification**: Update `specs/features/shopping_cart.feature` with your new scenario.
2. **Re-generate Contracts**: Run `dart run zuke_cli:zuke generate`. The codegen updates `lib/src/generated/feat_cart_001_contracts.g.dart` with new key bindings and contract drivers (`FeatCart001FlutterDriver`).
3. **Implement Flutter Driver**: Update `test/support/shopping_cart_flutter_driver.dart` to implement any new driver methods.
4. **Register Steps**: In `test/shopping_cart_widget_test.dart`, register any custom step definitions with `StepRegistry`.
5. **Update Evidence & Lockfile**: Run `zuke test`, `validate`, and
   `lock --profile pullRequest` in that order. Finish with
   `gate --profile pullRequest`, which checks current generation, evidence, and
   lock state without regenerating contracts or rewriting the lock.

---

## Tags in this Example

The feature uses `@FEAT-*`, `@RULE-*`, and `@SCN-*` tags as required stable identities:
- `@SCN-*`: Identifies scenario results captured by Zuke as evidence.
- `@security`, `@negative`, `@accessibility`: Activate specific policy checks.
- `@pr` and `@release`: Track target CI/CD execution profiles.

---

## Architecture Mapping

| Capability | Example Files | SDK Package | Evidence / CI Enforcement |
| :--- | :--- | :--- | :--- |
| Gherkin rules & PBI traceability | `specs/features/`, `specs/registry/` | `zuke_frontend` | `generate --check` |
| Typed bindings & interaction driver | `lib/src/shopping_bindings.dart`, `test/support/` | `zuke_cli`, `zuke_runner_flutter` | `flutter test` |
| `@ZukeBinding` key wiring | `lib/src/shopping_bindings.dart` | `zuke_annotations` | `flutter analyze/test` |
| Validation & semantics providers | `lib/src/cart_controller.dart`, `lib/src/shopping_screen.dart` | `zuke_annotations`, `zuke_cli` | `validate`, `gate` |
| Verification-backed assurance | `specs/controls/`, `policies/` | `zuke_core` | provider + digest-backed `verified` lock proof |
| Scenario execution & SHA-256 results | `test/shopping_cart_widget_test.dart` | `zuke`, through `zuke_runner_flutter` | `zuke test`, `validate` |
| Signed release record | `assurance-history/` | `zuke_cli` | `manifest verify-v2 --require-history` |
