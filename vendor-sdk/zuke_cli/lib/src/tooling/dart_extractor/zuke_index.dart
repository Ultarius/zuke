import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../implementation_claims.dart';
import '../../index_contract.dart';
import '../../path_safety.dart';
import '../../proof_engine/binding_coverage_engine.dart';

enum ZukeIndexFreshnessIssueKind {
  contractMismatch,
  generatedManifestMissing,
  generatedManifestDigestMismatch,
  generatedManifestMalformed,
  generatedOutputMissing,
  generatedOutputDigestMismatch,
  inputMissing,
  inputDigestMismatch,
  inputInventoryMismatch,
  sourceInventoryMismatch,
  inputSetDigestMismatch,
}

/// Which family of index facts a freshness issue invalidates.
///
/// An index holds two kinds of fact that drift independently. Requirement,
/// control and binding IDs come from the specifications, so editing Dart cannot
/// change them; verified claims and implementation sets come from source and
/// tests, so editing Dart invalidates exactly those. Reporting them separately is
/// what lets the rules that only consult specification facts keep running while
/// a workspace is being edited.
enum ZukeIndexFreshnessFacet {
  /// The index cannot answer correctly at all. No rule may consult it.
  everything,

  /// Only the specification-derived ID sets and spec findings are in question.
  specification,

  /// Only source-derived claims and implementation sets are in question.
  sources,

  /// The workspace still matches the index.
  none,
}

extension ZukeIndexFreshnessFacetOf on ZukeIndexFreshnessIssueKind {
  /// The facts this kind puts in question, for [path] within the workspace.
  ///
  /// [path] matters because a content change to an indexed input is a source
  /// drift when the input is Dart and a specification drift otherwise.
  ZukeIndexFreshnessFacet facetFor(String path) {
    if (rendersIndexUnusable) return ZukeIndexFreshnessFacet.everything;
    final isDart = path.toLowerCase().endsWith('.dart');
    return switch (this) {
      // The set of configured Dart sources moved.
      ZukeIndexFreshnessIssueKind.sourceInventoryMismatch =>
        ZukeIndexFreshnessFacet.sources,
      // The set of specification inputs moved: definitions, not source.
      ZukeIndexFreshnessIssueKind.inputInventoryMismatch =>
        ZukeIndexFreshnessFacet.specification,
      // Content of one input changed. Which family it belongs to decides.
      ZukeIndexFreshnessIssueKind.inputDigestMismatch ||
      ZukeIndexFreshnessIssueKind.inputMissing =>
        isDart
            ? ZukeIndexFreshnessFacet.sources
            : ZukeIndexFreshnessFacet.specification,
      _ => ZukeIndexFreshnessFacet.everything,
    };
  }
}

/// The freshness issues of one index, with the facts they collectively invalidate.
extension ZukeIndexFreshnessIssues on List<ZukeIndexFreshnessIssue> {
  /// The widest facet any issue here puts in question.
  ///
  /// A summary for display and for the coarse "is the index behind at all"
  /// question. Do not decide whether a particular fact may be consulted from
  /// this: the two facets drift independently, so a workspace with both a source
  /// and a specification edit is not described by any single value. Ask
  /// [specificationFresh] or [sourcesFresh], which are tracked separately.
  ZukeIndexFreshnessFacet get invalidates {
    var widest = ZukeIndexFreshnessFacet.none;
    for (final issue in this) {
      final facet = issue.kind.facetFor(issue.path);
      if (facet == ZukeIndexFreshnessFacet.everything) {
        return ZukeIndexFreshnessFacet.everything;
      }
      if (facet == ZukeIndexFreshnessFacet.specification) {
        widest = ZukeIndexFreshnessFacet.specification;
      } else if (facet == ZukeIndexFreshnessFacet.sources &&
          widest == ZukeIndexFreshnessFacet.none) {
        widest = ZukeIndexFreshnessFacet.sources;
      }
    }
    return widest;
  }

  /// Whether specification-derived facts are still safe to consult.
  ///
  /// False as soon as *any* issue touches the specification facet. Collapsing
  /// the two facets into one value made a source edit mask a simultaneous
  /// specification edit, so a stale ID set was still trusted.
  bool get specificationFresh {
    for (final issue in this) {
      final facet = issue.kind.facetFor(issue.path);
      if (facet == ZukeIndexFreshnessFacet.everything ||
          facet == ZukeIndexFreshnessFacet.specification) {
        return false;
      }
    }
    return true;
  }

  /// Whether source-derived facts are still safe to consult.
  bool get sourcesFresh {
    for (final issue in this) {
      final facet = issue.kind.facetFor(issue.path);
      if (facet == ZukeIndexFreshnessFacet.everything ||
          facet == ZukeIndexFreshnessFacet.sources) {
        return false;
      }
    }
    return true;
  }

