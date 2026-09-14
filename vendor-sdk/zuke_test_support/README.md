# zuke_test_support

Repository-only test support; not published to pub.dev.

This package is intentionally not part of any runtime package's public
dependency graph. Keep it in `dev_dependencies` only when an application's
tests need the reusable fixtures. Because it is not published, consumers
must resolve it from the Zuke repository (or from a local workspace path):

```yaml
dev_dependencies:
  zuke_test_support:
    git:
      url: https://github.com/Ultarius/zuke.git
      ref: <tested-zuke-revision>
      path: vendor-sdk/zuke_test_support
```

Inside this repository, parent packages can use a relative test bridge when
only one helper is needed:

```dart
export '../../../zuke_test_support/lib/src/temporary_directory.dart';
```

The shared WebSocket driver now belongs to `package:zuke_runner` and should be
imported from that package. This repository-only package is limited to helpers
such as `deleteTemporaryDirectory`; consumers should use a relative bridge for
those helpers or declare this package directly in `dev_dependencies`.

A package must never place `zuke_test_support` under `dependencies` or expose
it from shipped library code.

Published Zuke packages use the same support through their own test trees.
For example, `zuke_cli/test/support/temporary_directory.dart` re-exports the
temporary-directory helper from this repository package. That keeps the
helper owned by the parent package's tests without adding
`zuke_test_support` to the published package's runtime dependencies.

Do not add this package to `dependencies`, and do not import it from library
code that is shipped to consumers. The WebSocket driver and fixture helpers
are test-only APIs; product-specific protocol assertions remain in the
consumer's tests.
