/// Analyzer-facing extraction package.
///
/// The legacy implementation remains available through `zuke_core` while
/// consumers migrate to this package. New adapters should depend on the
/// analyzer-bearing package rather than pulling analyzer into shared IR.
library;

/// Analyzer-backed implementation surface. The compatibility implementation
/// remains source-compatible while ownership moves out of zuke_core's public
/// facade; future extractor revisions can replace this export without
/// changing CLI consumers.
export 'package:zuke_core/src/dart_extractor.dart';

export 'src/package_extractor.dart';
