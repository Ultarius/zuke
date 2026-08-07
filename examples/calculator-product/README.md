# Calculator Product Workspace 🔴 (Advanced Reference)

This is an advanced multi-package BDD and security attestation workspace
reference for Zuke. It demonstrates multi-tier specification testing across
backend Dart APIs, Flutter mobile applications, domain logic packages, and
security controls.

---

## Workspace Structure

```
calculator-product/
├── apps/
│   ├── calculator_api/       # Backend HTTP server (Dart) with Gherkin API driver tests
│   └── calculator_mobile/    # Mobile client application (Flutter) with Gherkin UI driver tests
├── packages/
│   ├── calculator_contracts/ # Strongly typed contracts & generated drivers (zuke generate)
│   └── calculator_domain/    # Core arithmetic & business domain logic
├── apps/calculator_mobile/test/support/
│   └── calculator_flutter_driver.dart # Test-only Flutter interaction driver
├── specs/                    # Gherkin features, PBIs, epics, controls, registries
├── policies/                 # Security, compliance, & performance policy configurations
├── assurance-history/        # Immutable release trust history & signed digests
└── zuke.yaml            # Zuke multi-target workspace configuration
```

---

## How to Run

From the repository root:

```bash
# 1. Bootstrap all packages in the workspace
dart run --suppress-analytics melos bootstrap

# 2. Generate contracts across all packages
dart run zuke_cli:zuke generate --root examples/calculator-product

# 3. Validate static control attestation graphs
dart run zuke_cli:zuke validate --root examples/calculator-product --profile pullRequest

# 4. Check lockfile consistency
dart run zuke_cli:zuke lock --root examples/calculator-product --profile pullRequest --check

# 5. Run the pull-request gate
dart run zuke_cli:zuke gate --root examples/calculator-product --profile pullRequest
```

Alternatively, run via Melos:
```bash
dart run melos run zuke:gate
```

---

## Key Capabilities Demonstrated

- **Multi-Package Workspace**: Separates UI, API server, domain logic, and generated contracts into modular Dart packages; keeps the UI driver local to the mobile test suite.
- **Dual Testing Target**: Gherkin scenarios execute against both HTTP APIs (`calculator_api`) and Flutter Widget trees (`calculator_mobile`).
- **Security Attestation (`@ProvidesControl`)**: Links rate-limiting, input validation, and error redaction controls to formal security policies in `policies/`.
- **Release Trust History**: Manages immutable evidence digests in `assurance-history/` for release gate enforcement.
