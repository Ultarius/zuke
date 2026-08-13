import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

enum ZukeIndexFreshnessIssueKind {
  generatedManifestMissing,
  generatedManifestDigestMismatch,
  generatedManifestMalformed,
  generatedOutputMissing,
  generatedOutputDigestMismatch,
  inputMissing,
  inputDigestMismatch,
  inputInventoryMismatch,
  inputSetDigestMismatch,
}

final class ZukeIndexFreshnessIssue {
  final ZukeIndexFreshnessIssueKind kind;
  final String path;
  final String message;

  const ZukeIndexFreshnessIssue({
    required this.kind,
    required this.path,
    required this.message,
  });
}

/// Read-only input index shared by generation, editor diagnostics, and hooks.
/// The index is never assurance evidence: it only allows local tooling to
/// reject stale mappings before a CLI validation run.
class ZukeIndex {
  static const kind = 'zuke.analyzer-index';

  final String inputDigest;
  final String generatedManifestDigest;
  final String generatedManifestPath;
  final List<ZukeIndexInput> inputs;
  final List<String> inputPatterns;
  final Set<String> patternInputs;
  final Set<String> requirementIds;
  final Set<String> controlIds;
  final Set<String> bindingIds;

  const ZukeIndex({
    required this.inputDigest,
    required this.generatedManifestDigest,
    required this.generatedManifestPath,
    required this.inputs,
    this.inputPatterns = const [],
    this.patternInputs = const {},
    required this.requirementIds,
    required this.controlIds,
    required this.bindingIds,
  });

  factory ZukeIndex.create({
    required String root,
    required Iterable<String> inputPaths,
    required String generatedManifestContent,
    required String generatedManifestPath,
    required Iterable<String> requirementIds,
    required Iterable<String> controlIds,
    required Iterable<String> bindingIds,
    Iterable<String> inputPatterns = const [],
    Iterable<String> patternInputPaths = const [],
    Map<String, String>? inputContents,
  }) {
    late final String rootPath;
    try {
      rootPath = Directory(root).resolveSymbolicLinksSync();
    } catch (_) {
      rootPath = Directory(root).absolute.path;
    }
    final inputs =
        inputPaths
            .map((path) {
              try {
                return File(path).resolveSymbolicLinksSync();
              } catch (_) {
                return File(path).absolute.path;
              }
            })
            .where(
              (path) =>
                  inputContents?.containsKey(path) == true ||
                  File(path).existsSync(),
            )
            .map((path) {
              final cached = inputContents?[path];
              final bytes = cached != null
                  ? utf8.encode(cached)
                  : File(path).readAsBytesSync();
              return ZukeIndexInput(
                path: _relative(rootPath, path),
                digest: _sha256(bytes),
              );
            })
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final normalizedPatterns =
        inputPatterns.map(_validatedPattern).toSet().toList()..sort();
    final normalizedPatternInputs = patternInputPaths
        .map((path) {
          try {
            return File(path).resolveSymbolicLinksSync();
          } catch (_) {
            return File(path).absolute.path;
          }
        })
        .map((path) => _relative(rootPath, path))
        .toSet();
    final requirements = Set<String>.from(requirementIds)
      ..removeWhere((id) => id.isEmpty);
    final controls = Set<String>.from(controlIds)
      ..removeWhere((id) => id.isEmpty);
    final bindings = Set<String>.from(bindingIds)
      ..removeWhere((id) => id.isEmpty);
    return ZukeIndex(
      inputDigest: _inputDigest(
        inputs,
        requirements,
        controls,
        bindings,
        normalizedPatterns,
        normalizedPatternInputs,
      ),
      generatedManifestDigest: _sha256(utf8.encode(generatedManifestContent)),
      generatedManifestPath: _validatedRelativePath(generatedManifestPath),
      inputs: List.unmodifiable(inputs),
      inputPatterns: List.unmodifiable(normalizedPatterns),
      patternInputs: Set.unmodifiable(normalizedPatternInputs),
      requirementIds: Set.unmodifiable(requirements),
      controlIds: Set.unmodifiable(controls),
      bindingIds: Set.unmodifiable(bindings),
    );
  }

