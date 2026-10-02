/// Editor/index diagnostics API without the full extractor graph.
///
/// Import this from analysis-server plugins so AOT compilation does not
/// pull `DartExtractor` (and its `zuke_core` IR types) into the isolate.
library;

export 'src/index_contract.dart';

export 'src/proof_engine/binding_coverage_engine.dart';

export 'src/tooling/inspection.dart';
