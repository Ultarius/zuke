# zuke_analyzer

Zuke resolved annotation diagnostics for Dart analysis.

## Preview status

This package is part of the Zuke preview release line.

## Installation

This package is not published to pub.dev. Reference it from the repository:

```yaml
dev_dependencies:
  zuke_analyzer:
    path: ../vendor-sdk/zuke_analyzer
```

Most workspaces should let `zuke` wire the plugin up for them by adding the
`zuke_analyzer` entry to `analysis_options.yaml`; see
[editor-plugin-cache.md](../../docs/editor-plugin-cache.md).

## Support tier

Repository-only analyzer plugin; not published to pub.dev. This analyzer integration
is exercised and released with the Zuke workspace.

## License

MIT. See [LICENSE](LICENSE).
