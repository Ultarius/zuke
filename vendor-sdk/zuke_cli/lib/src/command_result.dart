import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/src/atomic_file_writer.dart';

Diagnostic gateDiagnostic({
  required String stage,
  required String message,
  String? profile,
}) => Diagnostic(
  code: 'ZK-GATE-${stage.toUpperCase()}-FAILED',
  stage: stage,
  severity: DiagnosticSeverity.error,
  owner: DiagnosticOwner.unknown,
  message: message,
  remediation: 'Inspect the stage result and resolve the reported failure.',
  profile: profile,
);

/// Encodes the one command-result document used by stdout, summaries, and
/// safe artifact bundles. The trailing newline is part of the canonical byte
/// contract and therefore also part of any filename/content digest.
String encodeCommandResult(CommandResult result) =>
    '${canonicalJson(result.toJson())}\n';

/// Writes command-result bytes without deleting an existing destination.
///
/// Windows can report a destination collision while a previous process still
/// has the file open. Identical bytes are idempotent; different bytes are a
/// hard conflict so a concurrent writer can never silently replace a result.
void writeCommandResult(File destination, String encoded) {
  writeBytesAtomically(
    destination,
    utf8.encode(encoded),
    conflictCode: 'ZK-COMMAND-RESULT-WRITE-CONFLICT',
  );
}

void writeCommandSummary(String? path, CommandResult result) {
  if (path == null || path.isEmpty) return;
  writeCommandSummaryBytes(path, encodeCommandResult(result));
}

void writeCommandSummaryBytes(String? path, String encoded) {
  if (path == null || path.isEmpty) return;
  writeCommandResult(File(path), encoded);
}
