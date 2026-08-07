import 'dart:convert';
import 'dart:io';

import 'package:zuke_verifier/zuke_verifier.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: verify <assurance-history.v2.json> <trust-bundle.json>',
    );
    exitCode = 2;
    return;
  }
  try {
    final result = await const ExportedReleaseVerifier().verifyJson(
      File(arguments[0]).readAsStringSync(),
      File(arguments[1]).readAsStringSync(),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    exitCode = result.valid ? 0 : 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
