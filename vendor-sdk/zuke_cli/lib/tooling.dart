/// First-party analyzer-backed tooling boundary used by build integrations.
///
/// This library is intentionally a toolchain API. Application assurance
/// contracts remain analyzer-free in `package:zuke` and `package:zuke_core`.
library;

export 'src/dart_extractor.dart';
export 'src/tooling/extraction_target.dart';
export 'src/tooling/inspection.dart';
