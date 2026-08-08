// coverage:ignore-file
// This file defines the adapter extension contract; it contains no executable
// implementation to measure. Concrete adapters are covered by their owners.

import '../assurance_ir.dart';

export '../assurance_ir.dart'
    show
        AdapterCompleteness,
        AdapterDescriptor,
        AdapterOutput,
        Diagnostic,
        DiagnosticSeverity,
        ExtractedSourceLocation,
        ExtractedSymbol;

/// Source compatibility alias; the object is owned by assurance_ir.
typedef AdapterInfo = AdapterDescriptor;

abstract class FrameworkAdapter {
  AdapterDescriptor get adapterInfo;
  Future<AdapterOutput> extract(String rootPath);
}
