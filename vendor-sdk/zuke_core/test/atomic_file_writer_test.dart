import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_core/src/file_replacement.dart';
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

  group('replaceFile fallback', () {
    late File source;
    late File destination;

    setUp(() {
      source = File('${temporary.path}${Platform.pathSeparator}source')
        ..writeAsStringSync('new');
      destination = File('${temporary.path}${Platform.pathSeparator}target')
        ..writeAsStringSync('old');
    });

    test('keeps the original when the new file cannot be moved in', () {
      var sourceMoves = 0;
      void rename(File from, String to) {
        if (from.path == source.path) {
          sourceMoves++;
          throw FileSystemException('blocked', from.path);
        }
        from.renameSync(to);
      }

      expect(
        () => replaceFile(source, destination, rename: rename),
        throwsA(isA<FileSystemException>()),
      );
      expect(sourceMoves, 2, reason: 'the fallback must have been reached');
      expect(destination.readAsStringSync(), 'old');
      expect(source.readAsStringSync(), 'new');
      expect(temporary.listSync(), hasLength(2), reason: 'no stray backup');
    });

    test('replaces the file and removes its backup on success', () {
      var sourceMoves = 0;
      void rename(File from, String to) {
        if (from.path == source.path && sourceMoves++ == 0) {
          throw FileSystemException('rename-over-existing', from.path);
        }
        from.renameSync(to);
      }

      replaceFile(source, destination, rename: rename);

      expect(destination.readAsStringSync(), 'new');
      expect(temporary.listSync().map((entity) => entity.path), [
        destination.path,
      ]);
    });
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
