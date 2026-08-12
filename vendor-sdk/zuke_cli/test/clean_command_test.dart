import 'dart:io';

import 'package:test/test.dart';

import 'cli_test_helper.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-clean-');
    Directory(
      '${root.path}/packages/example/test/temp_extract_1',
    ).createSync(recursive: true);
    Directory(
      '${root.path}/packages/example/test/temp_fixture_2',
    ).createSync(recursive: true);
    File(
      '${root.path}/packages/example/test/keep.txt',
    ).writeAsStringSync('keep');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('clean removes only test temporary directories', () async {
    final result = await runInProcessCli(['clean', '--root', root.path]);

    expect(result.exitCode, 0);
    expect(
      Directory(
        '${root.path}/packages/example/test/temp_extract_1',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${root.path}/packages/example/test/temp_fixture_2',
      ).existsSync(),
      isFalse,
    );
    expect(
      File('${root.path}/packages/example/test/keep.txt').existsSync(),
      isTrue,
    );
  });

  test('clean dry-run leaves temporary directories untouched', () async {
    final result = await runInProcessCli([
      'clean',
      '--root',
      root.path,
      '--dry-run',
    ]);

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Would remove'));
    expect(
      Directory(
        '${root.path}/packages/example/test/temp_extract_1',
      ).existsSync(),
      isTrue,
    );
  });
}
