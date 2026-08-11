# zuke_adapter_dart_frog

First-party Dart Frog topology adapter for Zuke V2.

## Support tier

Supported adapter extension API. The adapter uses the public
`dart_frog_gen.buildRouteConfiguration` API and emits target-aware route,
middleware, alias, and WebSocket topology nodes. It reports unresolved or
dynamic registration as incomplete/indeterminate rather than complete.

## Installation

```yaml
dev_dependencies:
  zuke_adapter_dart_frog: ^0.1.0
```
