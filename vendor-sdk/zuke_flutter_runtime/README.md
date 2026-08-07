# zuke_flutter_runtime

Typed Flutter key families for Zuke UI bindings.

Use `FlutterBindingKey.single` for one logical widget and
`FlutterBindingKey.collection` with `.instance(stableItemId)` for repeated
widgets such as list rows. This preserves stable item identity without
requiring application code and test code to agree on string-prefix conventions.

## Preview status

This package is part of the Zuke `0.1.0` preview release line.

## Installation

```yaml
dependencies:
  zuke_flutter_runtime: ^0.1.0
```

## Support tier

User-facing SDK. **Support contract:** Supported application-facing public API.
APIs exported by this package are supported for application use during the
`0.1.x` preview. See the [integration guide](https://github.com/Ultarius/zuke/blob/main/docs/integration-guide.md).

## License

MIT. See [LICENSE](LICENSE).