  factory ZukeIndex.fromJson(Map<Object?, Object?> json) {
    if (json['kind'] != kind) {
      throw const FormatException('Unsupported Zuke analyzer index schema');
    }
    String requiredString(String field) {
      final value = json[field];
      if (value is! String || value.isEmpty) {
        throw FormatException(
          'Analyzer index $field must be a non-empty string',
        );
      }
      return value;
    }

    Set<String> ids(String field) {
      final value = json[field];
      if (value is! List ||
          value.any((entry) => entry is! String || entry.isEmpty)) {
        throw FormatException('Analyzer index $field must be a list of IDs');
      }
      return Set.unmodifiable(value.cast<String>());
    }

    final inputs = json['inputs'];
    if (inputs is! List) {
      throw const FormatException('Analyzer index inputs missing');
    }
    final patterns = json['inputPatterns'];
    if (patterns is! List || patterns.any((value) => value is! String)) {
      throw const FormatException('Analyzer index inputPatterns missing');
    }
    final patternInputs = json['patternInputs'];
    if (patternInputs is! List ||
        patternInputs.any((value) => value is! String)) {
      throw const FormatException('Analyzer index patternInputs missing');
    }
    return ZukeIndex(
      inputDigest: requiredString('inputDigest'),
      generatedManifestDigest: requiredString('generatedManifestDigest'),
      generatedManifestPath: _validatedRelativePath(
        requiredString('generatedManifestPath'),
      ),
      inputs: List.unmodifiable(
        inputs.map((input) {
          if (input is! Map) {
            throw const FormatException('Invalid analyzer index input');
          }
          return ZukeIndexInput.fromJson(input);
        }),
      ),
      inputPatterns: List.unmodifiable(
        patterns.cast<String>().map(_validatedPattern).toList()..sort(),
      ),
      patternInputs: Set.unmodifiable(
        patternInputs.cast<String>().map(_validatedRelativePath),
      ),
      requirementIds: ids('requirementIds'),
      controlIds: ids('controlIds'),
      bindingIds: ids('bindingIds'),
    );
  }

  factory ZukeIndex.read(File file) => ZukeIndex.fromJson(
    Map<Object?, Object?>.from(jsonDecode(file.readAsStringSync()) as Map),
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'inputDigest': inputDigest,
    'generatedManifestDigest': generatedManifestDigest,
    'generatedManifestPath': generatedManifestPath,
    'inputs': inputs.map((input) => input.toJson()).toList(),
    'inputPatterns': inputPatterns,
    'patternInputs': patternInputs.toList()..sort(),
    'requirementIds': requirementIds.toList()..sort(),
    'controlIds': controlIds.toList()..sort(),
    'bindingIds': bindingIds.toList()..sort(),
  };

  bool isCurrent({required String root}) => freshnessIssues(root: root).isEmpty;

