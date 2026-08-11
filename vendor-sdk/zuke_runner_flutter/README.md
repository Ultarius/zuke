# zuke_runner_flutter

Flutter testWidgets integration boundary for Zuke scenarios.

## Preview status

This package is part of the Zuke `0.1.x` preview release line.

## Installation

```yaml
dependencies:
  zuke_runner_flutter: ^0.1.0
```

Flutter test code can use this package as its single Zuke facade. It
re-exports the public runner API now owned by `zuke`, plus `zuke_frontend` and
`zuke_annotations`, while preserving the Flutter-specific harness and driver
APIs in this package. Pure-Dart and HTTP test code should depend on `zuke`.

## Support tier

Supported Flutter testWidgets integration boundary. See the [integration guide](https://github.com/Ultarius/zuke/blob/main/docs/integration-guide.md).

## License

MIT. See [LICENSE](LICENSE).
