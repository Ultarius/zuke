/// Editor/index diagnostics API without the full extractor graph.
///
/// Import this from analysis-server plugins so AOT compilation does not
/// pull `DartExtractor` (and its `zuke_core` IR types) into the isolate.
library;

export 'src/tooling/inspection.dart';
