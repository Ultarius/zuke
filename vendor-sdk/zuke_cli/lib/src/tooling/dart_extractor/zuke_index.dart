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

/// One specification finding, carried in the index so an editor can show it.
///
/// The analyzer plugin can only anchor a diagnostic on a Dart node, so the
/// location of the *problem* and the location of the *report* are different
/// things. [file], [line] and [column] say where the specification is wrong;
/// the plugin reports against a generated constant and puts these in the
/// message so the reader can go straight to the `.feature` line.
final class ZukeSpecDiagnostic {
  /// Workspace-relative, forward-slashed path of the offending `.feature`.
  final String file;

  /// 1-based line within [file].
  final int line;

  /// 1-based column within [file], or 0 when the parser reported none.
  final int column;

  /// Diagnostic code, e.g. `ZUKE-REF-009`.
  final String code;

  /// `error`, `warning` or `info`.
  final String severity;

  final String message;

  /// The feature the finding belongs to, when it could be attributed.
  final String? featureId;

  const ZukeSpecDiagnostic({
    required this.file,
    required this.line,
    required this.column,
    required this.code,
    required this.severity,
    required this.message,
    this.featureId,
  });

  /// Stable identity of one finding.
  ///
  /// Defined once, here, so any consumer that pairs a finding with a place to
  /// report it uses the same key. [featureId] is part of it because it decides
  /// *which* generated contract the finding is reported on: one specification
  /// file can declare two features, and collapsing two identical findings would
  /// silently drop one feature's copy.
  String get key => '$code|$file|$line|$column|$message|${featureId ?? ''}';

  /// The finding's location as `file:line`, or `file:line:column` when the
  /// parser reported a column.
  ///
  /// A column of 0 means the parser had none, and printing `:0` would point at a
  /// position that cannot exist.
  String get location => column > 0 ? '$file:$line:$column' : '$file:$line';

  Map<String, Object?> toJson() => {
    'file': file,
    'line': line,
    'column': column,
    'code': code,
    'severity': severity,
    'message': message,
    if (featureId != null) 'featureId': featureId,
  };

  /// Reads one finding leniently, returning null when a required field is
  /// missing or the wrong shape.
  ///
  /// A finding is advice about a specification, not a correctness input to the
  /// index, so an unreadable one is dropped rather than failing the read. The
  /// rest of the index stays usable and the remaining rules still run.
  static ZukeSpecDiagnostic? fromJson(Map<Object?, Object?> json) {
    final file = json['file'];
    final code = json['code'];
    final message = json['message'];
    final line = json['line'];
    final column = json['column'];
    if (file is! String || file.isEmpty) return null;
    if (code is! String || code.isEmpty) return null;
    if (message is! String) return null;
    if (line is! int || line < 1) return null;
    final severity = json['severity'];
    final featureId = json['featureId'];
    return ZukeSpecDiagnostic(
      file: file,
      line: line,
      column: column is int && column > 0 ? column : 0,
      code: code,
      severity: severity is String && severity.isNotEmpty ? severity : 'error',
      message: message,
      featureId: featureId is String && featureId.isNotEmpty ? featureId : null,
    );
  }

  @override
  String toString() =>
      '$severity: [$code] $message ($file:$line${column > 0 ? ':$column' : ''})';
}

/// Feature ID to generated contract path, normalized for direct comparison.
Map<String, String> _normalizedFeatureFiles(Map<String, String> paths) {
  final result = <String, String>{};
  for (final entry in paths.entries) {
    final id = entry.key.trim();
    if (id.isEmpty) continue;
    final path = entry.value.replaceAll('\\', '/').trim();
    if (path.isEmpty) continue;
    result[id] = path;
  }
  return result;
}

/// Drops unreadable and duplicate findings, and orders them deterministically.

