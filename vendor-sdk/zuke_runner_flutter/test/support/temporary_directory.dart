import 'dart:async';
import 'dart:io';

Future<void> deleteTemporaryDirectory(
  Directory directory, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
  throw StateError('Unable to delete ${directory.path}: $lastError');
}
