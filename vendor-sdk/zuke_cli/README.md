# zuke_cli

<p align="center">
  <a href="https://github.com/Ultarius/zuke">
    <img src="https://raw.githubusercontent.com/Ultarius/zuke/main/assets/brand/zuke-wordmark.png" alt="Zuke" width="390">
  </a>
</p>

Authoritative zuke CLI tool.

The current CLI generates contracts, extracts supported framework topology,
executes configured profiles, validates evidence, writes profile locks, and
runs release gates for the primary `zuke` SDK.

## Installation

```yaml
dev_dependencies:
  zuke_cli: ^0.4.1
```

Projects that regenerate non-Flutter steps with the current CLI should add
`zuke: ^0.3.0` to the dependency section used by those tests. Flutter steps
use `zuke_runner_flutter: ^0.3.0`.

## Support tier

Supported CLI for generation, extraction, validation, locks, and gates. See the [integration guide](https://github.com/Ultarius/zuke/blob/main/docs/integration-guide.md).

## License

MIT. See [LICENSE](LICENSE).