///
/// Sorting by file then line then code keeps the generated anchors and the
/// index in the same order across runs, so regenerating an unchanged workspace
/// produces byte-identical output.
List<ZukeSpecDiagnostic> _normalizedSpecDiagnostics(
  Iterable<ZukeSpecDiagnostic> diagnostics,
) {
  final byKey = <String, ZukeSpecDiagnostic>{};
  for (final diagnostic in diagnostics) {
    if (diagnostic.file.trim().isEmpty) continue;
    if (diagnostic.code.trim().isEmpty) continue;
    if (diagnostic.line < 1) continue;
    byKey.putIfAbsent(diagnostic.key, () => diagnostic);
  }
  final ordered = byKey.values.toList()
    ..sort((left, right) {
      final byFile = left.file.compareTo(right.file);
      if (byFile != 0) return byFile;
      final byLine = left.line.compareTo(right.line);
      if (byLine != 0) return byLine;
      final byColumn = left.column.compareTo(right.column);
      if (byColumn != 0) return byColumn;
      return left.key.compareTo(right.key);
    });
  return ordered;
}

/// Read-only input index shared by generation, editor diagnostics, and hooks.
/// The index is never assurance evidence: it only allows local tooling to
/// reject stale mappings before a CLI validation run.
///
/// Unlike the evidence and lock digests, the index is deliberately byte-exact:
/// it answers "has anything I generated been regenerated?", not "did the
/// specification's structure change?". Input digests therefore hash raw
/// specification bytes, and `generatedManifestDigest` plus the generated-output
/// checks compare exact generated content. A retitling is a change to the
/// generated contract, so regeneration (and an index refresh) is required;
/// `zuke check` runs generation before validation for exactly that reason.
///
/// Keep this file free of `zuke_frontend` and `zuke_core` symbols that are not
/// in the published releases: the analysis-server plugin AOT-compiles it
/// through `package:zuke_cli/editor.dart`, and the plugin resolves those
/// packages from the pub cache rather than this workspace. That is why the
/// local `_sha256` below is not the shared `zuke_core` helper.
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

  /// Requirement IDs that already carry a workspace `@VerifiesRequirement`.
  /// Stale after test edits until `zuke generate` refreshes the index.
  final Set<String> verifiedRequirementIds;

  /// Requirement IDs claimed by `@ImplementsRequirement` or
  /// `@PresentsRequirement` in the configured package roots.
  ///
  /// This is what makes "declared but never implemented" visible to the editor
  /// rather than only to `zuke validate`. Stale after implementation edits
  /// until `zuke generate` refreshes the index.
  final Set<String> implementedRequirementIds;

  /// The subset of [implementedRequirementIds] claimed by
  /// `@PresentsRequirement`, kept separately so a caller can tell a UI
  /// presentation from a logic implementation.
  final Set<String> presentedRequirementIds;

  /// Control IDs claimed by `@ProvidesControl`.
  final Set<String> providedControlIds;

  /// Binding IDs claimed by `@ZukeBinding`.
  final Set<String> implementedBindingIds;

  /// Declared targets per requirement ID.
  ///
  /// The index is workspace-global but specifications declare `targets:`, so a
  /// requirement owned by `backend` must not be reported as unimplemented in a
  /// Flutter package that legitimately does not implement it. An ID absent from
  /// this map is not target-scoped and applies everywhere.
  final Map<String, List<String>> requirementTargets;

  /// Target ID per configured package path, both workspace-relative and
  /// forward-slashed.
  ///
  /// Lets the editor resolve which target owns the file being analyzed, which
  /// is what narrows [requirementTargets] to a single target.
  final Map<String, String> packageTargets;

  /// Specification findings recorded at generation time.
  ///
  /// Spec problems are found by the reference resolver, not the generator, but
  /// they are surfaced in the editor through the analyzer plugin, which only
  /// reads this index. Recording them here is what lets a `.feature` problem
  /// reach the editor at all. Empty when every reference resolves, which is the
  /// common case, so the index carries nothing for a healthy workspace.
  final List<ZukeSpecDiagnostic> specDiagnostics;

  /// Feature ID to the workspace-relative path of its generated contract file.
  ///
  /// Lets the editor put a specification finding on the file generated from the
  /// feature that owns it. Recorded by the generator rather than inferred from a
  /// file name, so it stays correct when a feature ID contains an underscore or
  /// collides after normalization.
  final Map<String, String> featureFiles;

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
    this.verifiedRequirementIds = const {},
    this.implementedRequirementIds = const {},
    this.presentedRequirementIds = const {},
    this.providedControlIds = const {},
    this.implementedBindingIds = const {},
    this.requirementTargets = const {},
    this.packageTargets = const {},
    this.specDiagnostics = const [],
    this.featureFiles = const {},
  });

  factory ZukeIndex.create({
    required String root,
    required Iterable<String> inputPaths,
    required String generatedManifestContent,
    required String generatedManifestPath,
    required Iterable<String> requirementIds,
    required Iterable<String> controlIds,
    required Iterable<String> bindingIds,
    Iterable<String> verifiedRequirementIds = const [],
    Iterable<String> implementedRequirementIds = const [],
    Iterable<String> presentedRequirementIds = const [],
    Iterable<String> providedControlIds = const [],
    Iterable<String> implementedBindingIds = const [],
    Map<String, List<String>> requirementTargets = const {},
    Map<String, String> packageTargets = const {},
    Iterable<ZukeSpecDiagnostic> specDiagnostics = const [],
    Map<String, String> featureFiles = const {},
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
    final verified = Set<String>.from(verifiedRequirementIds)
      ..removeWhere((id) => id.isEmpty);
    final implemented = Set<String>.from(implementedRequirementIds)
      ..removeWhere((id) => id.isEmpty);
    final presented = Set<String>.from(presentedRequirementIds)
      ..removeWhere((id) => id.isEmpty);
    final providedControls = Set<String>.from(providedControlIds)
      ..removeWhere((id) => id.isEmpty);
    final implementedBindings = Set<String>.from(implementedBindingIds)
      ..removeWhere((id) => id.isEmpty);
    final scopedTargets = _normalizedRequirementTargets(requirementTargets);
    final scopedPackages = _normalizedPackageTargets(packageTargets);
    final specs = _normalizedSpecDiagnostics(specDiagnostics);
    final featurePaths = _normalizedFeatureFiles(featureFiles);
    return ZukeIndex(
      inputDigest: _inputDigest(
        inputs,
        requirements,
        controls,
        bindings,
        verified,
        implemented,
        presented,
        providedControls,
        implementedBindings,
        scopedTargets,
        scopedPackages,
        specs,
        featurePaths,
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
      verifiedRequirementIds: Set.unmodifiable(verified),
      implementedRequirementIds: Set.unmodifiable(implemented),
      presentedRequirementIds: Set.unmodifiable(presented),
      providedControlIds: Set.unmodifiable(providedControls),
      implementedBindingIds: Set.unmodifiable(implementedBindings),
      requirementTargets: Map.unmodifiable(scopedTargets),
      packageTargets: Map.unmodifiable(scopedPackages),
      specDiagnostics: List.unmodifiable(specs),
      featureFiles: Map.unmodifiable(featurePaths),
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

    Set<String> optionalIds(String field) {
      if (!json.containsKey(field)) return const {};
      return ids(field);
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
      verifiedRequirementIds: optionalIds('verifiedRequirementIds'),
      implementedRequirementIds: optionalIds('implementedRequirementIds'),
      presentedRequirementIds: optionalIds('presentedRequirementIds'),
      providedControlIds: optionalIds('providedControlIds'),
      implementedBindingIds: optionalIds('implementedBindingIds'),
      requirementTargets: _requirementTargetsFromJson(json),
      packageTargets: _packageTargetsFromJson(json),
      specDiagnostics: _specDiagnosticsFromJson(json),
      featureFiles: _featureFilesFromJson(json),
    );
  }

  /// Target scoping, read leniently: an index written before target scoping
  /// existed simply has none, and an ID it does not mention is unscoped.
  ///
  /// Only the shape is coerced here; normalization is delegated to
  /// [_normalizedRequirementTargets] so a read index and a created one cannot
  /// disagree about what a key or a target name means.
  static Map<String, List<String>> _requirementTargetsFromJson(
    Map<Object?, Object?> json,
  ) {
    final value = json['requirementTargets'];
    if (value is! Map) return const {};
    final coerced = <String, List<String>>{};
    for (final entry in value.entries) {
      final id = entry.key;
      final targets = entry.value;
      if (id is! String || targets is! List) continue;
      coerced[id] = targets.whereType<String>().toList();
    }
    return _normalizedRequirementTargets(coerced);
  }

  /// Reads [packageTargets] leniently, coercing the shape only.
  ///
  /// Normalization is delegated to [_normalizedPackageTargets] so a read index
  /// and a created one cannot disagree about what a package path means.
  static Map<String, String> _packageTargetsFromJson(
    Map<Object?, Object?> json,
  ) {
    final value = json['packageTargets'];
    if (value is! Map) return const {};
    final coerced = <String, String>{};
    for (final entry in value.entries) {
      final path = entry.key;
      final target = entry.value;
      if (path is! String || target is! String) continue;
      coerced[path] = target;
    }
    return _normalizedPackageTargets(coerced);
  }

  /// Reads [specDiagnostics] leniently, skipping anything malformed.
  ///
  /// A finding that cannot be understood is dropped rather than failing the whole
  /// index: the other rules must keep working on a workspace whose spec findings
  /// were written by a different version.
  static List<ZukeSpecDiagnostic> _specDiagnosticsFromJson(
    Map<Object?, Object?> json,
  ) {
    final value = json['specDiagnostics'];
    if (value is! List) return const [];
    final parsed = <ZukeSpecDiagnostic>[];
    for (final entry in value.whereType<Map<Object?, Object?>>()) {
      final diagnostic = ZukeSpecDiagnostic.fromJson(entry);
      if (diagnostic != null) parsed.add(diagnostic);
    }
    return _normalizedSpecDiagnostics(parsed);
  }

  /// Reads [featureFiles] leniently, coercing the shape only.
  static Map<String, String> _featureFilesFromJson(Map<Object?, Object?> json) {
    final value = json['featureFiles'];
    if (value is! Map) return const {};
    final coerced = <String, String>{};
    for (final entry in value.entries) {
      final id = entry.key;
      final path = entry.value;
      if (id is! String || path is! String) continue;
      coerced[id] = path;
    }
    return _normalizedFeatureFiles(coerced);
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
    'verifiedRequirementIds': verifiedRequirementIds.toList()..sort(),
    'implementedRequirementIds': implementedRequirementIds.toList()..sort(),
    'presentedRequirementIds': presentedRequirementIds.toList()..sort(),
    'providedControlIds': providedControlIds.toList()..sort(),
    'implementedBindingIds': implementedBindingIds.toList()..sort(),
    'requirementTargets': {
      for (final id in requirementTargets.keys.toList()..sort())
        id: requirementTargets[id]!,
    },
    'packageTargets': {
      for (final path in packageTargets.keys.toList()..sort())
        path: packageTargets[path]!,
    },
    // Only written when non-empty, so a healthy workspace's index is unchanged
    // by the existence of these features.
    if (specDiagnostics.isNotEmpty)
      'specDiagnostics': [
        for (final diagnostic in specDiagnostics) diagnostic.toJson(),
      ],
    if (featureFiles.isNotEmpty)
      'featureFiles': {
        for (final id in featureFiles.keys.toList()..sort())
          id: featureFiles[id]!,
      },
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
              verifiedRequirementIds,
              implementedRequirementIds,
              presentedRequirementIds,
              providedControlIds,
              implementedBindingIds,
              requirementTargets,
              packageTargets,
              specDiagnostics,
              featureFiles,
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

  /// The target that owns [relativePath], or null when no configured package
  /// contains it.
  ///
  /// Longest matching package path wins, so a nested package (`apps/api`)
  /// resolves to its own target rather than the workspace root's. The
  /// comparison is case-insensitive because the same workspace is indexed from
  /// differently cased paths on Windows and macOS.
  String? targetForPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/').toLowerCase();
    String? best;
    String? bestTarget;
    for (final entry in packageTargets.entries) {
      final path = _normalizePackagePath(entry.key).toLowerCase();
      // A package declared at the workspace root owns every path in the
      // workspace, so it matches anything. It still loses to a longer nested
      // package path, which is what keeps a multi-package workspace resolving
      // `apps/api` to `backend` instead of the root's target.
      final matches =
          _isWorkspaceRootPackage(path) ||
          normalized == path ||
          normalized.startsWith(path.endsWith('/') ? path : '$path/');
      if (!matches) continue;
      if (best == null || path.length > best.length) {
        best = path;
        bestTarget = entry.value;
      }
    }
    return bestTarget;
  }

  /// Feature IDs whose generated contract file is [relativePath].
  ///
  /// Empty when the path was not produced by the generator, which is how the
  /// editor rule decides a file is a contract and therefore the right place to
  /// report a specification finding.
  Set<String> featuresAtPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return {
      for (final entry in featureFiles.entries)
        if (entry.value == normalized) entry.key,
    };
  }

  /// [absolutePath] expressed against [root], or null when it is not under it.
  ///
  /// Guards the slice. An absolute path that merely *starts with* the same
  /// characters — a sibling directory such as `/repo-other` — must not be sliced
  /// as if it were inside the workspace, because that yields a path that looks
  /// relative and silently attributes a file to the wrong target.
  ///
  /// The comparison folds case where the filesystem does. On Windows
  /// `C:\Repo` and `c:\repo` are the same directory, so refusing to match them
  /// would silently switch off every rule that depends on this — the failure
  /// looks like "no diagnostics configured", not "wrong case". macOS is left
  /// alone because its volumes can be either case-sensitive or not, and guessing
  /// wrong there would merge two genuinely different paths.
  ///
  /// The returned substring keeps the caller's original casing.
  static String? relativeToRoot(String root, String absolutePath) {
    var normalizedRoot = root.replaceAll('\\', '/');
    final normalizedPath = absolutePath.replaceAll('\\', '/');
    while (normalizedRoot.endsWith('/')) {
      normalizedRoot = normalizedRoot.substring(0, normalizedRoot.length - 1);
    }
    if (normalizedRoot.isEmpty) return null;
    final fold = Platform.isWindows
        ? (String value) => value.toLowerCase()
        : (String value) => value;
    final rootKey = fold(normalizedRoot);
    final pathKey = fold(normalizedPath);
    if (pathKey.length <= rootKey.length) return null;
    if (!pathKey.startsWith(rootKey)) return null;
    if (pathKey[rootKey.length] != '/') return null;
    return normalizedPath.substring(normalizedRoot.length + 1);
  }

  /// Whether [requirementId] is declared for [targetId].
  ///
  /// Delegates to [requirementAppliesTo] so the editor and the CLI cannot
  /// disagree about what "declared for this target" means.
  bool appliesToTarget(String requirementId, String? targetId) =>
      requirementAppliesTo(requirementTargets, requirementId, targetId);

  /// Declared requirement IDs that no configured source claims to implement,
  /// narrowed to those that apply to [targetId].
  Set<String> unimplementedRequirementIds(String? targetId) => {
    for (final id in requirementIds)
      if (!implementedRequirementIds.contains(id) &&
          appliesToTarget(id, targetId))
        id,
  };

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
        } else if (_digestHex(file.readAsBytesSync()) != contentHash) {
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

  /// Digest over every input and ID set the index publishes.
  ///
  /// The implementation sets and target maps participate so that adding,
  /// removing or re-targeting an implementation invalidates the index exactly
  /// like editing a test does. Without them the editor would keep reporting a
  /// requirement as unimplemented after the code that implements it was added.
  static String _inputDigest(
    List<ZukeIndexInput> inputs,
    Set<String> requirements,
    Set<String> controls,
    Set<String> bindings,
    Set<String> verifiedRequirements,
    Set<String> implementedRequirements,
    Set<String> presentedRequirements,
    Set<String> providedControls,
    Set<String> implementedBindings,
    Map<String, List<String>> requirementTargets,
    Map<String, String> packageTargets,
    List<ZukeSpecDiagnostic> specDiagnostics,
    Map<String, String> featureFiles,
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
        'verifiedRequirementIds': verifiedRequirements.toList()..sort(),
        'implementedRequirementIds': implementedRequirements.toList()..sort(),
        'presentedRequirementIds': presentedRequirements.toList()..sort(),
        'providedControlIds': providedControls.toList()..sort(),
        'implementedBindingIds': implementedBindings.toList()..sort(),
        'requirementTargets': {
          for (final id in requirementTargets.keys.toList()..sort())
            id: requirementTargets[id]!,
        },
        'packageTargets': {
          for (final path in packageTargets.keys.toList()..sort())
            path: packageTargets[path]!,
        },
        'specDiagnostics': [
          for (final diagnostic in specDiagnostics) diagnostic.toJson(),
        ],
      }),
    ),
  );
}