  List<ZukeIndexFreshnessIssue> freshnessIssues({required String root}) {
    final issues = <ZukeIndexFreshnessIssue>[];
    final generatedManifest = File(_join(root, generatedManifestPath));
    if (!generatedManifest.existsSync()) {
      return [
        ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.generatedManifestMissing,
          path: generatedManifestPath,
          message: 'Generated manifest is missing: $generatedManifestPath',
        ),
      ];
    }
    if (_sha256(generatedManifest.readAsBytesSync()) !=
        generatedManifestDigest) {
      return [
        ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.generatedManifestDigestMismatch,
          path: generatedManifestPath,
          message: 'Generated manifest content changed: $generatedManifestPath',
        ),
      ];
    }
    issues.addAll(_generatedOutputIssues(root, generatedManifest));
    final rootPath = Directory(root).absolute.path;
    final currentPatternInputs = _matchedPatternInputs(rootPath, inputPatterns);
    if (!_sameSet(currentPatternInputs, patternInputs)) {
      final changed =
          <String>{...currentPatternInputs, ...patternInputs}
              .where(
                (path) =>
                    !currentPatternInputs.contains(path) ||
                    !patternInputs.contains(path),
              )
              .toList()
            ..sort();
      issues.add(
        ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.inputInventoryMismatch,
          path: changed.isEmpty ? '.zuke/analyzer-index.json' : changed.first,
          message:
              'Configured specification inputs changed: '
              '${changed.isEmpty ? '.zuke/analyzer-index.json' : changed.join(', ')}',
        ),
      );
    }
    final current = <ZukeIndexInput>[];
    for (final input in inputs) {
      final file = File(_join(rootPath, input.path));
      if (!file.existsSync()) {
        issues.add(
          ZukeIndexFreshnessIssue(
            kind: ZukeIndexFreshnessIssueKind.inputMissing,
            path: input.path,
            message: 'Indexed input is missing: ${input.path}',
          ),
        );
        continue;
      }
      final currentInput = ZukeIndexInput(
        path: input.path,
        digest: _sha256(file.readAsBytesSync()),
      );
      current.add(currentInput);
      if (currentInput.digest != input.digest) {
        issues.add(
          ZukeIndexFreshnessIssue(
            kind: ZukeIndexFreshnessIssueKind.inputDigestMismatch,
            path: input.path,
            message: 'Indexed input content changed: ${input.path}',
          ),
        );
      }
    }
    final hasInputIssue = issues.any(
      (issue) =>
          issue.kind == ZukeIndexFreshnessIssueKind.inputMissing ||
          issue.kind == ZukeIndexFreshnessIssueKind.inputDigestMismatch ||
          issue.kind == ZukeIndexFreshnessIssueKind.inputInventoryMismatch,
    );
    if (!hasInputIssue &&
        _inputDigest(
              current,
              requirementIds,
              controlIds,
              bindingIds,
              inputPatterns,
              patternInputs,
            ) !=
            inputDigest) {
      issues.add(
        const ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.inputSetDigestMismatch,
          path: '.zuke/analyzer-index.json',
          message:
              'Analyzer index digest does not match its indexed inputs and IDs',
        ),
      );
    }
    return List.unmodifiable(issues);
  }

  List<ZukeIndexFreshnessIssue> _generatedOutputIssues(
    String root,
    File manifest,
  ) {
    final issues = <ZukeIndexFreshnessIssue>[];
    try {
      final decoded = jsonDecode(manifest.readAsStringSync());
      if (decoded is! Map || decoded['files'] is! List) {
        throw const FormatException('manifest root must contain files');
      }
      for (final value in decoded['files'] as List) {
        if (value is! Map) {
          throw const FormatException('manifest entry must be an object');
        }
        final path = value['path'];
        final contentHash = value['contentHash'];
        if (path is! String ||
            contentHash is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentHash)) {
          throw const FormatException('manifest entry is invalid');
        }
        final normalizedPath = _validatedRelativePath(path);
        final file = File(_join(root, normalizedPath));
        if (!file.existsSync()) {
          issues.add(
            ZukeIndexFreshnessIssue(
              kind: ZukeIndexFreshnessIssueKind.generatedOutputMissing,
              path: normalizedPath,
              message: 'Generated output is missing: $normalizedPath',
            ),
          );
        } else if (sha256.convert(file.readAsBytesSync()).toString() !=
            contentHash) {
          issues.add(
            ZukeIndexFreshnessIssue(
              kind: ZukeIndexFreshnessIssueKind.generatedOutputDigestMismatch,
              path: normalizedPath,
              message: 'Generated output content changed: $normalizedPath',
            ),
          );
        }
      }
      return issues;
    } on FormatException catch (error) {
      return [
        ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.generatedManifestMalformed,
          path: generatedManifestPath,
          message:
              'Generated manifest is malformed: $generatedManifestPath '
              '(${error.message})',
        ),
      ];
    }
  }

  static String _inputDigest(
    List<ZukeIndexInput> inputs,
    Set<String> requirements,
    Set<String> controls,
    Set<String> bindings,
    List<String> patterns,
    Set<String> matchedInputs,
  ) => _sha256(
    utf8.encode(
      _canonicalJson({
        'kind': kind,
        'inputs': (inputs.map((input) => input.toJson()).toList()
          ..sort(
            (left, right) =>
                (left['path'] as String).compareTo(right['path'] as String),
          )),
        'inputPatterns': patterns,
        'patternInputs': matchedInputs.toList()..sort(),
        'requirementIds': requirements.toList()..sort(),
        'controlIds': controls.toList()..sort(),
        'bindingIds': bindings.toList()..sort(),
      }),
    ),
  );
}

