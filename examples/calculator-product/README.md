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
- **Security controls (`@ProvidesControl`)**: Links rate-limiting, input validation, and error redaction controls to executable application code and integration evidence.
- **Release Trust History**: Manages immutable evidence digests in `assurance-history/` for release gate enforcement.

---

## Rate-limit demonstration

This example does not require Azure API Management. The default implementation
uses `RateLimitMiddleware` at the application's HTTP request boundary. The
integration test sends real HTTP requests through `CalculatorServer` and proves
that:

1. two requests from one identity are accepted;
2. the next request from that identity receives `429 RATE_LIMIT_EXCEEDED` and
   `Retry-After: 60`;
3. the rejected request does not invoke the calculator controller or domain;
4. a different identity remains allowed.

Run the human-readable demonstration with:

```bash
dart run bin/rate_limit_demo.dart
```

GitHub Actions runs this same demonstration and places its result table in the
job summary. The Zuke control is therefore `proven` by source analysis and
repeatable integration evidence, rather than being represented as a fictional
external gateway attestation.

If the service is later deployed behind Azure API Management, the same
behavior can be enforced at the gateway instead. The APIM policy and migration
notes are in [docs/apim-rate-limit.md](docs/apim-rate-limit.md). That deployment
choice is intentionally separate from this local CI demonstration.
