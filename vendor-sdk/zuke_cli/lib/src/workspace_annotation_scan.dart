import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
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

/// One scenario named by a managed test registration in resolved source.
///
/// Managed registrations (`zukeTest`, `zukeTestWidgets`, `zukeUnit`, and
/// evidence-harness cases) are what make `zuke test` execute a scenario. A
/// declared scenario that no registration names is never executed, which is the
/// fact scenario-coverage diagnostics report.
final class ManagedScenarioClaim {
  final String scenarioId;
  final String sourcePath;
  final String? target;

  const ManagedScenarioClaim({
    required this.scenarioId,
    required this.sourcePath,
    this.target,
  });
}

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

  /// Scenarios named by managed test registrations.
  final List<ManagedScenarioClaim> managedScenarios;

  /// Managed registrations whose `scenario`/`scenarios` argument could not be
  /// resolved to constant scenario IDs.
  ///
  /// Scenario coverage must not guess: an unresolved registration could be
  /// exactly the one that covers a scenario, so a caller reporting gaps has to
  /// treat a non-zero count as "unknown", not "uncovered".
  final int unresolvedManagedRegistrations;

  const WorkspaceAnnotationScan({
    required this.root,
    required this.claims,
    required this.sourcePaths,
    required this.inputPaths,
    this.managedScenarios = const [],
    this.unresolvedManagedRegistrations = 0,
  });

  /// Scenario IDs named by at least one managed registration.
  Set<String> get managedScenarioIds => {
    for (final claim in managedScenarios) claim.scenarioId,
  };

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
  final managedScenarios = <ManagedScenarioClaim>[];
  final seenManagedScenarios = <String>{};
  final unresolved = _UnresolvedRegistrations();
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
          managedScenarios,
          seenManagedScenarios,
          unresolved,
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
    managedScenarios: List.unmodifiable(managedScenarios),
    unresolvedManagedRegistrations: unresolved.count,
  );
}

/// Mutable counter shared by the per-file collectors of one scan.
final class _UnresolvedRegistrations {
  int count = 0;
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
  _ClaimCollector(
    this.sourcePath,
    this.target,
    this.claims,
    this.managedScenarios,
    this.seenManagedScenarios,
    this.unresolved,
  );

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
  final List<ManagedScenarioClaim> managedScenarios;

  /// Scenario IDs already collected in this scan, so one scenario registered
  /// through several call sites or harness cases is one claim.
  final Set<String> seenManagedScenarios;
  final _UnresolvedRegistrations unresolved;
  final Set<_ClaimKey> _seen = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (zukeManagedEntrypointName(node.methodName.element) != null) {
      _recordScenarioArgument(node.argumentList.arguments, 'scenario');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final scenarioArgument = flutterHarnessScenarioArgument(node);
    if (scenarioArgument != null) {
      _recordScenarioArgument(node.argumentList.arguments, scenarioArgument);
    }
    super.visitInstanceCreationExpression(node);
  }

  /// Records every constant scenario ID reachable from a named argument.
  ///
  /// The argument is either a single scenario contract (`scenario:`) or an
  /// iterable of them (`scenarios:`). A list literal, an `X.all` constant, or an
  /// enum `.values` list all evaluate to a constant list of objects carrying an
  /// `id`; anything else is counted as unresolved rather than guessed at.
  void _recordScenarioArgument(Iterable<AstNode> arguments, String name) {
    final expression = namedArgumentValue(arguments, name);
    if (expression == null || !_registerScenarioExpression(expression)) {
      // A registration that names no scenario is unresolved, not coverage.
      unresolved.count += 1;
    }
  }

  bool _registerScenarioExpression(Expression expression) {
    if (expression is ListLiteral) {
      var any = false;
      for (final element in expression.childEntities.whereType<Expression>()) {
        if (_registerScenarioExpression(element)) any = true;
      }
      return any;
    }
    // A bare identifier is not a child of itself: `scenario: fake` is a
    // `SimpleIdentifier` with no child entities, while `scenario: Foo.bar`
    // exposes both names as children. Handle both shapes.
    final Element? member;
    if (expression is SimpleIdentifier) {
      member = expression.element;
    } else {
      final identifiers = expression.childEntities
          .whereType<SimpleIdentifier>()
          .toList();
      member = identifiers.isEmpty ? null : identifiers.last.element;
    }
    if (member == null) return false;
    final value = _constantValueOf(member);
    if (value == null) return false;
    final items = value.toListValue();
    if (items != null) {
      var any = false;
      for (final item in items) {
        if (_registerScenarioId(_scenarioIdOf(item))) any = true;
      }
      return any;
    }
    return _registerScenarioId(_scenarioIdOf(value));
  }

  bool _registerScenarioId(String? scenarioId) {
    if (scenarioId == null) return false;
    if (!seenManagedScenarios.add(scenarioId)) return true;
    managedScenarios.add(
      ManagedScenarioClaim(
        scenarioId: scenarioId,
        sourcePath: sourcePath,
        target: target,
      ),
    );
    return true;
  }

  /// The generated contract carries the scenario ID as `id.value`.
  String? _scenarioIdOf(DartObject? value) {
    final id = value?.getField('id')?.getField('value')?.toStringValue();
    return id == null || id.isEmpty ? null : id;
  }

  DartObject? _constantValueOf(Element? element) {
    if (element is VariableElement) return element.computeConstantValue();
    if (element is PropertyAccessorElement) {
      return element.variable.computeConstantValue();
    }
    return null;
  }

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
