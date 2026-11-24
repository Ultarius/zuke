import 'dart:io';

/// Moves [source] to the path [destination].
typedef FileRename = void Function(File source, String destination);

void _renameFile(File source, String destination) {
  source.renameSync(destination);
}

/// Moves [source] over [destination] without ever leaving neither file.
///
/// A direct rename is atomic where the platform allows replacing a file. Where
/// it does not, the existing file is moved aside first and only removed once
/// [source] is in place. If that second move fails the original is restored, and
/// if the restore fails too the backup stays on disk rather than being lost.
///
/// Kept out of the package's public exports: [rename] exists so a test can fail
/// one specific move, which real filesystem state cannot do reliably.
void replaceFile(
  File source,
  File destination, {
  FileRename rename = _renameFile,
}) {
  try {
    rename(source, destination.path);
    return;
  } on FileSystemException {
    if (!destination.existsSync()) rethrow;
  }

  final backup = File(
    '${destination.path}.bak-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  rename(destination, backup.path);
  try {
    rename(source, destination.path);
  } on FileSystemException {
    rename(backup, destination.path);
    rethrow;
  }
  try {
    backup.deleteSync();
  } on FileSystemException {
    // The new content is already in place. A leftover backup is untidy but
    // must not report a completed replacement as failed.
  }
}
