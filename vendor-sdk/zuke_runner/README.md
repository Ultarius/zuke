# zuke_runner

Compatibility package for deterministic Gherkin execution and evidence
contracts now implemented by `package:zuke`.

`zuke_runner` is the coordinated compatibility runner package for projects
that keep runner-specific imports separate from the primary `zuke` facade.

## Installation

```yaml
dependencies:
  zuke_runner: ^0.4.0
```

Use these imports in new code:

```dart
import 'package:zuke/zuke.dart';
import 'package:zuke/http.dart'; // HTTP scenario tests only
```

The package provides the current runner surface while the primary SDK remains
available through `package:zuke/zuke.dart`.

## Support tier

Compatibility package for the primary Zuke SDK. See the [integration guide](https://github.com/Ultarius/zuke/blob/main/docs/integration-guide.md).

## License

MIT. See [LICENSE](LICENSE).
