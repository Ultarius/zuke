import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Drives the real desk process, because delivery bugs live in how the command
/// line wires branches together rather than in one branch alone.
void main() {
  Future<String> runDesk(List<String> commands) async {
    final packageConfig = await Isolate.packageConfig;
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=${packageConfig!.toFilePath()}',
      'bin/library_desk.dart',
    ]);
    final output = StringBuffer();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .forEach(output.write);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach(output.write);
    process.stdin.writeln([...commands, 'quit'].join('\n'));
    await process.stdin.flush();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await Future.wait([stdoutDone, stderrDone]);
    expect(exitCode, 0, reason: output.toString());
    return output.toString();
  }

  const isbn = '9780134685991';
  const threeBranches = [
    'peer listen north',
    'peer listen south',
    'peer listen east',
    'peer connect north south',
    'peer seed north $isbn',
  ];

  test('a share to an unconnected branch fails and sends nothing', () async {
    final output = await runDesk([
      ...threeBranches,
      'peer share north east',
      'peer status',
    ]);

    expect(output, contains('no active connection to east'));
    expect(output, isNot(contains('Shared north -> east')));
    expect(output, contains('south: listening=true'));
    expect(
      RegExp(r'south: .*peer=\[\]').hasMatch(output),
      isTrue,
      reason: 'the loans must not reach a branch that was not named:\n$output',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('each connection delivers to its own destination', () async {
    final output = await runDesk([
      ...threeBranches,
      'peer connect north east',
      'peer share north east',
      'peer status',
    ]);

    expect(output, contains('Shared north -> east. east received: [$isbn]'));
    expect(RegExp(r'south: .*peer=\[\]').hasMatch(output), isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