  /// Which facts a consumer may consult right now.
  ///
  /// The one place this policy is expressed, shared by the analysis-server plugin
  /// and the standalone analyzer. They once derived it separately and drifted:
  /// the standalone path substituted empty ID sets and kept running the checks
  /// that read them, so a specification drift reported every annotation as
  /// unknown. [indexReadable] answers the separate question of whether the index
  /// could be parsed at all.
  ZukeIndexConsultableFacts consultableFacts({required bool indexReadable}) =>
      indexReadable
      ? ZukeIndexConsultableFacts(
          specification: specificationFresh,
          sources: sourcesFresh,
        )
      : const ZukeIndexConsultableFacts(specification: false, sources: false);
}

/// Which of the index's two independent fact families a check may read.
final class ZukeIndexConsultableFacts {
  const ZukeIndexConsultableFacts({
    required this.specification,
    required this.sources,
  });

  /// IDs and requirement targets, derived from the `.feature` files.
  final bool specification;

  /// Source claims and target scopes, derived from the Dart extractor.
  final bool sources;
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

  /// Whether this issue leaves the index unusable, rather than merely behind.
  ///
  /// The distinction is the difference between "you have not regenerated yet"
  /// and "this index cannot answer correctly". Drift is the ordinary state of a
  /// project being edited, so treating it as an error put a red squiggle on
  /// every open file for the whole of a normal editing session. An unusable
  /// index is different in kind: the plugin is being asked about facts it does
  /// not have, and no amount of editing fixes it.
  bool get rendersIndexUnusable => kind.rendersIndexUnusable;
}

/// Whether a freshness issue of this kind leaves the index unable to answer
/// correctly, as opposed to merely describing sources that moved on.
extension ZukeIndexFreshnessUsability on ZukeIndexFreshnessIssueKind {
  bool get rendersIndexUnusable => switch (this) {
    // The index itself cannot be trusted: wrong contract, missing or edited
    // manifest, a generated file that vanished or was tampered with, or a
    // digest that disagrees with the contents it claims to describe.
    ZukeIndexFreshnessIssueKind.contractMismatch ||
    ZukeIndexFreshnessIssueKind.generatedManifestMissing ||
    ZukeIndexFreshnessIssueKind.generatedManifestDigestMismatch ||
    ZukeIndexFreshnessIssueKind.generatedManifestMalformed ||
    ZukeIndexFreshnessIssueKind.generatedOutputMissing ||
    ZukeIndexFreshnessIssueKind.generatedOutputDigestMismatch ||
    ZukeIndexFreshnessIssueKind.inputSetDigestMismatch => true,
    // The index is a faithful snapshot; the workspace has simply moved past it.
    ZukeIndexFreshnessIssueKind.inputMissing ||
    ZukeIndexFreshnessIssueKind.inputDigestMismatch ||
    ZukeIndexFreshnessIssueKind.inputInventoryMismatch ||
    ZukeIndexFreshnessIssueKind.sourceInventoryMismatch => false,
  };
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
  String get key =>
      jsonEncode([code, file, line, column, message, featureId, severity]);

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

  /// Dart source roots included in implementation and verification scans.
  final List<String> sourceRoots;

  /// Workspace-relative Dart files discovered under [sourceRoots].
  ///
  /// This inventory is compared against current directory contents so adding a
  /// source file invalidates the index.
  final Set<String> sourcePaths;
  final Set<String> requirementIds;
  final Set<String> controlIds;
  final Set<String> bindingIds;

  /// Requirement IDs that already carry a workspace `@VerifiesRequirement`.
  /// Stale after test edits until `zuke generate` refreshes the index.
  ///
  /// The flat set, kept for the common question "is this requirement verified
  /// anywhere". It cannot answer "is it verified for the target I am", which is
  /// what [verifiedClaims] is for.
  final Set<String> verifiedRequirementIds;

  /// Each `@VerifiesRequirement`, with the target owning the test file.
  ///
  /// Verification is target-scoped for the same reason implementation is: a
  /// backend test does not verify a requirement for a Flutter target, so
  /// without this a Flutter package implementing a requirement that only the
  /// backend package tests is told it has no test, while `zuke validate` on the
  /// backend passes. The two have to agree, so both read these claims.
  ///
  /// Claims, not [verifiedRequirementIds], decide the target-aware question.
  /// The factories reconcile the two — a flat set with no claims is backfilled
  /// as unpinned — but a `const ZukeIndex(...)` built by hand bypasses that, so
  /// a hand-built index has to supply the claims itself.
  final List<ZukeImplementationClaim> verifiedClaims;

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

  /// Every implementation claim, with the target that made it.
  ///
  /// The authoritative record of coverage. [implementedRequirementIds] remains as
  /// a flat summary, but it cannot answer "is this implemented *for the target I
  /// am*?", which is the only question that matters once a requirement is
  /// target-scoped — so the decision reads these instead.
  final List<ZukeImplementationClaim> implementationClaims;

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

