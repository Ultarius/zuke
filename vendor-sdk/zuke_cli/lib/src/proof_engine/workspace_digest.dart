import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart';

/// Computes the deterministic digest of repository inputs covered by a lock
/// or evidence validation pass.
final class WorkspaceDigest {
  WorkspaceDigest({
    String lockFile = 'zuke.lock.json',
    Iterable<String> generatedPaths = const [],
  }) : _excludedFiles = {
         _normalizeRelative(lockFile),
         for (final path in generatedPaths) _normalizeRelative(path),
       };

  static const _ignoredDirectoryNames = <String>{
    '.dart_tool',
    '.git',
    '.gradle',
    '.idea',
    '.plugin_symlinks',
    '.zuke',
    '.symlinks',
    '.cxx',
    '.externalNativeBuild',
    'Pods',
    'assurance-history',
    'build',
    'coverage',
    'dist',
    'generated',
    'node_modules',
  };

  static const _ignoredFileNames = <String>{
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.packages',
    '.zuke-generated.json',
    'local.properties',
    'pubspec_overrides.yaml',
  };

  static const _separator = <int>[0];

  final Set<String> _excludedFiles;

  Future<String> compute(Directory root) async {
    final files = <_DigestFile>[];
    final entityType = FileSystemEntity.typeSync(root.path);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileSystemException('Workspace root does not exist', root.path);
    }
    if (entityType != FileSystemEntityType.directory) {
      throw FileSystemException('Workspace root is not a directory', root.path);
    }
    final canonicalRoot = Directory(root.resolveSymbolicLinksSync());
    await _collect(canonicalRoot, '', files);
    if (files.isEmpty) {
      throw StateError(
        'WorkspaceDigest computed over zero files: ${root.path}',
      );
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    for (final entry in files) {
      input
        ..add(utf8.encode(entry.relativePath))
        ..add(_separator);
      if (isCanonicalDigestTextPath(entry.relativePath)) {
        input.add(
          canonicalDigestBytes(
            entry.relativePath,
            entry.file.readAsBytesSync(),
          ),
        );
      } else {
        await for (final chunk in entry.file.openRead()) {
          input.add(chunk);
        }
      }
      input.add(_separator);
    }
    input.close();
    return output.value.toString();
  }

  /// Computes a digest over the exact configuration and specification inputs
  /// already read by workspace discovery. Paths are made workspace-relative so
  /// aliases and absolute checkout locations produce the same result.
  static String computeInputContents(
    Directory root,
    Map<String, String> inputContents,
  ) {
    final entityType = FileSystemEntity.typeSync(root.path);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileSystemException('Workspace root does not exist', root.path);
    }
    if (entityType != FileSystemEntityType.directory) {
      throw FileSystemException('Workspace root is not a directory', root.path);
    }
    final physicalRoot = Directory(root.resolveSymbolicLinksSync());
    final normalizedRoot = physicalRoot.path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final comparisonRoot = _comparisonPath(normalizedRoot);
    final entries = inputContents.entries.map((entry) {
      final absoluteFile = File(entry.key).absolute;
      final resolvedPath = absoluteFile.existsSync()
          ? absoluteFile.resolveSymbolicLinksSync()
          : absoluteFile.path;
      final path = resolvedPath.replaceAll('\\', '/');
      final comparisonPath = _comparisonPath(path);
      if (comparisonPath != comparisonRoot &&
          !comparisonPath.startsWith('$comparisonRoot/')) {
        throw FileSystemException(
          'Discovered input escapes the workspace',
          entry.key,
        );
      }
      final relative = path
          .substring(normalizedRoot.length)
          .replaceFirst(RegExp(r'^/+'), '');
      return (path: relative, content: entry.value);
    }).toList()..sort((left, right) => left.path.compareTo(right.path));
    if (entries.isEmpty) {
      throw StateError(
        'WorkspaceDigest computed over zero discovery inputs: ${root.path}',
      );
    }

    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    for (final entry in entries) {
      input
        ..add(utf8.encode(entry.path))
        ..add(_separator)
        ..add(canonicalDigestBytes(entry.path, utf8.encode(entry.content)))
        ..add(_separator);
    }
    input.close();
    return output.value.toString();
  }

  /// Synchronously computes a digest over files in [rootPath] matching [include].
  static String computeFiltered(
    String rootPath,
    bool Function(String path) include,
  ) {
    final rootDirectory = Directory(rootPath);
    if (!rootDirectory.existsSync()) {
      return 'sha256:0000000000000000000000000000000000000000000000000000000000000000';
    }
    final files =
        rootDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) {
              final relative = file.path
                  .substring(rootDirectory.path.length)
                  .replaceAll('\\', '/')
                  .replaceFirst(RegExp(r'^/+'), '');
              return (file: file, relative: relative);
            })
            .where((entry) => include(entry.relative))
            .toList()
          ..sort((left, right) => left.relative.compareTo(right.relative));
    final bytes = <int>[];
    for (final entry in files) {
      bytes
        ..addAll(utf8.encode(entry.relative))
        ..add(0)
        ..addAll(
          canonicalDigestBytes(entry.relative, entry.file.readAsBytesSync()),
        )
        ..add(0);
    }
    return 'sha256:${sha256.convert(bytes)}';
  }

  Future<void> _collect(
    Directory directory,
    String relativeDirectory,
    List<_DigestFile> files,
  ) async {
    await for (final entity in directory.list(followLinks: false)) {
      final name = _basename(entity.path);
      final relativePath = relativeDirectory.isEmpty
          ? name
          : '$relativeDirectory/$name';
      if (entity is Directory) {
        if (_ignoreDirectory(name, relativePath)) continue;
        await _collect(entity, relativePath, files);
        continue;
      }
      if (entity is! File || _ignoreFile(name, relativePath)) {
        continue;
      }
      files.add(_DigestFile(File(entity.path), relativePath));
    }
  }

  bool _ignoreDirectory(String name, String relativePath) {
    if (_ignoredDirectoryNames.contains(name)) return true;
    final segments = relativePath.split('/');
    return name == 'ephemeral' &&
        segments.length >= 2 &&
        segments[segments.length - 2] == 'flutter';
  }

  bool _ignoreFile(String name, String relativePath) =>
      _excludedFiles.contains(relativePath) ||
      _ignoredFileNames.contains(name) ||
      name.endsWith('.iml');

  static String _basename(String path) =>
      path.replaceAll(r'\', '/').split('/').last;

  static String _normalizeRelative(String path) {
    var normalized = path.replaceAll(r'\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  static String _comparisonPath(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;
}

final class _DigestFile {
  const _DigestFile(this.file, this.relativePath);

  final File file;
  final String relativePath;
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final value = _value;
    if (value == null) {
      throw StateError('Workspace digest conversion did not produce a value.');
    }
    return value;
  }

  @override
  void add(Digest data) {
    if (_value != null) {
      throw StateError('Workspace digest conversion produced multiple values.');
    }
    _value = data;
  }

  @override
  void close() {}
}
