import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/zuke_core.dart';

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
  destination.parent.createSync(recursive: true);
  final temporary = File(
    '${destination.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
  );
  final bytes = utf8.encode(encoded);
  try {
    final handle = temporary.openSync(mode: FileMode.write);
    try {
      handle.writeFromSync(bytes);
      handle.flushSync();
    } finally {
      handle.closeSync();
    }
    if (destination.existsSync()) {
      final existing = destination.readAsBytesSync();
      if (_sameBytes(existing, bytes)) return;
      throw const FormatException(
        'ZK-EVIDENCE-WRITE-CONFLICT: destination contains different bytes',
      );
    }
    try {
      temporary.renameSync(destination.path);
    } on FileSystemException {
      if (!destination.existsSync()) rethrow;
      final existing = destination.readAsStringSync();
      if (existing != encoded) {
        throw const FormatException(
          'ZK-EVIDENCE-WRITE-CONFLICT: destination contains different bytes',
        );
      }
    }
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void writeCommandSummary(String? path, CommandResult result) {
  if (path == null || path.isEmpty) return;
  writeCommandSummaryBytes(path, encodeCommandResult(result));
}

void writeCommandSummaryBytes(String? path, String encoded) {
  if (path == null || path.isEmpty) return;
  writeCommandResult(File(path), encoded);
}
