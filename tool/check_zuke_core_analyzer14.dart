import 'dart:async';
import 'dart:io';

Future<void> main() async {
  final repositoryRoot = Directory.current.absolute;
  final sourceRoot = Directory('${repositoryRoot.path}/vendor-sdk');
  final temporaryRoot = Directory.systemTemp.createTempSync(
    'zuke-core-analyzer14-',
  );

  try {
    _writeRootPubspec(temporaryRoot);
    _copyPackage(sourceRoot, temporaryRoot, 'zuke_core');
    _copyPackage(sourceRoot, temporaryRoot, 'zuke_annotations');
    _copyPackage(sourceRoot, temporaryRoot, 'zuke_frontend');
    _copyPackage(sourceRoot, temporaryRoot, 'zuke');
    _copyPackage(sourceRoot, temporaryRoot, 'zuke_cli');
    _copyPackage(sourceRoot, temporaryRoot, 'zuke_http_runtime');

    final testDirectory = Directory('${temporaryRoot.path}/test')
      ..createSync(recursive: true);
    final extractorTest = File(
      '${repositoryRoot.path}${Platform.pathSeparator}vendor-sdk'
      '${Platform.pathSeparator}zuke_cli${Platform.pathSeparator}test'
      '${Platform.pathSeparator}tooling${Platform.pathSeparator}dart_extractor_test.dart',
    );
    if (!extractorTest.existsSync()) {
      throw StateError(
        'Required analyzer compatibility fixture is missing: '
        '${extractorTest.path}. The extractor fixture belongs to '
        'zuke_cli/test/tooling, not zuke_core/test.',
      );
    }
    extractorTest.copySync('${testDirectory.path}/dart_extractor_test.dart');

    final pubGet = await Process.run(Platform.resolvedExecutable, [
      '--suppress-analytics',
      'pub',
      'get',
    ], workingDirectory: temporaryRoot.path);
    stdout.write(pubGet.stdout);
    stderr.write(pubGet.stderr);
    if (pubGet.exitCode != 0) {
      exitCode = pubGet.exitCode;
      return;
    }

    final tests = await Process.run(Platform.resolvedExecutable, [
      '--suppress-analytics',
      'test',
      'test/dart_extractor_test.dart',
      '--reporter',
      'expanded',
    ], workingDirectory: temporaryRoot.path);
    stdout.write(tests.stdout);
    stderr.write(tests.stderr);
    exitCode = tests.exitCode;
  } finally {
    await _deleteDirectoryWithRetry(temporaryRoot);
  }
}

void _writeRootPubspec(Directory root) {
  File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: zuke_core_analyzer14_smoke
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  zuke_cli:
    path: zuke_cli
  zuke_annotations:
    path: zuke_annotations
  zuke_core:
    path: zuke_core
  zuke_frontend:
    path: zuke_frontend
  zuke:
    path: zuke
  zuke_http_runtime:
    path: zuke_http_runtime
dev_dependencies:
  test: ^1.31.1
dependency_overrides:
  zuke_annotations:
    path: zuke_annotations
  zuke_cli:
    path: zuke_cli
  zuke_core:
    path: zuke_core
  zuke_frontend:
    path: zuke_frontend
  zuke_http_runtime:
    path: zuke_http_runtime
  zuke:
    path: zuke
''');
}

void _copyPackage(
  Directory sourceRoot,
  Directory destinationRoot,
  String name,
) {
  final source = Directory('${sourceRoot.path}/$name');
  final destination = Directory('${destinationRoot.path}/$name')
    ..createSync(recursive: true);
  _copyTree(
    Directory('${source.path}/lib'),
    Directory('${destination.path}/lib'),
  );
  final pubspec = File('${source.path}/pubspec.yaml')
      .readAsStringSync()
      .replaceFirst(
        RegExp(r'^resolution: workspace\r?\n', multiLine: true),
        '',
      );
  File('${destination.path}/pubspec.yaml').writeAsStringSync(pubspec);
}

void _copyTree(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      _copyTree(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  var delay = const Duration(milliseconds: 25);
  while (DateTime.now().isBefore(deadline)) {
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(delay);
      delay *= 2;
      if (delay > const Duration(milliseconds: 500)) {
        delay = const Duration(milliseconds: 500);
      }
    }
  }
  throw StateError('Unable to remove temporary directory: ${directory.path}');
}
