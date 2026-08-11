import 'dart:convert';

import 'package:assurance_ir/assurance_ir.dart';

String renderCommandResult(CommandResultV2 result) => const JsonEncoder.withIndent('  ').convert(result.toJson());

String renderDiagnostics(Iterable<DiagnosticV2> diagnostics) => diagnostics
    .map((diagnostic) => '${diagnostic.code}: ${diagnostic.message}')
    .join('\n');
