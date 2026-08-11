import 'dart:async';
import 'dart:io';

/// Deletes a test fixture directory while tolerating transient Windows locks.
Future<void> deleteTemporaryDirectory(
  Directory directory, {
  Duration timeout = const Duration(seconds: 5),
  Duration initialDelay = const Duration(milliseconds: 25),
  Duration maximumDelay = const Duration(milliseconds: 500),
}) async {
  Object? lastError;
  final deadline = DateTime.now().add(timeout);
  var attempts = 0;
  var delay = initialDelay;
  while (DateTime.now().isBefore(deadline)) {
    attempts++;
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      lastError = error;
      await Future<void>.delayed(delay);
      delay *= 2;
      if (delay > maximumDelay) delay = maximumDelay;
    }
  }
  throw StateError(
    'Unable to delete temporary directory ${directory.path} after $attempts attempts: $lastError',
  );
}
