# zuke_conformance

Conformance fixtures and versioned JSON schemas for Zuke adapters.

## Preview status

This package is part of the synchronized Zuke `0.1.0` preview release.

## Installation

```yaml
dependencies:
  zuke_conformance: ^0.1.0
```

## Minimal usage

Use `ZukeSchemaPaths` to locate the packaged schemas without relying on
monorepo-relative paths:

```dart
import 'package:zuke_conformance/zuke_conformance.dart';

final schemaUri = Uri.parse(ZukeSchemaPaths.behavioralAssuranceManifestV1);
```

The package also contains negative and reference fixtures for adapter authors.

## Support tier

Repository-only tooling; not published to pub.dev. Its schemas and reference
fixtures are maintained with the Zuke workspace.

## License

MIT. See [LICENSE](LICENSE).
