import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/command_result.dart';

void main() {
  test('command-result writes are byte-idempotent', () {
    final root = Directory.systemTemp.createTempSync('zuke-command-result-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final destination = File('${root.path}/command-result.json');

    writeCommandResult(destination, 'é\n');
    final firstBytes = destination.readAsBytesSync();
    writeCommandResult(destination, 'é\n');

    expect(destination.readAsBytesSync(), firstBytes);
  });

  test('command-result conflicts use the command-specific code', () {
    final root = Directory.systemTemp.createTempSync('zuke-command-result-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final destination = File('${root.path}/command-result.json');

    writeCommandResult(destination, '{"status":"passed"}\n');

    expect(
      () => writeCommandResult(destination, '{"status":"failed"}\n'),
      throwsA(
        predicate<FormatException>(
          (error) =>
              error.message.startsWith('ZK-COMMAND-RESULT-WRITE-CONFLICT:'),
        ),
      ),
    );
  });
}
