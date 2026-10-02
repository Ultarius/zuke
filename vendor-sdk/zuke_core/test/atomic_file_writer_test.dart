import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('zuke-atomic-');
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test('writeBytesReplacing creates parent directories and writes bytes', () {
    final destination = File(
      '${temporary.path}${Platform.pathSeparator}nested${Platform.pathSeparator}out.json',
    );
    writeBytesReplacing(destination, utf8.encode('{"a":1}\n'));
    expect(destination.readAsStringSync(), '{"a":1}\n');
    expect(destination.parent.listSync().whereType<File>().map((f) => f.path), [
      destination.path,
    ]);
  });

  test('writeBytesReplacing overwrites differing destination bytes', () {
    final destination = File(
      '${temporary.path}${Platform.pathSeparator}out.json',
    );
    writeBytesReplacing(destination, utf8.encode('first'));
    writeBytesReplacing(destination, utf8.encode('second'));
    expect(destination.readAsStringSync(), 'second');
    expect(destination.parent.listSync().whereType<File>().map((f) => f.path), [
      destination.path,
    ]);
  });

  test('writeBytesReplacing is idempotent for identical bytes', () {
    final destination = File(
      '${temporary.path}${Platform.pathSeparator}out.json',
    );
    writeBytesReplacing(destination, utf8.encode('same'));
    writeBytesReplacing(destination, utf8.encode('same'));
    expect(destination.readAsStringSync(), 'same');
  });

  test('writeBytesAtomically still reports differing bytes as a conflict', () {
    final destination = File(
      '${temporary.path}${Platform.pathSeparator}conflict.json',
    );
    const conflictCode = 'ZK-COMMAND-RESULT-WRITE-CONFLICT';
    writeBytesAtomically(
      destination,
      utf8.encode('first'),
      conflictCode: conflictCode,
    );
    expect(
      () => writeBytesAtomically(
        destination,
        utf8.encode('second'),
        conflictCode: conflictCode,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(conflictCode),
        ),
      ),
    );
    expect(destination.readAsStringSync(), 'first');
  });
}
