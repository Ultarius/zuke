import 'dart:io';

import 'package:zuke_test_support/zuke_test_support.dart';
import 'package:test/test.dart';

void main() {
  test('deletes nested temporary fixtures', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zuke-test-support-',
    );
    await File(
      '${directory.path}${Platform.pathSeparator}fixture.txt',
    ).writeAsString('fixture');

    await deleteTemporaryDirectory(directory);

    expect(directory.existsSync(), isFalse);
  });
}
