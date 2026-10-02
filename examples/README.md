# Zuke Examples Index

Welcome! This directory contains example projects illustrating BDD (Behavior-Driven Development), Gherkin specifications, and Zuke compliance attestation with Flutter and Dart applications.

---

## Recommended Learning Path

| Step | Example Project | Level | Focus |
| :--- | :--- | :--- | :--- |
| **1** | [**`library_catalog`**](library_catalog) | 🟢 **Beginner · Pure Dart** | Specs-first flow: write `specs/`, `zuke generate`, implement against typed contracts, catch bad IDs/stale indexes with the analyzer plugin. Runs Gherkin on a non-Flutter `StepRegistry` + `ScenarioExecutor`, plus a loopback TCP peer demo and CLI desk TUI. Smallest Zuke surface (1 control, 3 rules). |
| **2** | [**`todo_app`**](todo_app) | 🟢 **Beginner · Flutter** | Canonical Flutter starter: `@ZukeBinding` widget keys, `ChangeNotifier` controller, `ZukeFlutterHarness` batteries-included Gherkin, generated contracts. Signing/build-hooks intentionally off. |
| **3** | [**`shopping_cart`**](shopping_cart) | 🟡 **Intermediate · Flutter** | Heavier single-package app: promo-code state machine, `Semantics` accessibility rule, 3 security profiles/controls, scenario-filter + guide-snippet tests, larger profile locks. |
| **4** | [**`calculator-product`**](calculator-product) | 🔴 **Advanced · Multi-package** | Workspace of 4 packages and 2 targets (HTTP API + Flutter UI): rate-limit/body-limit/redaction controls, dual extractors, 9 evidence types, performance/nightly tags, dedicated assurance CI. |

**How to read the levels:** difficulty is scoped to learning the Zuke
spec → generate → verify → gate loop. All four examples ship the same
4-profile locks and CI gate path; later steps add product surface
(controls, packages, harnesses), not a different workflow.

---

## Quick Start (Running Any Example)

To run any example project locally:

1. **Bootstrap dependencies** from the repository root:
   ```bash
   dart run --suppress-analytics melos bootstrap
   ```

2. **Navigate to the example directory**:
   ```bash
   cd examples/library_catalog
   # or cd examples/todo_app
   # or cd examples/shopping_cart
   # or cd examples/calculator-product
   ```

3. **Generate Zuke contracts and run tests**:
   ```bash
   # Pure Dart examples:
   dart run zuke_cli:zuke generate
   dart test
   # Flutter examples:
   flutter pub get
   dart run zuke_cli:zuke generate
   flutter test --no-pub
   ```

4. **Execute complete BDD evidence validation**:
   ```bash
   dart run zuke_cli:zuke gate --profile pullRequest
   ```

---

## Architecture Overview

All examples follow standard Zuke BDD principles:

1. **Gherkin Specifications (`specs/features/*.feature`)**: Define business behavior, acceptance criteria, and PBIs using strongly typed `# spec-begin` tags.
2. **Contract Generation (`zuke generate`)**: Automatically compiles feature requirements into typed Dart contracts in `lib/src/generated/`.
3. **Widget & Logic Annotations (`@ZukeBinding`, `@ProvidesControl`)**: Wire Flutter UI elements and state controllers to generated specification keys.
4. **Step Definitions & Adapters (`test/`)**: Map scenario steps to widget drivers and unit tests; advanced examples keep these drivers in test support rather than a separate package.
5. **Evidence Locking & Gating (`zuke gate`)**: Collects execution logs, SHA-256 digests, and policy assertions to ensure release compliance.

---

## Next Steps

- Start with step 1: the [**Library Catalog Example**](library_catalog/README.md) (pure Dart), then the [**Todo App**](todo_app/README.md) for Flutter.
- Read the comprehensive [**Integration & Implementation Guide**](../docs/integration-guide.md) for full architecture details.
