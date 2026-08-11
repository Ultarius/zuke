import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/v2.dart';

DiagnosticV2 gateDiagnostic({
  required String stage,
  required String message,
  String? profile,
}) => DiagnosticV2(
      code: 'ZK-GATE-${stage.toUpperCase()}-FAILED',
      stage: stage,
      severity: DiagnosticSeverity.error,
      owner: DiagnosticOwner.unknown,
      message: message,
      remediation: 'Inspect the stage result and resolve the reported failure.',
      profile: profile,
    );

void writeCommandSummary(String? path, CommandResultV2 result) {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(result.toJson()) + '\n',
  );
}
