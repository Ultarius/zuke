import 'dart:io';

/// Writes an exact byte sequence without deleting an existing destination.
///
/// This is shared by command-result and managed evidence writers so collision
/// handling remains identical on every platform. A destination already
/// containing the same bytes is an idempotent success; different bytes are a
/// hard conflict reported with the caller's domain-specific diagnostic code.
void writeBytesAtomically(
  File destination,
  List<int> bytes, {
  required String conflictCode,
}) {
  destination.parent.createSync(recursive: true);
  final temporary = File(
    '${destination.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
  );

  try {
    final handle = temporary.openSync(mode: FileMode.write);
    try {
      handle.writeFromSync(bytes);
      handle.flushSync();
    } finally {
      handle.closeSync();
    }

    if (destination.existsSync()) {
      final existing = destination.readAsBytesSync();
      if (_sameBytes(existing, bytes)) return;
      throw _writeConflict(conflictCode);
    }

    try {
      temporary.renameSync(destination.path);
    } on FileSystemException {
      // Windows can report a collision when another writer wins the rename.
      // Never delete the winner; compare its exact bytes instead.
      if (!destination.existsSync()) rethrow;
      final existing = destination.readAsBytesSync();
      if (!_sameBytes(existing, bytes)) {
        throw _writeConflict(conflictCode);
      }
    }
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

FormatException _writeConflict(String conflictCode) =>
    FormatException('$conflictCode: destination contains different bytes');

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
