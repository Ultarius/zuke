# zuke_runner

Compatibility package for deterministic Gherkin execution and evidence
contracts now implemented by `package:zuke`.

## Preview status

`zuke_runner` is deprecated as a primary entry package. Version `0.1.1` keeps
the existing libraries source-compatible by forwarding them to `zuke`.

## Installation

```yaml
dependencies:
  zuke: ^0.1.0
```

Use these imports in new code:

```dart
import 'package:zuke/zuke.dart';
import 'package:zuke/http.dart'; // HTTP scenario tests only
```

Existing `package:zuke_runner/zuke_runner.dart`, `runtime.dart`, and
`http.dart` imports continue to compile. There is no removal timeline during
the current preview; keeping the package available also leaves room for a more
specialized runner role in a future breaking release.

## Support tier

Compatibility package for the primary Zuke SDK. See the [integration guide](https://github.com/Ultarius/zuke/blob/main/docs/integration-guide.md).

## License

MIT. See [LICENSE](LICENSE).
