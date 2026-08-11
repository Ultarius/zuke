# Zuke

<p align="center">
  <a href="https://github.com/Ultarius/zuke">
    <img src="https://raw.githubusercontent.com/Ultarius/zuke/main/assets/brand/zuke-wordmark.png" alt="Zuke" width="390">
  </a>
</p>

A specification-driven BDD testing, security control attestation, and cryptographic evidence verification framework for Dart and Flutter applications.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Overview

Zuke bridges Gherkin feature specifications with Flutter widget tests, HTTP
drivers, static control attestation graphs, and automated CI/CD release gates.

### Key Capabilities

- 🥒 **Gherkin BDD Testing**: Execute Gherkin scenarios directly within Flutter `testWidgets` and Dart `test` runners.
- 📐 **Strongly-Typed Contract Generation**: Automatically compile Gherkin UI element requirements into Dart abstract interfaces and keys (`zuke generate`).
- 🛡️ **Security Control Attestation**: Link application features to controls (e.g. rate-limiting, authentication) using Dart annotations (`@ProvidesControl`) and YAML policies.
- 🔐 **Cryptographic Evidence Verification**: Capture SHA-256 test execution digests and verify that all specified requirements are covered by evidence.
- 🚦 **Release Gate Enforcement**: Fail CI/CD builds if test suites fail, evidence is stale/missing, or line coverage falls below thresholds (`zuke gate`).

---

## Example Projects & Reference Implementations

Explore runnable example applications in the [**`examples/`**](examples/README.md) directory:

- 🟢 [**`examples/todo_app`**](examples/todo_app/README.md) — **Recommended Starting Point**. Beginner Flutter BDD setup with generated contracts, `@ZukeBinding` UI keys, and widget scenario execution.
- 🟡 [**`examples/shopping_cart`**](examples/shopping_cart/README.md) — Intermediate reference with `CartController` state management, promo logic, accessibility rules, and evidence locking.
- 🔴 [**`examples/calculator-product`**](examples/calculator-product/README.md) — Advanced multi-package reference featuring backend API drivers, mobile UI drivers, security attestation, and signed release records.

---

## Documentation & Guides

- 📖 **[Integration & Implementation Guide](docs/integration-guide.md)** — Integration, release signing, verification, and CI/CD gate guidance.
- 📂 **[Examples Directory Index](examples/README.md)** — Complete guide to all example projects and learning paths.

---

## Quick Start

### Prerequisites

Install Flutter and ensure its `bin` directory is on your `PATH`; Flutter
supplies the compatible Dart SDK. Before bootstrapping the workspace, confirm:

```bash
flutter doctor
dart --version
```

If either command is unavailable, add `<your-flutter-sdk>/bin` to `PATH` and
open a new terminal before continuing.

### 1. Add Dependencies

The supported hosted V2 tuple is defined by `docs/release-matrix.yaml`. The
public release surface contains nine packages: `zuke_core` 0.3.0,
`zuke_annotations` 0.3.0, `zuke_frontend` 0.2.0, `zuke` 0.3.0,
`zuke_runner` 0.3.0, `zuke_runner_flutter` 0.3.0, `zuke_http_runtime` 0.1.1,
`zuke_cli` 0.4.0, and `zuke_dart_build_hook` 0.3.0. Repository-only packages
such as `zuke_analyzer` are not hosted dependencies.

```yaml
dependencies:
  flutter:
    sdk: flutter
  zuke_annotations: ^0.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  zuke: ^0.3.0
  zuke_cli: ^0.4.0
  zuke_runner_flutter: ^0.3.0
```

`zuke` is the primary pure-Dart execution SDK and owns the runner, runtime
events, and HTTP scenario-test helpers. Keep `zuke_annotations` in normal
dependencies when production code only needs metadata, then add `zuke` to
`dev_dependencies` for Dart/backend scenario execution. Add
`zuke_http_runtime` as a normal dependency only when the application registers
an inspectable HTTP topology. `zuke_runner` is retained as a compatibility
package for existing consumers.

### Publishing the Zuke Packages

The supported pub.dev release surface is maintained by the repository publisher
script. It runs each package's native Pub command in dependency order, so the
shared `zuke_core` package is handled before packages that depend on it:

```bash
# Validate every publishable package without uploading anything
dart run tool/publish_packages.dart --dry-run

# Ignore only the expected dirty-worktree warning during local validation
dart run tool/publish_packages.dart --dry-run --ignore-warnings

# Publish all supported packages; the script asks for confirmation
dart run tool/publish_packages.dart --publish
```

To retry one package after a partial release, select it explicitly:

```bash
dart run tool/publish_packages.dart --publish --package zuke_cli
```

### 2. Tag & Profile Support

Zuke parses feature `@FEAT-*`, `@RULE-*`, and `@SCN-*` tags to enforce identity, assurance metadata, and policy rules. Execution profiles (`--profile pullRequest`, `--profile merge`, `--profile release`) determine required evidence assurance levels during `zuke test`, `validate`, and `gate`.

### 3. Run Zuke Release Gate

```bash
# Generate code contracts from Gherkin feature files
dart run zuke_cli:zuke generate --root .

# Run static graph validation for pull requests
dart run zuke_cli:zuke validate --root . --profile pullRequest

# Synchronize SHA-256 lockfile
dart run zuke_cli:zuke lock --root . --profile pullRequest

# Verify one or more workspaces, including configured runners and reports.
dart run zuke_cli:zuke check --root examples/calculator-product --root examples/shopping_cart --root examples/todo_app --profile pullRequest --jobs 3
```

---

## License

Zuke is licensed under the MIT License. See [LICENSE](LICENSE) for details.
