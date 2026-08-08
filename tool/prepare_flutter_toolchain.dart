import 'dart:io';

Future<void> main() async {
  final flutterRootValue = Platform.environment['FLUTTER_ROOT'];
  if (flutterRootValue == null || flutterRootValue.trim().isEmpty) {
    stderr.writeln(
      'FLUTTER_ROOT is not set; the Flutter toolchain cannot be prepared.',
    );
    exitCode = 1;
    return;
  }

  final flutterRoot = Directory(flutterRootValue).absolute.path;
  final separator = Platform.pathSeparator;
  String join(String first, String second) => '$first$separator$second';

  final flutterToolsDirectory = join(
    join(flutterRoot, 'packages'),
    'flutter_tools',
  );
  final dartExecutable = join(
    join(join(join(flutterRoot, 'bin'), 'cache'), 'dart-sdk'),
    join('bin', Platform.isWindows ? 'dart.exe' : 'dart'),
  );
  final packageConfig = join(
    join(flutterToolsDirectory, '.dart_tool'),
    'package_config.json',
  );

  if (!File(dartExecutable).existsSync()) {
    stderr.writeln('Flutter bundled Dart executable is missing: $dartExecutable');
    exitCode = 1;
    return;
  }

  final result = await Process.run(
    dartExecutable,
    const ['--suppress-analytics', 'pub', 'get'],
    workingDirectory: flutterToolsDirectory,
    runInShell: false,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    exitCode = result.exitCode;
    return;
  }

  if (!File(packageConfig).existsSync()) {
    stderr.writeln(
      'Flutter tool package configuration was not created: $packageConfig',
    );
    exitCode = 1;
  }
}
