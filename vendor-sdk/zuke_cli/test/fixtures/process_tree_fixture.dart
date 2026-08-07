import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final heartbeat = File(arguments.last);
  if (arguments.contains('--child')) {
    Timer.periodic(const Duration(milliseconds: 50), (_) {
      heartbeat.writeAsStringSync(
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
    });
    await Completer<void>().future;
  }

  final child = await Process.start(Platform.resolvedExecutable, [
    Platform.script.toFilePath(),
    '--child',
    heartbeat.path,
  ]);
  File(
    '${heartbeat.path}.ready',
  ).writeAsStringSync(jsonEncode({'parent': pid, 'child': child.pid}));
  final keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {});
  await Completer<void>().future;
  keepAlive.cancel();
}
