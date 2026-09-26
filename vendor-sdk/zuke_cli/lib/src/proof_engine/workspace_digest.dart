import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart' show sha256Hex;
import 'package:zuke_frontend/zuke_frontend.dart' show GherkinSyntax;
import '../ir.dart';
import '../lock_path.dart';
import '../path_safety.dart';

/// Computes the deterministic digest of repository inputs covered by a lock
/// or evidence validation pass.
final class WorkspaceDigest {
  WorkspaceDigest({
    String? lockFile,
    Iterable<String> generatedPaths = const [],
  }) : _excludedFiles = {
         for (final profile in const [
           'pullRequest',
           'merge',
           'release',
           'nightly',
         ])
           _normalizeRelative(profileLockRelativePath(profile)),
         if (lockFile != null) _normalizeRelative(lockFile),
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

  /// Computes a digest over the configuration and specification inputs
  /// already read by workspace discovery. Paths are made workspace-relative so
  /// aliases and absolute checkout locations produce the same result.
  ///
  /// Inputs are hashed through [structuralDigestBytes], matching every other
  /// specification digest, so prose alone cannot move a lock.
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
      return _InputEntry(relative, entry.value);
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
        ..add(structuralDigestBytes(entry.path, utf8.encode(entry.content)))
        ..add(_separator);
    }
    input.close();
    return output.value.toString();
  }

  static const _emptyDigest =
      'sha256:0000000000000000000000000000000000000000000000000000000000000000';

  /// Synchronously computes a digest over files in [rootPath] matching [include].
  ///
  /// Skips the same ignored tool/platform directories as [compute] so filtered
  /// evidence digests do not walk `.dart_tool`, `build`, and similar trees.
  static String computeFiltered(
    String rootPath,
    bool Function(String path) include,
  ) {
    final rootDirectory = Directory(rootPath);
    if (!rootDirectory.existsSync()) {
      return _emptyDigest;
    }
    final files = <_DigestFile>[];
    _walkFiltered(rootDirectory, '', (file, relative) {
      if (include(relative)) {
        files.add(_DigestFile(file, relative));
      }
    });
    return _hashRelativeFiles(files);
  }

  /// Computes several filtered digests over one recursive listing of [rootPath].
  ///
  /// Each entry in [includes] is an independent predicate; a file may land in
  /// more than one bucket. Per-bucket results match calling [computeFiltered]
  /// once per predicate (same path set, sort order, and hash framing).
  /// Ignored tool/platform directories are pruned as in [computeFiltered].
  static Map<String, String> computeFilteredMany(
    String rootPath,
    Map<String, bool Function(String path)> includes,
  ) {
    final rootDirectory = Directory(rootPath);
    if (!rootDirectory.existsSync()) {
      return {for (final name in includes.keys) name: _emptyDigest};
    }
    final buckets = {for (final name in includes.keys) name: <_DigestFile>[]};
    _walkFiltered(rootDirectory, '', (file, relative) {
      for (final entry in includes.entries) {
        if (entry.value(relative)) {
          buckets[entry.key]!.add(_DigestFile(file, relative));
        }
      }
    });
    return {
      for (final entry in includes.entries)
        entry.key: _hashRelativeFiles(buckets[entry.key]!),
    };
  }

  /// Paths hashed into the evidence `mapping` digest.
  static bool evidenceMappingInclude(String path) =>
      path.startsWith('specs/registry/') ||
      path.startsWith('policies/') ||
      path.endsWith('zuke.yaml');

  /// Paths hashed into the evidence `specificationIndex` digest.
  static bool evidenceSpecificationInclude(String path) =>
      path.startsWith('specs/');

  /// One-listing digests written on evidence records and rechecked on validate.
  static Map<String, String> computeEvidenceIndexDigests(String rootPath) =>
      computeFilteredMany(rootPath, {
        'mapping': evidenceMappingInclude,
        'specificationIndex': evidenceSpecificationInclude,
      });

  static void _walkFiltered(
    Directory directory,
    String relativeDirectory,
    void Function(File file, String relative) onFile,
  ) {
    for (final entity in directory.listSync(followLinks: false)) {
      final name = _basename(entity.path);
      final relative = relativeDirectory.isEmpty
          ? name
          : '$relativeDirectory/$name';
      if (entity is Directory) {
        if (_shouldPruneDirectory(name, relative)) continue;
        _walkFiltered(entity, relative, onFile);
        continue;
      }
      if (entity is File) {
        onFile(entity, relative);
      }
    }
  }

  static bool _shouldPruneDirectory(String name, String relativePath) {
    if (_ignoredDirectoryNames.contains(name)) return true;
    final segments = relativePath.split('/');
    return name == 'ephemeral' &&
        segments.length >= 2 &&
        segments[segments.length - 2] == 'flutter';
  }

  static String _hashRelativeFiles(List<_DigestFile> files) {
    final sorted = [...files]
      ..sort((left, right) => left.relativePath.compareTo(right.relativePath));
    final bytes = <int>[];
    for (final entry in sorted) {
      bytes
        ..addAll(utf8.encode(entry.relativePath))
        ..add(0)
        ..addAll(
          structuralDigestBytes(
            entry.relativePath,
            entry.file.readAsBytesSync(),
          ),
        )
        ..add(0);
    }
    return sha256Hex(bytes);
  }

  /// Whether [relativePath] is reduced to its structural projection before it
  /// is hashed.
  static bool _structuralPath(String relativePath) =>
      relativePath.toLowerCase().endsWith('.feature');

  /// Digest bytes for one workspace file: canonical bytes reduced to the
  /// structural projection when the path has one.
  ///
  /// This is the single entry point for hashing a repository file: the
  /// evidence index, the lock's per-feature hashes, the specification digest,
  /// and the filtered digests all route through it. `.feature` inputs lose
  /// their prose — a scenario title, a description, a comment — so evidence
  /// that already executed the same steps, and a lock that records it, stay
  /// valid across a wording-only edit. Everything else is hashed verbatim.
  static List<int> structuralDigestBytes(String relativePath, List<int> bytes) {
    final canonical = canonicalDigestBytes(relativePath, bytes);
    if (!_structuralPath(relativePath)) return canonical;
    // `allowMalformed` keeps a mis-encoded specification on the projection
    // path instead of silently reverting to a prose-sensitive hash.
    return utf8.encode(
      structuralFeatureText(utf8.decode(canonical, allowMalformed: true)),
    );
  }

  /// Projects a feature file onto the lines that change what tests execute.
  ///
  /// Kept: tags, steps, data tables, doc strings, `# spec-*` metadata, and the
  /// structural keyword of every `Feature`/`Rule`/`Scenario`/`Background`/
  /// `Examples` line. Dropped: keyword titles, free-text descriptions, and
  /// comments outside a metadata block.
  ///
  /// Classification uses [GherkinSyntax], the same vocabulary the parser scans
  /// with, so this projection cannot drift from what a parse would recognize.
  /// An unrecognized line is dropped only when it is not a step, a tag, a
  /// table, or a doc string, mirroring how the parser collects descriptions.
  static String structuralFeatureText(String content) {
    final kept = <String>[];
    var inMetadata = false;
    String? openFence;
    for (final raw in const LineSplitter().convert(content)) {
      final trimmed = raw.trim();
      if (inMetadata) {
        kept.add(raw);
        if (trimmed == '# spec-end' || trimmed == '# rule-spec-end') {
          inMetadata = false;
        }
        continue;
      }
      if (trimmed == '# spec-begin' || trimmed == '# rule-spec-begin') {
        inMetadata = true;
        kept.add(raw);
        continue;
      }
      if (openFence != null) {
        kept.add(raw);
        // Only the delimiter that opened the block can close it, so a `"""`
        // block is not terminated by a stray `'''` line.
        if (trimmed == openFence) openFence = null;
        continue;
      }
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('@') ||
          trimmed.startsWith('|') ||
          GherkinSyntax.stepPrefix.hasMatch(trimmed)) {
        kept.add(raw);
        continue;
      }
      if (trimmed.startsWith('"""') || trimmed.startsWith("'''")) {
        final fence = trimmed.substring(0, 3);
        kept.add(raw);
        if (trimmed.length == fence.length || !trimmed.endsWith(fence)) {
          openFence = fence;
        }
        continue;
      }
      final keyword = GherkinSyntax.keywordOf(trimmed);
      if (keyword != null) kept.add(keyword);
    }
    return kept.join('\n');
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

  bool _ignoreDirectory(String name, String relativePath) =>
      _shouldPruneDirectory(name, relativePath);

  bool _ignoreFile(String name, String relativePath) =>
      _excludedFiles.contains(relativePath) ||
      _ignoredFileNames.contains(name) ||
      name.endsWith('.iml');

  static String _basename(String path) =>
      path.replaceAll(r'\', '/').split('/').last;

  /// Shared with the rest of the CLI; see [normalizeRelativePath].
  static String _normalizeRelative(String path) => normalizeRelativePath(path);

  static String _comparisonPath(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;
}

final class _DigestFile {
  const _DigestFile(this.file, this.relativePath);

  final File file;
  final String relativePath;
}

final class _InputEntry {
  const _InputEntry(this.path, this.content);

  final String path;
  final String content;
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
