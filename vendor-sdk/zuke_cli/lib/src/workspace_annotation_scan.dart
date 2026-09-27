import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:zuke_frontend/zuke_frontend.dart';

import 'annotation_claim.dart';
import 'requirement_scopes.dart';
import 'tooling/analyzer_sdk.dart';
import 'tooling/inspection.dart';
import 'tooling/source_files.dart';

/// One resolved scan shared by implementation and verification projections.
final class WorkspaceAnnotationScan {
  final String root;
  final List<ImplementationClaim> claims;

  /// Dart files under configured roots, excluding manifest-owned outputs.
  /// Includes files with no annotations to detect source inventory changes.
  final List<String> sourcePaths;

  /// Source files and workspace-local imported dependencies whose contents
  /// affect constant resolution, excluding manifest-owned generated outputs.
  final List<String> inputPaths;

  const WorkspaceAnnotationScan({
    required this.root,
    required this.claims,
    required this.sourcePaths,
    required this.inputPaths,
  });

  List<String> contributingPaths(Iterable<ImplementationClaim> selected) =>
      {for (final claim in selected) p.join(root, claim.sourcePath)}.toList()
        ..sort();
}

/// Resolves each source unit once and visits all supported annotation kinds
/// together. Dart's element model handles imports, prefixes, re-exports, parts,
/// aliases and class scope; there is no workspace-global name fallback.
Future<WorkspaceAnnotationScan> scanWorkspaceAnnotations(
  String root,
  WorkspaceDiscoveryResult workspace, {
  Map<String, String> pendingContent = const {},
  Set<String> generatedPaths = const {},
}) async {
  root = p.normalize(Directory(root).absolute.path);
  String normalize(String path) => p.normalize(File(path).absolute.path);
  final pending = {
    for (final entry in pendingContent.entries)
      normalize(entry.key): entry.value,
  };
  final generated = {...generatedPaths.map(normalize), ...pending.keys};
  final sources = packageDartFiles(
    root,
    workspace,
    pendingContent: pending,
  ).where((file) => !generated.contains(file.path)).toList();
  final sourcePaths = sources.map((file) => file.path).toList();
  final inputs = sourcePaths.toSet();
  final claims = <ImplementationClaim>[];
  if (sources.isEmpty) {
    return WorkspaceAnnotationScan(
      root: root,
      claims: claims,
      sourcePaths: sourcePaths,
      inputPaths: sourcePaths,
    );
  }

  final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  // A previous output scheduled for deletion must not supply stale constants.
  for (final path in generated) {
    provider.setOverlay(
      path,
      content: pending[path] ?? '',
      modificationStamp: 1,
    );
  }
  // Passing individual source paths also includes configured files that an
  // editor's analysis_options excludes, while retaining each package's context.
  final collection = AnalysisContextCollection(
    includedPaths: sourcePaths,
    resourceProvider: provider,
    sdkPath: resolveAnalyzerSdkPath(),
  );
  final packageTargets = workspacePackageTargets(workspace);
  final visitedLibraries = <LibraryElement>{};
  void recordDependencies(LibraryElement library) {
    if (library.isInSdk || !visitedLibraries.add(library)) return;
    for (final fragment in library.fragments) {
      final path = normalize(fragment.source.fullName);
      // External package inputs belong to their package/lock lifecycle. Index
      // paths are workspace-relative and must never escape the workspace.
      if (!p.isWithin(root, path)) continue;
      if (!generated.contains(path) && File(path).existsSync()) {
        inputs.add(path);
      }
      for (final imported in fragment.importedLibraries) {
        recordDependencies(imported);
      }
      for (final exported in fragment.libraryExports) {
        final dependency = exported.exportedLibrary;
        if (dependency != null) recordDependencies(dependency);
      }
    }
  }

  try {
    for (final file in sources) {
      if (isGeneratedSource(file)) continue;
      final result = await collection
          .contextFor(file.path)
          .currentSession
          .getResolvedUnit(file.path);
      if (result is! ResolvedUnitResult) {
        // Reported, not skipped. A source the resolver cannot read is exactly
        // the source whose annotations are unknown, and silently dropping it
        // would erase its claims and make implemented requirements look
        // unimplemented — the one failure the user cannot see.
        throw StateError('Could not resolve annotation source: ${file.path}');
      }
      recordDependencies(result.libraryElement);
      final sourcePath = p
          .relative(file.path, from: root)
          .replaceAll('\\', '/');
      result.unit.accept(
        _ClaimCollector(
          sourcePath,
          targetForWorkspacePath(packageTargets, sourcePath),
          claims,
        ),
      );
    }
  } finally {
    await collection.dispose();
  }
  return WorkspaceAnnotationScan(
    root: root,
    claims: List.unmodifiable(claims),
    sourcePaths: List.unmodifiable(sourcePaths),
    inputPaths: List.unmodifiable(inputs.toList()..sort()),
  );
}

