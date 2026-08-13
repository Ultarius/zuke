# Changelog

## 0.3.1

- Include the managed widget-test case identity when emitting suite and
  scenario results so distinct cases and sequential profile runs cannot
  collide during validation.

## 0.3.0

- Added the analyzer-free core dependency and current source identity emission for
  Flutter result artifacts.
- Declared the direct digest dependency and aligned the managed widget-test
  `skip` option with Flutter's boolean test API.
- Allow Flutter's pinned SDK metadata to select the analyzer-8 lane from the
  dual-version-compatible `zuke_core` dependency.

## 0.2.0

- Raised the `zuke` and `zuke_annotations` dependency floors for the
  analyzer-compatible SDK release.

## 0.1.1

- Switched the Flutter runner to the primary `zuke` execution SDK.
- Preserved the existing Flutter runner API and exports.

## 0.1.0

- Initial public preview release.