String _validatedPattern(String pattern) {
  final normalized = pattern.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.startsWith('../') ||
      normalized.contains('/../') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw FormatException(
      'Analyzer index input pattern must be workspace-relative: $pattern',
    );
  }
  return normalized;
}

Set<String> _matchedPatternInputs(String root, List<String> patterns) {
  final resolvedRoot = Directory(root).resolveSymbolicLinksSync();
  final prefix = resolvedRoot.replaceAll('\\', '/').toLowerCase();
  final matched = <String>{};
  final expressions = patterns.map(_patternExpression).toList();
  for (final entity in Directory(
    root,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    try {
      final physical = FileSystemEntity.isLinkSync(entity.path)
          ? entity.resolveSymbolicLinksSync()
          : entity.path;
      final canonical = physical.replaceAll('\\', '/').toLowerCase();
      if (canonical != prefix && !canonical.startsWith('$prefix/')) continue;
      final relative = _relative(resolvedRoot, physical);
      if (expressions.any((expression) => expression.hasMatch(relative))) {
        matched.add(relative);
      }
    } on FileSystemException {
      // Broken and escaping links are never valid specification inputs.
    }
  }
  return matched;
}

RegExp _patternExpression(String pattern) {
  final normalized = pattern.replaceAll('\\', '/');
  final buffer = StringBuffer('^');
  for (var index = 0; index < normalized.length; index++) {
    final character = normalized[index];
    if (character == '*' &&
        index + 2 < normalized.length &&
        normalized.substring(index, index + 3) == '**/') {
      buffer.write('(?:.*/)?');
      index += 2;
    } else if (character == '*') {
      buffer.write('[^/]*');
    } else if (character == '?') {
      buffer.write('[^/]');
    } else {
      buffer.write(RegExp.escape(character));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _validatedRelativePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      File(path).isAbsolute ||
      normalized.split('/').contains('..')) {
    throw FormatException(
      'Analyzer index path must be workspace-relative: $path',
    );
  }
  return normalized;
}

class ZukeIndexInput {
  final String path;
  final String digest;
  const ZukeIndexInput({required this.path, required this.digest});
  factory ZukeIndexInput.fromJson(Map<Object?, Object?> json) {
    final path = json['path'];
    final digest = json['digest'];
    if (path is! String ||
        path.isEmpty ||
        File(path).isAbsolute ||
        path.split('/').contains('..') ||
        digest is! String ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid analyzer index input');
    }
    return ZukeIndexInput(path: path, digest: digest);
  }
  Map<String, Object?> toJson() => {'path': path, 'digest': digest};
}

String _sha256(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

String _relative(String root, String path) {
  final normalizedRoot = root
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/$'), '');
  final normalizedPath = path.replaceAll('\\', '/');
  final comparisonRoot = Platform.isWindows
      ? normalizedRoot.toLowerCase()
      : normalizedRoot;
  final comparisonPath = Platform.isWindows
      ? normalizedPath.toLowerCase()
      : normalizedPath;
  if (!comparisonPath.startsWith('$comparisonRoot/')) {
    throw FormatException('Analyzer index input escapes workspace: $path');
  }
  return normalizedPath.substring(normalizedRoot.length + 1);
}

String _join(String root, String relative) =>
    '$root${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
