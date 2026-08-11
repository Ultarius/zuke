# zuke

<p align="center">
  <a href="https://github.com/Ultarius/zuke">
    <img src="https://raw.githubusercontent.com/Ultarius/zuke/main/assets/brand/zuke-wordmark.png" alt="Zuke" width="390">
  </a>
</p>

The primary pure-Dart SDK for Zuke: connect Gherkin specifications to Dart
implementations, execute scenarios deterministically, and produce assurance
evidence through one supported package.

## What is Zuke?

Zuke connects four things that are usually kept separate:

1. Human-readable Gherkin requirements and scenarios.
2. Dart annotations and generated contracts that identify their implementation.
3. Deterministic Dart, HTTP, and Flutter scenario execution.
4. Validation, evidence, digests, lock files, and release gates.

This package owns the pure-Dart runner implementation, runtime events, feature
flags, and HTTP scenario-test helpers. It re-exports the supported annotation
and Gherkin frontend APIs so a complete Dart integration can use one package.
It does not depend on Flutter, the CLI, the HTTP application runtime, or build
hooks.

## Installation

For a Dart or backend package:

```yaml
dependencies:
  zuke: ^0.1.0
  zuke_http_runtime: ^0.1.0 # Optional: inspect a real HTTP application

dev_dependencies:
  zuke_cli: ^0.2.0
```

For a Flutter application, the narrow dependency layout remains valid and is
often preferable when annotations belong to production code while execution
belongs to tests:

```yaml
dependencies:
  zuke_annotations: ^0.1.0

dev_dependencies:
  zuke_runner_flutter: ^0.1.0
  zuke_cli: ^0.2.0
```

For strict backend separation, keep annotation and application registration
packages in `dependencies`, and place execution APIs in `dev_dependencies`:

```yaml
dependencies:
  zuke_annotations: ^0.1.0
  zuke_http_runtime: ^0.1.0

dev_dependencies:
  test: ^1.26.0
  zuke: ^0.1.0
```

## Public API

The main library re-exports the supported application-facing APIs from:

- `zuke_annotations` for `@ImplementsRequirement`, `@ProvidesControl`,
  `@ZukeBinding`, and related metadata.
- `zuke_frontend` for `GherkinParser`, workspace discovery, and parsed feature
  models.
- This package's own runner implementation for worlds, step registries,
  scenario execution, results, and evidence contracts.
- This package's runtime event and feature-flag APIs.

Backend scenario tests can also import `package:zuke/http.dart` for the
logical-endpoint HTTP driver and reusable HTTP assertions.

## Which package do I need?

| Need | Package |
| --- | --- |
| Main Dart execution and HTTP test API | `zuke` |
| Flutter `testWidgets` harness and vendor steps | `zuke_runner_flutter` |
| Real HTTP route and middleware registration | `zuke_http_runtime` |
| Optional package build validation | `zuke_dart_build_hook` |
| Generate, test, validate, lock, and gate a workspace | `zuke_cli` |
| Low-level extraction, assurance, and adapter integrations | `zuke_core` and other specialized packages |

`zuke_runner` remains available as a source-compatible transition package for
existing `0.1.x` consumers. New pure-Dart execution code should import `zuke`.

## Support tier

Primary pure-Dart Zuke SDK and supported V2 facade. Its runner implementation
and exported APIs are supported for application and test use. Use
`zuke_annotations` directly when production code only needs metadata and the
execution SDK belongs in `dev_dependencies`.

## Typical workflow

```text
Gherkin features and YAML metadata
        |
        v
zuke generate
        |
        v
Typed contracts, binding descriptors, and indexes
        |
        v
zuke or zuke_runner_flutter
        |
        v
Structured scenario results
        |
        v
zuke validate -> zuke lock --profile <name> -> zuke gate
```

The generated source is owned by `zuke_cli`; application code supplies the
drivers, bindings, and domain-specific steps.

## License

MIT. See [LICENSE](LICENSE).
