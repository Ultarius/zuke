# zuke_cli

<p align="center">
  <a href="https://github.com/Ultarius/zuke">
    <img src="https://raw.githubusercontent.com/Ultarius/zuke/main/assets/brand/zuke-wordmark.png" alt="Zuke" width="390">
  </a>
</p>

Authoritative zuke CLI tool.

## Preview status

Version `0.2.0` generates pure-Dart step support against the primary `zuke`
SDK while preserving narrow `zuke_annotations` imports for generated
application contracts.

## Installation

```yaml
dev_dependencies:
  zuke_cli: ^0.2.0
```

Projects that regenerate non-Flutter steps with CLI `0.2.0` must add
`zuke: ^0.1.0` to the dependency section used by those tests. Flutter steps
continue to use `zuke_runner_flutter`.

## Support tier

Supported CLI for generation, extraction, validation, locks, and gates. See the [integration guide](https://github.com/Ultarius/zuke/blob/main/docs/integration-guide.md).

## License

MIT. See [LICENSE](LICENSE).