  /// Every managed test registration found under the configured roots.
  ///
  /// Recorded so the editor can answer the binding-coverage question without
  /// re-scanning the workspace: absence of a registration is a claim about the
  /// *whole* set, so a per-file analysis could not make it.
  ///
  /// The nullable fields are unknown, not absent, and are serialized as explicit
  /// nulls for that reason. A registration whose kinds could not be read may be
  /// exactly the one satisfying a declared slot, so an index that dropped or
  /// emptied it would convert `unverified` into a false `unbound`.
  final List<ManagedRegistrationFact> managedRegistrations;

  /// Managed registrations whose scenario argument resolved to no constant ID.
  ///
  /// Carried because a non-zero count makes *every* slot undecidable: any one of
  /// them may be the registration a slot needs. Omitting this count would let the
  /// editor report a confident gap that the CLI correctly refuses to decide.
  final int unresolvedManagedRegistrations;

  /// Every rule that declares evidence slots, with its scenarios and its real
  /// location in the `.feature` file.
  ///
  /// Specification-derived, and read here rather than from the features so the
  /// editor never has to hold a parsed specification.
  final List<EvidenceObligation> evidenceObligations;

  /// The runner scopes an adapter can be attributed through.
  ///
  /// Configuration-derived. A registration records no adapter, so which adapter
  /// runs it — and therefore whether a slot naming one can be decided at all —
  /// depends on these.
  final List<RunnerScopeFact> runnerScopes;

  final int? contractVersion;
  final String? diagnosticAnchor;

  const ZukeIndex({
    this.contractVersion = zukeIndexContract,
    this.diagnosticAnchor,
    required this.inputDigest,
    required this.generatedManifestDigest,
    required this.generatedManifestPath,
    required this.inputs,
    this.inputPatterns = const [],
    this.patternInputs = const {},
    this.sourceRoots = const [],
    this.sourcePaths = const {},
    required this.requirementIds,
    required this.controlIds,
    required this.bindingIds,
    this.verifiedRequirementIds = const {},
    this.verifiedClaims = const [],
    this.implementedRequirementIds = const {},
    this.presentedRequirementIds = const {},
    this.providedControlIds = const {},
    this.implementedBindingIds = const {},
    this.requirementTargets = const {},
    this.packageTargets = const {},
    this.specDiagnostics = const [],
    this.implementationClaims = const [],
    this.featureFiles = const {},
    this.managedRegistrations = const [],
    this.unresolvedManagedRegistrations = 0,
    this.evidenceObligations = const [],
    this.runnerScopes = const [],
  });