/// The constant field a supported annotation fills, and the kind of claim it
/// makes from it.
final class _ClaimDescriptor {
  final ImplementationKind kind;
  final String field;

  const _ClaimDescriptor(this.kind, this.field);
}

/// Deduplication key for a claim: the same kind and ID from the same file is
/// one claim, however many annotations or constants it was spelled in.
final class _ClaimKey {
  final ImplementationKind kind;
  final String id;

  const _ClaimKey(this.kind, this.id);

  @override
  bool operator ==(Object other) =>
      other is _ClaimKey && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class _ClaimCollector extends RecursiveAstVisitor<void> {
  _ClaimCollector(this.sourcePath, this.target, this.claims);

  /// The constant field an annotation fills, paired with the kind of claim it
  /// makes.
  ///
  /// A named type rather than a record: the pair is a real concept in this
  /// file — it decides both what is read off the annotation and how the claim
  /// is categorised — and naming it keeps the switch below readable and gives
  /// the deduplication set something to be made of.
  static const _descriptors = <String, _ClaimDescriptor>{
    'ImplementsRequirement': _ClaimDescriptor(
      ImplementationKind.implemented,
      'requirementIds',
    ),
    'PresentsRequirement': _ClaimDescriptor(
      ImplementationKind.presented,
      'requirementIds',
    ),
    'VerifiesRequirement': _ClaimDescriptor(
      ImplementationKind.verified,
      'requirementIds',
    ),
    'ProvidesControl': _ClaimDescriptor(
      ImplementationKind.control,
      'controlIds',
    ),
    'ZukeBinding': _ClaimDescriptor(ImplementationKind.binding, 'bindingId'),
  };

  final String sourcePath;
  final String? target;
  final List<ImplementationClaim> claims;
  final Set<_ClaimKey> _seen = {};

  @override
  void visitAnnotation(Annotation node) {
    final annotation = node.elementAnnotation;
    final annotationName = zukeAnnotationName(annotation?.element);
    final declarationKind = switch (node.parent) {
      ClassDeclaration() => 'class',
      MixinDeclaration() => 'mixin',
      ExtensionTypeDeclaration() => 'extensionType',
      MethodDeclaration(isGetter: true) ||
      FunctionDeclaration(isGetter: true) => 'getter',
      MethodDeclaration() => 'method',
      FunctionDeclaration() => 'function',
      FieldDeclaration() => 'field',
      _ => '',
    };
    if (annotationName == null ||
        !supportsZukeAnnotationTarget(annotationName, declarationKind)) {
      return;
    }
    final descriptor = _descriptors[annotationName];
    if (descriptor == null) return;
    final value = annotation!.computeConstantValue();
    if (value == null || !value.hasKnownValue) return;
    final kind = descriptor.kind;
    final field = descriptor.field;
    final ids = kind == ImplementationKind.binding
        ? [if (constantString(value, field) case final String id) id]
        : constantStrings(value, field) ?? const <String>[];
    for (final id in ids) {
      if (id.isEmpty || !_seen.add(_ClaimKey(kind, id))) continue;
      claims.add(
        ImplementationClaim(
          kind: kind,
          id: id,
          sourcePath: sourcePath,
          target: target,
        ),
      );
    }
  }
}