/// Target-scoped requirement IDs, with sorted, forward-slashed target names.
///
/// An ID whose target list is empty is dropped rather than stored as an empty
/// list, so "no declared targets" and "declared no targets" are the same thing
/// downstream: unscoped, and therefore reported everywhere.
Map<String, List<String>> _normalizedRequirementTargets(
  Map<String, List<String>> targets,
) {
  final result = <String, List<String>>{};
  for (final entry in targets.entries) {
    final id = entry.key.replaceAll('\\', '/').trim();
    if (id.isEmpty) continue;
    final values =
        entry.value
            .map((target) => target.replaceAll('\\', '/').trim())
            .where((target) => target.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (values.isEmpty) continue;
    result[id] = List.unmodifiable(values);
  }
  return result;
}

/// Whether [requirementId] applies to [targetId], given the [scopes] map that
/// records the targets each requirement ID declared.
///
/// The single definition of this rule, shared by the editor rule and the CLI
/// validator so the two cannot drift. A requirement that declared no targets is
/// unscoped and applies everywhere, and an unattributable [targetId] never
/// narrows: under-reporting an unimplemented requirement is recoverable, while
/// hiding one because scoping metadata was missing is not.
bool requirementAppliesTo(
  Map<String, List<String>> scopes,
  String requirementId,
  String? targetId,
) {
  final targets = scopes[requirementId];
  if (targets == null || targets.isEmpty) return true;
  if (targetId == null) return true;
  return targets.contains(targetId);
}

/// Package paths mapped to their target, normalized the same way
/// [ZukeIndexInput.path] is, so a caller can compare a relative path directly.
Map<String, String> _normalizedPackageTargets(Map<String, String> targets) {
  final result = <String, String>{};
  for (final entry in targets.entries) {
    final path = _normalizePackagePath(entry.key);
    if (path.isEmpty) continue;
    final target = entry.value.trim();
    if (target.isEmpty) continue;
    result[path] = target;
  }
  return result;
}

/// Normalizes a workspace-relative package path for comparison.
///
/// Forward-slashes, no surrounding whitespace, no leading `./` and no trailing
/// `/`. A path that reduces to nothing (`./`, `./.`) becomes `.`, which is how
/// a single-package workspace declares its only package in zuke.yaml.
String _normalizePackagePath(String path) {
  final trimmed = path.replaceAll('\\', '/').trim();
  if (trimmed.isEmpty) return '';
  var normalized = trimmed;
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.isEmpty ? '.' : normalized;
}

/// Whether [normalizedPath] denotes the workspace root rather than a directory
/// inside it.
///
/// A single-package workspace records its one package as `.`, and that package
/// owns the whole workspace. Matching `.` as a literal directory prefix would
/// match no path at all, and a file whose target cannot be attributed is
/// deliberately reported as *unscoped*, so the mistake does not look like a
/// miss, it looks like every requirement applying everywhere. That is how
/// `backend` requirements ended up reported in a Flutter app.
bool _isWorkspaceRootPackage(String normalizedPath) => normalizedPath == '.';

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

/// The bare hex form, for the per-file `contentHash` entries the manifest
/// stores; the `sha256:` form is for the aggregate index digests.
String _digestHex(List<int> bytes) => sha256.convert(bytes).toString();

String _sha256(List<int> bytes) => 'sha256:${_digestHex(bytes)}';

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