  factory ZukeIndex.create({
    String? diagnosticAnchor,
    required String root,
    required Iterable<String> inputPaths,
    required String generatedManifestContent,
    required String generatedManifestPath,
    required Iterable<String> requirementIds,
    required Iterable<String> controlIds,
    required Iterable<String> bindingIds,
    Iterable<String> verifiedRequirementIds = const [],
    Iterable<ZukeImplementationClaim> verifiedClaims = const {},
    Iterable<String> implementedRequirementIds = const [],
    Iterable<String> presentedRequirementIds = const [],
    Iterable<String> providedControlIds = const [],
    Iterable<String> implementedBindingIds = const [],
    Map<String, List<String>> requirementTargets = const {},
    Map<String, String> packageTargets = const {},
    Iterable<ZukeSpecDiagnostic> specDiagnostics = const [],
    Iterable<ZukeImplementationClaim> implementationClaims = const {},
    Map<String, String> featureFiles = const {},
    Iterable<ManagedRegistrationFact> managedRegistrations = const [],
    int unresolvedManagedRegistrations = 0,
    Iterable<EvidenceObligation> evidenceObligations = const [],
    Iterable<RunnerScopeFact> runnerScopes = const [],
    Iterable<String> inputPatterns = const [],
    Iterable<String> patternInputPaths = const [],
    Iterable<String> sourceRoots = const [],
    Iterable<String> sourcePaths = const [],
    Map<String, String>? inputContents,
    Map<String, String> pendingContents = const {},
  }) {
    late final String rootPath;
    try {
      rootPath = Directory(root).resolveSymbolicLinksSync();
    } catch (_) {
      rootPath = Directory(root).absolute.path;
    }
    // Content supplied instead of read from disk, keyed by normalized path.
    //
    // Two sources: the workspace's own parsed inputs, and the files this
    // generation is about to write. The latter matter because a first generation
    // has no contract on disk yet, and without them the contract would be dropped
    // from the inventory as unreadable — leaving an index that lists fewer inputs
    // than the very next run computes, and reports itself stale immediately.
    final suppliedContents = <String, String>{
      if (inputContents != null)
        for (final entry in inputContents.entries)
          _normalizedFsPath(entry.key): entry.value,
      for (final entry in pendingContents.entries)
        _normalizedFsPath(entry.key): entry.value,
    };
    // Keyed by the *recorded* path, because that is where two spellings of one
    // file collide. `inputPaths` is deduplicated as raw strings, so a caller
    // reaching the same file by two routes - an absolute path from discovery and
    // relative one built locally, say - contributes two entries that only become
    // equal once normalized here. Recording both put a duplicate in `inputs`, and
    // `inputDigest` hashes the list as given, so the committed index described an
    // input set the generator could not reliably reproduce. `zuke.yaml` reached
    // this way: it was already an input, and was named a second time.
    //
    // First occurrence wins. Two paths are equal here only after symlinks and the
    // root have been resolved, so they name the same file and cannot disagree
    // about its content.
    final inputsByPath = <String, ZukeIndexInput>{};
    for (final path in inputPaths) {
      String resolved;
      try {
        resolved = File(path).resolveSymbolicLinksSync();
      } catch (_) {
        resolved = File(path).absolute.path;
      }
      final exists =
          inputContents?.containsKey(resolved) == true ||
          suppliedContents.containsKey(_normalizedFsPath(resolved)) ||
          File(resolved).existsSync();
      if (!exists) continue;
      final relative = _relative(rootPath, resolved);
      if (inputsByPath.containsKey(relative)) continue;
      final cached = suppliedContents[_normalizedFsPath(resolved)];
      final bytes = cached != null
          ? utf8.encode(cached)
          : File(resolved).readAsBytesSync();
      inputsByPath[relative] = ZukeIndexInput(
        path: relative,
        digest: _sha256(bytes),
      );
    }
    final inputs = inputsByPath.values.toList()
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
    final normalizedSourceRoots = _normalizedRelativePaths(sourceRoots);
    final normalizedSourcePaths = sourcePaths
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
    final claims = normalizedImplementationClaims(implementationClaims);
    // Sorted so the digest is a function of the workspace's contents rather than
    // of the order a directory walk happened to produce. Two runs over an
    // unchanged workspace must agree byte for byte.
    final normalizedRegistrations = managedRegistrations.toList()
      ..sort((left, right) {
        final byPath = left.sourcePath.compareTo(right.sourcePath);
        return byPath != 0
            ? byPath
            : left.scenarioId.compareTo(right.scenarioId);
      });
    final normalizedObligations = evidenceObligations.toList()
      ..sort((left, right) {
        final byFeature = left.featureId.compareTo(right.featureId);
        return byFeature != 0 ? byFeature : left.ruleId.compareTo(right.ruleId);
      });
    final normalizedScopes = runnerScopes.toList()
      ..sort((left, right) {
        final byTarget = left.target.compareTo(right.target);
        return byTarget != 0
            ? byTarget
            : left.sourcePackage.compareTo(right.sourcePackage);
      });
    final reconciled = reconcileClaims(
      claims: claims,
      implementedRequirements: implemented,
      presentedRequirements: presented,
      providedControls: providedControls,
      implementedBindings: implementedBindings,
    );
    // Verification is reconciled against its own flat set, never the
    // implementation sets: a requirement can be verified without being
    // implemented here, and backfilling from implementation would invent a test.
    final reconciledVerified = reconcileClaims(
      claims: normalizedImplementationClaims(verifiedClaims),
      implementedRequirements: verified,
      presentedRequirements: const {},
      providedControls: const {},
      implementedBindings: const {},
    );
    return ZukeIndex(
      diagnosticAnchor: diagnosticAnchor,
      inputDigest: _inputDigest(
        diagnosticAnchor: diagnosticAnchor,
        inputs: inputs,
        requirements: requirements,
        controls: controls,
        bindings: bindings,
        verifiedRequirements: verified,
        verifiedClaims: reconciledVerified,
        implementedRequirements: implemented,
        presentedRequirements: presented,
        providedControls: providedControls,
        implementedBindings: implementedBindings,
        requirementTargets: scopedTargets,
        packageTargets: scopedPackages,
        specDiagnostics: specs,
        featureFiles: featurePaths,
        implementationClaims: reconciled,
        sourceRoots: normalizedSourceRoots,
        sourcePaths: normalizedSourcePaths,
        patterns: normalizedPatterns,
        matchedInputs: normalizedPatternInputs,
        managedRegistrations: normalizedRegistrations,
        unresolvedManagedRegistrations: unresolvedManagedRegistrations,
        evidenceObligations: normalizedObligations,
        runnerScopes: normalizedScopes,
      ),

      generatedManifestDigest: _sha256(utf8.encode(generatedManifestContent)),
      generatedManifestPath: _validatedRelativePath(generatedManifestPath),
      inputs: List.unmodifiable(inputs),
      inputPatterns: List.unmodifiable(normalizedPatterns),
      patternInputs: Set.unmodifiable(normalizedPatternInputs),
      sourceRoots: List.unmodifiable(normalizedSourceRoots),
      sourcePaths: Set.unmodifiable(normalizedSourcePaths),
      requirementIds: Set.unmodifiable(requirements),
      controlIds: Set.unmodifiable(controls),
      bindingIds: Set.unmodifiable(bindings),
      verifiedRequirementIds: Set.unmodifiable(verified),
      verifiedClaims: List.unmodifiable(reconciledVerified),
      implementedRequirementIds: Set.unmodifiable(implemented),
      presentedRequirementIds: Set.unmodifiable(presented),
      providedControlIds: Set.unmodifiable(providedControls),
      implementedBindingIds: Set.unmodifiable(implementedBindings),
      requirementTargets: Map.unmodifiable(scopedTargets),
      packageTargets: Map.unmodifiable(scopedPackages),
      specDiagnostics: List.unmodifiable(specs),
      featureFiles: Map.unmodifiable(featurePaths),
      implementationClaims: List.unmodifiable(reconciled),
      managedRegistrations: List.unmodifiable(normalizedRegistrations),
      unresolvedManagedRegistrations: unresolvedManagedRegistrations < 0
          ? 0
          : unresolvedManagedRegistrations,
      evidenceObligations: List.unmodifiable(normalizedObligations),
      runnerScopes: List.unmodifiable(normalizedScopes),
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
    // Read strictly, and required. A lenient read here would be the worst possible
    // failure for this check: defaulting an absent or unreadable registration to
    // "no registrations" would report a workspace as having a coverage gap it may
    // not have. Better to reject the index outright and let it regenerate.
    int requiredCount(String field) {
      final value = json[field];
      if (value is! int || value < 0) {
        throw FormatException(
          'Analyzer index $field must be a non-negative integer',
        );
      }
      return value;
    }

    List<T> requiredFacts<T>(
      String field,
      T? Function(Map<Object?, Object?> entry) parse,
    ) {
      final value = json[field];
      if (value is! List) {
        throw FormatException('Analyzer index $field must be a list');
      }
      final parsed = <T>[];
      for (final entry in value) {
        if (entry is! Map) {
          throw FormatException('Analyzer index $field has a malformed entry');
        }
        final fact = parse(entry);
        if (fact == null) {
          throw FormatException(
            'Analyzer index $field has an entry this version cannot read',
          );
        }
        parsed.add(fact);
      }
      return List.unmodifiable(parsed);
    }

    return ZukeIndex(
      contractVersion: ZukeIndexHeader(json).contractVersion,
      diagnosticAnchor: json['diagnosticAnchor'] is String
          ? _validatedRelativePath(json['diagnosticAnchor'] as String)
          : null,
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
      sourceRoots: List.unmodifiable(
        _normalizedRelativePaths(_optionalPathList(json, 'sourceRoots')),
      ),
      sourcePaths: Set.unmodifiable(
        _optionalPathList(json, 'sourcePaths').map(_validatedRelativePath),
      ),
      requirementIds: ids('requirementIds'),
      controlIds: ids('controlIds'),
      bindingIds: ids('bindingIds'),
      verifiedRequirementIds: optionalIds('verifiedRequirementIds'),
      verifiedClaims: reconcileClaims(
        claims: claimsFromJson(json, 'verifiedClaims'),
        implementedRequirements: optionalIds('verifiedRequirementIds'),
        presentedRequirements: const {},
        providedControls: const {},
        implementedBindings: const {},
      ),
      implementedRequirementIds: optionalIds('implementedRequirementIds'),
      presentedRequirementIds: optionalIds('presentedRequirementIds'),
      providedControlIds: optionalIds('providedControlIds'),
      implementedBindingIds: optionalIds('implementedBindingIds'),
      requirementTargets: _requirementTargetsFromJson(json),
      packageTargets: _packageTargetsFromJson(json),
      specDiagnostics: _specDiagnosticsFromJson(json),
      featureFiles: _featureFilesFromJson(json),
      implementationClaims: reconcileClaims(
        claims: claimsFromJson(json, 'implementationClaims'),
        implementedRequirements: optionalIds('implementedRequirementIds'),
        presentedRequirements: optionalIds('presentedRequirementIds'),
        providedControls: optionalIds('providedControlIds'),
        implementedBindings: optionalIds('implementedBindingIds'),
      ),
      managedRegistrations: requiredFacts(
        'managedRegistrations',
        ManagedRegistrationFact.fromJson,
      ),
      unresolvedManagedRegistrations: requiredCount(
        'unresolvedManagedRegistrations',
      ),
      evidenceObligations: requiredFacts(
        'evidenceObligations',
        EvidenceObligation.fromJson,
      ),
      runnerScopes: requiredFacts('runnerScopes', RunnerScopeFact.fromJson),
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
    if (contractVersion != null) 'contractVersion': contractVersion,
    if (diagnosticAnchor != null) 'diagnosticAnchor': diagnosticAnchor,
    'inputDigest': inputDigest,
    'generatedManifestDigest': generatedManifestDigest,
    'generatedManifestPath': generatedManifestPath,
    'inputs': inputs.map((input) => input.toJson()).toList(),
    'inputPatterns': inputPatterns,
    'patternInputs': patternInputs.toList()..sort(),
    if (sourceRoots.isNotEmpty) 'sourceRoots': sourceRoots,
    if (sourcePaths.isNotEmpty) 'sourcePaths': sourcePaths.toList()..sort(),
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
    if (implementationClaims.isNotEmpty)
      'implementationClaims': [
        for (final claim in implementationClaims) claim.toJson(),
      ],
    if (verifiedClaims.isNotEmpty)
      'verifiedClaims': [for (final claim in verifiedClaims) claim.toJson()],
    if (featureFiles.isNotEmpty)
      'featureFiles': {
        for (final id in featureFiles.keys.toList()..sort())
          id: featureFiles[id]!,
      },
    // Always written, even when empty. `managedRegistrations: []` and a missing
    // key mean the same thing to this producer, but only the explicit form lets
    // the reader insist it is looking at a complete set rather than guessing.
    'managedRegistrations': [
      for (final registration in managedRegistrations) registration.toJson(),
    ],
    'unresolvedManagedRegistrations': unresolvedManagedRegistrations,
    'evidenceObligations': [
      for (final obligation in evidenceObligations) obligation.toJson(),
    ],
    'runnerScopes': [for (final scope in runnerScopes) scope.toJson()],
  };

  bool isCurrent({required String root}) => freshnessIssues(root: root).isEmpty;

  List<ZukeIndexFreshnessIssue> freshnessIssues({required String root}) {
    if (contractVersion != zukeIndexContract) {
      return [
        ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.contractMismatch,
          path: '.zuke/analyzer-index.json',
          message:
              'Analyzer index contract is missing or incompatible; run zuke generate.',
        ),
      ];
    }
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
    final currentSourcePaths = _currentSourcePaths(
      rootPath,
      sourceRoots,
      _generatedPathsFromManifest(generatedManifest),
    );
    final currentSourceKeys = currentSourcePaths.map(pathComparisonKey).toSet();
    final indexedSourceKeys = sourcePaths.map(pathComparisonKey).toSet();
    if (!_sameSet(currentSourceKeys, indexedSourceKeys)) {
      final changed =
          <String>{...currentSourcePaths, ...sourcePaths}
              .where(
                (path) =>
                    !currentSourceKeys.contains(pathComparisonKey(path)) ||
                    !indexedSourceKeys.contains(pathComparisonKey(path)),
              )
              .toList()
            ..sort();
      issues.add(
        ZukeIndexFreshnessIssue(
          kind: ZukeIndexFreshnessIssueKind.sourceInventoryMismatch,
          path: changed.isEmpty ? '.zuke/analyzer-index.json' : changed.first,
          message:
              'Configured Dart source files changed: '
              '${changed.isEmpty ? '.zuke/analyzer-index.json' : changed.join(', ')}',
        ),
      );
    }
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
          issue.kind == ZukeIndexFreshnessIssueKind.inputInventoryMismatch ||
          issue.kind == ZukeIndexFreshnessIssueKind.sourceInventoryMismatch,
    );
    if (!hasInputIssue &&
        _inputDigest(
              diagnosticAnchor: diagnosticAnchor,
              inputs: current,
              requirements: requirementIds,
              controls: controlIds,
              bindings: bindingIds,
              verifiedRequirements: verifiedRequirementIds,
              verifiedClaims: verifiedClaims,
              implementedRequirements: implementedRequirementIds,
              presentedRequirements: presentedRequirementIds,
              providedControls: providedControlIds,
              implementedBindings: implementedBindingIds,
              requirementTargets: requirementTargets,
              packageTargets: packageTargets,
              specDiagnostics: specDiagnostics,
              featureFiles: featureFiles,
              implementationClaims: implementationClaims,
              sourceRoots: sourceRoots,
              sourcePaths: sourcePaths,
              patterns: inputPatterns,
              matchedInputs: patternInputs,
              // Recomputed from the stored facts, so an index whose
              // registrations were edited by hand no longer matches its own
              // digest and is reported unusable rather than believed.
              managedRegistrations: managedRegistrations,
              unresolvedManagedRegistrations: unresolvedManagedRegistrations,
              evidenceObligations: evidenceObligations,
              runnerScopes: runnerScopes,
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
  /// Delegates to [targetForWorkspacePath] so the index and the implementation
  /// scan, which must attribute a claim to the same target the index later
  /// judges it by, cannot drift apart.
  String? targetForPath(String relativePath) =>
      targetForWorkspacePath(packageTargets, relativePath);

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
    final normalizedRoot = _withoutTrailingSeparators(
      root.replaceAll('\\', '/'),
    );
    final normalizedPath = absolutePath.replaceAll('\\', '/');
    if (normalizedRoot.isEmpty) return null;
    final direct = _relativeUnder(normalizedRoot, normalizedPath);
    if (direct != null) return direct;

    // The literal comparison failed, which usually means the root is spelled
    // differently from the canonical filesystem path: macOS reports its temp
    // directory as `/var/...` while everything under it resolves to
    // `/private/var/...`, and Windows hands out 8.3 aliases such as `RUNNER~1`
    // for a long user directory. Both are the same directory, so the path is not
    // outside the workspace and the diagnostic must not be dropped -- doing so
    // silently removed every spec finding on those platforms. Retry against the
    // resolved form before concluding the path is unrelated.
    //
    // Only when both sides agree about which volume they name. Resolving a path
    // makes it absolute, and on Windows that attaches the current drive to a
    // rooted-but-driveless spelling, so `/repo` would start matching
    // `C:/repo/...` -- a different volume under the caller's reading.
    if (Platform.isWindows &&
        _hasDrive(normalizedRoot) != _hasDrive(normalizedPath)) {
      return null;
    }
    final canonicalRoot = _withoutTrailingSeparators(
      canonicalComparablePath(normalizedRoot).replaceAll('\\', '/'),
    );
    if (canonicalRoot.isEmpty || canonicalRoot == normalizedRoot) return null;
    final canonicalPath = canonicalComparablePath(
      normalizedPath,
    ).replaceAll('\\', '/');
    return _relativeUnder(canonicalRoot, canonicalPath);
  }

  /// Whether [path] names a Windows volume, as in `C:/repo`.
  static bool _hasDrive(String path) =>
      path.length >= 2 && path[1] == ':' && RegExp(r'^[A-Za-z]').hasMatch(path);

  static String _withoutTrailingSeparators(String path) {
    var result = path;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// The part of [absolutePath] below [root], or null when it is not strictly
  /// inside it.
  static String? _relativeUnder(String root, String absolutePath) {
    final fold = Platform.isWindows
        ? (String value) => value.toLowerCase()
        : (String value) => value;
    final rootKey = fold(root);
    final pathKey = fold(absolutePath);
    if (pathKey.length <= rootKey.length) return null;
    if (!pathKey.startsWith(rootKey)) return null;
    if (pathKey[rootKey.length] != '/') return null;
    return absolutePath.substring(root.length + 1);
  }

  /// Whether [requirementId] is declared for [targetId].
  ///
  /// Delegates to [requirementAppliesTo] so the editor and the CLI cannot
  /// disagree about what "declared for this target" means.
  bool appliesToTarget(String requirementId, String? targetId) =>
      requirementAppliesTo(requirementTargets, requirementId, targetId);

  /// Declared requirement IDs that no configured source claims to implement for
  /// [targetId], narrowed to those that apply to it.
  ///
  /// A claim made for a *different* target does not count: a Flutter package
  /// claiming a `backend`-only requirement has not implemented it, and reporting
  /// otherwise is exactly the false negative target scoping exists to prevent.
  Set<String> unimplementedRequirementIds(String? targetId) => {
    for (final id in requirementIds)
      if (!claimsSatisfyRequirement(implementationClaims, id, targetId) &&
          appliesToTarget(id, targetId))
        id,
  };

  Set<String> _generatedPathsFromManifest(File manifest) {
    try {
      final decoded = jsonDecode(manifest.readAsStringSync());
      if (decoded is! Map || decoded['files'] is! List) return const {};
      return {
        for (final entry in decoded['files'] as List)
          if (entry is Map && entry['path'] is String)
            _validatedRelativePath(entry['path'] as String),
      };
    } on FormatException {
      return const {};
    }
  }

  Set<String> _currentSourcePaths(
    String root,
    List<String> roots,
    Set<String> generatedPaths,
  ) {
    final generated = generatedPaths.map(pathComparisonKey).toSet();
    final found = <String>{};
    for (final sourceRoot in roots) {
      final directory = Directory(_join(root, sourceRoot));
      if (!directory.existsSync()) continue;
      try {
        for (final entity in directory.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final relative = _relative(root, entity.path);
          final normalized = relative.replaceAll('\\', '/');
          if (isGuideSnippetFixture(normalized)) continue;
          if (generated.contains(pathComparisonKey(normalized))) continue;
          found.add(normalized);
        }
      } on FileSystemException {
        // An unreadable root will also make its indexed inputs missing below.
      }
    }
    return found;
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
  static String _inputDigest({
    required String? diagnosticAnchor,
    required List<ZukeIndexInput> inputs,
    required Set<String> requirements,
    required Set<String> controls,
    required Set<String> bindings,
    required Set<String> verifiedRequirements,
    required List<ZukeImplementationClaim> verifiedClaims,
    required Set<String> implementedRequirements,
    required Set<String> presentedRequirements,
    required Set<String> providedControls,
    required Set<String> implementedBindings,
    required Map<String, List<String>> requirementTargets,
    required Map<String, String> packageTargets,
    required List<ZukeSpecDiagnostic> specDiagnostics,
    required Map<String, String> featureFiles,
    required List<ZukeImplementationClaim> implementationClaims,
    required List<String> sourceRoots,
    required Set<String> sourcePaths,
    required List<String> patterns,
    required Set<String> matchedInputs,
    required List<ManagedRegistrationFact> managedRegistrations,
    required int unresolvedManagedRegistrations,
    required List<EvidenceObligation> evidenceObligations,
    required List<RunnerScopeFact> runnerScopes,
  }) => _sha256(
    utf8.encode(
      _canonicalJson({
        'kind': kind,
        'contractVersion': zukeIndexContract,
        'diagnosticAnchor': ?diagnosticAnchor,
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
        'verifiedClaims': [for (final claim in verifiedClaims) claim.toJson()],
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
        'featureFiles': {
          for (final id in featureFiles.keys.toList()..sort())
            id: featureFiles[id]!,
        },
        'implementationClaims': [
          for (final claim in implementationClaims) claim.toJson(),
        ],
        'sourceRoots': sourceRoots,
        'sourcePaths': sourcePaths.toList()..sort(),
        // The binding-coverage facts participate in the digest for the same
        // reason the implementation sets do: adding or removing a registration,
        // or changing the obligations it is matched against, has to invalidate
        // the index, or the editor keeps reporting a gap that was just closed.
        'managedRegistrations': [
          for (final registration in managedRegistrations)
            registration.toJson(),
        ],
        'unresolvedManagedRegistrations': unresolvedManagedRegistrations,
        'evidenceObligations': [
          for (final obligation in evidenceObligations) obligation.toJson(),
        ],
        'runnerScopes': [for (final scope in runnerScopes) scope.toJson()],
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
  final owners = <String, String>{};
  for (final entry in targets.entries) {
    final path = normalizePackagePath(entry.key);
    if (path.isEmpty) continue;
    final target = entry.value.trim();
    if (target.isEmpty) continue;
    final key = pathComparisonKey(path);
    final previous = owners[key];
    if (previous != null && previous != target) {
      throw FormatException(
        'Conflicting package owners for path "$path": "$previous" and "$target"',
      );
    }
    owners[key] = target;
    result[path] = target;
  }
  return result;
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
  // Both spellings of the root have to be recognised. `resolvedRoot` is what the
  // filesystem says, but the walk below yields paths built from the spelling that
  // was *passed in*, and the two differ whenever the root is itself an alias --
  // macOS reports its temp directory as `/var/...` while it resolves to
  // `/private/var/...`, and Windows CI hands out 8.3 aliases such as `RUNNER~1`.
  // Comparing the walk against the resolved root alone silently matched nothing,
  // so every specification input looked deleted and a freshly generated index
  // reported itself stale. Keyed case-folded for the comparison, kept verbatim
  // for slicing the relative path out.
  final candidateRoots = <String>{
    resolvedRoot.replaceAll('\\', '/'),
    root.replaceAll('\\', '/'),
  }.where((candidate) => candidate != '/').toList();
  if (candidateRoots.isEmpty) return const {};
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
      String? owner;
      for (final candidate in candidateRoots) {
        final prefix = candidate.toLowerCase();
        if (canonical == prefix || canonical.startsWith('$prefix/')) {
          owner = candidate;
          break;
        }
      }
      if (owner == null) continue;
      final relative = _relative(owner, physical);
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

/// A filesystem path reduced to forward slashes, without case folding.
///
/// Distinct from [pathComparisonKey]: this one keys pending content handed in by the
/// generator, where the caller spells the path its own way and only the
/// separator has to agree. Case is left alone so a path cannot collide with a
/// differently cased file on a case-sensitive filesystem.
String _normalizedFsPath(String path) => path.replaceAll('\\', '/');

List<String> _normalizedRelativePaths(Iterable<String> paths) {
  final normalized = <String>{};
  for (final raw in paths) {
    final trimmed = raw.trim();
    // An empty path means the workspace root, which a single-package workspace
    // records as `.`, so it is mapped rather than rejected.
    if (trimmed.isEmpty) {
      normalized.add('.');
      continue;
    }
    // Validated before normalizing, not after: `normalizeRelativePath` strips a
    // leading `/`, so normalizing first would turn an absolute path into an
    // accepted relative one and quietly defeat this check.
    _validatedRelativePath(trimmed);
    normalized.add(normalizeRelativePath(trimmed));
  }
  return normalized.toList()..sort();
}

List<String> _optionalPathList(Map<Object?, Object?> json, String field) {
  final value = json[field];
  if (value == null) return const [];
  if (value is! List || value.any((entry) => entry is! String)) {
    throw FormatException('Analyzer index $field must be a list of paths');
  }
  return value.cast<String>().map(_validatedRelativePath).toList();
}

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
