# Zuke Examples Index

Welcome! This directory contains example projects illustrating BDD (Behavior-Driven Development), Gherkin specifications, and Zuke compliance attestation with Flutter and Dart applications.

---

## Recommended Learning Path

| Step | Example Project | Complexity | Key Learning Objectives |
| :--- | :--- | :--- | :--- |
| **1** | [**`todo_app`**](todo_app) | 🟢 **Beginner** | Basic Flutter BDD workflow, widget bindings (`@ZukeBinding`), dynamic list items, scenario execution, generated contracts. |
| **2** | [**`shopping_cart`**](shopping_cart) | 🟡 **Intermediate** | Complete state management (CartController), promo codes, accessibility constraints, evidence locking, and full CI gate profile validation. |
| **3** | [**`calculator-product`**](calculator-product) | 🔴 **Advanced** | Multi-package architecture (`apps/`, `packages/`), backend API contract testing + test-local Flutter UI drivers, security controls (`@ProvidesControl`), and release signing. |

---

## Quick Start (Running Any Example)

To run any example project locally:

1. **Bootstrap dependencies** from the repository root:
   ```bash
   dart run --suppress-analytics melos bootstrap
   ```

2. **Navigate to the example directory**:
   ```bash
   cd examples/todo_app
   # or cd examples/shopping_cart
   # or cd examples/calculator-product
   ```

3. **Generate Zuke contracts and run tests**:
   ```bash
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

- Start with the [**Todo App Example**](todo_app/README.md).
- Read the comprehensive [**Integration & Implementation Guide**](../docs/integration-guide.md) for full architecture details.
