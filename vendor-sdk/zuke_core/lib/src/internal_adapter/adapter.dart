// coverage:ignore-file
// This file defines the adapter extension contract; it contains no executable
// implementation to measure. Concrete adapters are covered by their owners.

import '../internal_ir.dart';

export '../internal_ir.dart'
    show
        IrAdapterCompleteness,
        AdapterDescriptor,
        IrAdapterOutput,
        IrDiagnostic,
        IrDiagnosticSeverity,
        ExtractedSourceLocation,
        ExtractedSymbol;

/// Internal source-extraction boundary. Framework topology adapters use the
/// current public [FrameworkAdapter] contract; this interface is only for
/// resolved Dart source extraction before the one-way proof projection.
typedef AdapterInfo = AdapterDescriptor;

abstract class DartSourceExtractor {
  AdapterDescriptor get adapterInfo;
  Future<IrAdapterOutput> extract(String rootPath);
}
