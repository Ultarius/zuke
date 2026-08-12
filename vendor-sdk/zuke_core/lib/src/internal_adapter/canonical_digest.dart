import 'dart:convert';

/// Returns the bytes used when hashing known UTF-8 text inputs.
///
/// Git normally gives the repository LF endings, but Zuke also supports
/// workspaces copied by other tools.  Only the explicit text extensions are
/// normalized; binary and unknown files remain byte-exact.
List<int> canonicalDigestBytes(String path, List<int> bytes) {
  if (!isCanonicalDigestTextPath(path)) return bytes;
  try {
    final text = utf8.decode(bytes);
    return utf8.encode(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  } on FormatException {
    return bytes;
  }
}

bool isCanonicalDigestTextPath(String path) =>
    _canonicalTextExtensions.contains(_extension(path));

const _canonicalTextExtensions = <String>{
  '.dart',
  '.feature',
  '.json',
  '.yaml',
  '.yml',
};

String _extension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.substring(normalized.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}
