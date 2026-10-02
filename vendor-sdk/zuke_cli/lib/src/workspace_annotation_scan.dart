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
///
/// One claim per registration site. Two registrations naming the same scenario
/// stay separate claims, because merging them would attribute one file's
/// evidence kinds to another file's target: an app unit registration plus a
/// backend widget registration merge into one app claim publishing
/// `flutter-widget`, which then satisfies a slot the app never registered.
final class ManagedScenarioClaim {
  final String scenarioId;
  final String sourcePath;
  final String? target;

  /// The configured package containing [sourcePath], or null when no package
  /// does. Carried because a slot names a package and a target alone cannot tell
  /// two packages of one target apart.
  final String? packageId;

  /// The evidence kinds this registration declares it publishes, resolved from
  /// the `evidenceTypes`/`evidenceType` argument or inherited from a harness, or
  /// null when the argument is absent-and-inherited-nowhere, or unreadable.
  ///
  /// Null means "unknown", not "none". A registration whose kinds cannot be
  /// resolved may be exactly the one satisfying a declared slot, so a caller
  /// reporting gaps has to treat a null here as blocking the question rather
  /// than as evidence of a gap. This is why the field is not defaulted to an
  /// empty list.
  final List<String>? evidenceTypes;

  const ManagedScenarioClaim({
    required this.scenarioId,
    required this.sourcePath,
    this.target,
    this.packageId,
    this.evidenceTypes,
  });

  @override
  String toString() =>
      'ManagedScenarioClaim($scenarioId @ $sourcePath -> $target/$packageId, '
      '${evidenceTypes ?? '<unknown>'})';
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
  // One entry per registration site. Two registrations naming the same scenario
  // stay separate claims: merging them would attribute one file's evidence kinds
  // to another file's target and satisfy a slot that was never registered. A
  // consumer that needs them grouped by scenario groups them itself.
  final managedScenarios = <ManagedScenarioClaim>[];
  // Summed from each file's collector. A plain local int rather than a shared
  // mutable holder: the total is only read once the walk is over, so there is
  // nothing to share, and a wrapper class around a single counter only added an
  // indirection between an increment and the field it wrote.
  var unresolvedRegistrations = 0;
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
  final packageIds = workspacePackageIds(workspace);
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
      // One traversal collects the managed registrations and, separately, the
      // harness and case declarations a `registerAll` call has to resolve
      // against. Ownership cannot be read during the walk: a harness may be
      // declared anywhere in the library, including after the call that uses it,
      // so the walk only records and `resolve` decides.
      final collector = _ClaimCollector(
        sourcePath,
        targetForWorkspacePath(packageTargets, sourcePath),
        packageIdForWorkspacePath(packageIds, sourcePath),
        claims,
        managedScenarios,
      );
      result.unit.accept(collector);
      collector.resolve();
      unresolvedRegistrations += collector.unresolvedRegistrations;
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
    unresolvedManagedRegistrations: unresolvedRegistrations,
  );
}

/// A `ZukeFlutterHarness` construction, and the kinds it publishes.
///
/// The step harness names its own scenarios and a single `evidenceType`, so it
/// is self-describing. Ownership still has to be established: a construction
/// that no `registerAll` call reaches is not a test.
final class _StepHarnessDeclaration {
  _StepHarnessDeclaration({
    required this.node,
    required this.scenariosArgument,
    required this.evidenceType,
  });

  final InstanceCreationExpression node;
  final Expression? scenariosArgument;
  final ConstantStringsArgument evidenceType;
}

/// A `ZukeFlutterEvidenceHarness` construction, and the defaults its cases
/// inherit.
///
/// Only constructions from the harness library count. Any other constructor
/// that happens to take a `defaultEvidenceTypes` argument is not a harness this
/// scan knows how to attribute.
final class _EvidenceHarnessDeclaration {
  _EvidenceHarnessDeclaration({required this.node, required this.defaults});

  final InstanceCreationExpression node;
  final ConstantStringsArgument defaults;
}

/// A `FlutterEvidenceCase` construction.
///
/// Records the case, not a registration: a case only becomes a test when some
/// `registerAll` call reaches it.
final class _EvidenceCaseDeclaration {
  _EvidenceCaseDeclaration({
    required this.node,
    required this.scenarioArgument,
    required this.explicitKinds,
  });

  final InstanceCreationExpression node;
  final Expression? scenarioArgument;
  final ConstantStringsArgument explicitKinds;
}

/// A `registerAll` call: the harness it reaches and the cases handed to it.
final class _RegisterAllCall {
  _RegisterAllCall({required this.receiver, required this.arguments});

  /// The expression `registerAll` is called on.
  final Expression receiver;

  /// Arguments are interpreted after all local declarations have been collected.
  final List<AstNode> arguments;
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
    this.packageId,
    this.claims,
    this.managedScenarios,
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

  /// The configured package this file belongs to, so a slot naming a package
  /// can be matched and an unattributable file stays unattributable.
  final String? packageId;
  final List<ImplementationClaim> claims;

  /// Registrations collected so far, one per call site.
  final List<ManagedScenarioClaim> managedScenarios;

  /// Registrations this file could not resolve to a scenario, counted here and
  /// summed across the scan.
  ///
  /// Any one of them could be the registration satisfying some other rule's
  /// slot, so the total is workspace-wide on purpose: one unreadable
  /// registration makes every slot undecidable rather than only the rules in this
  /// file.
  int unresolvedRegistrations = 0;

  final Set<_ClaimKey> _seen = {};

  /// Harness and case declarations, keyed by construction site. Local variable
  /// aliases resolve to those sites through their collected initializers.
  final _stepHarnesses = <Object, _StepHarnessDeclaration>{};
  final _evidenceHarnesses = <Object, _EvidenceHarnessDeclaration>{};
  final _cases = <Object, _EvidenceCaseDeclaration>{};
  final _registerAlls = <_RegisterAllCall>[];
  final _initializers = <Object, Expression>{};
  final _assigned = <Object>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final entrypoint = zukeManagedEntrypointName(node.methodName.element);
    if (entrypoint != null) {
      final arguments = node.argumentList.arguments;
      _recordScenarioArgument(
        namedArgumentValue(arguments, 'scenario'),
        entrypointEvidenceTypes(entrypoint, arguments),
      );
    } else if (isZukeHarnessRegisterAll(node.methodName.element)) {
      // Recorded, not acted on: the receiver says which harness owns the cases,
      // and that cannot be read until the walk has seen every declaration.
      final receiver = node.realTarget;
      if (receiver == null) {
        unresolvedRegistrations += 1;
      } else {
        _registerAlls.add(
          _RegisterAllCall(
            receiver: receiver,
            arguments: node.argumentList.arguments.toList(),
          ),
        );
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _recordHarnessConstruction(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    final element = _declarationElementOf(node.declaredFragment?.element);
    if (initializer != null && element != null) {
      _initializers[element] = initializer;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final element = _referenceElementOf(node.leftHandSide);
    if (element != null) _assigned.add(element);
    super.visitAssignmentExpression(node);
  }

  /// Records each construction once; aliases resolve through their initializers.
  void _recordHarnessConstruction(InstanceCreationExpression node) {
    switch (zukeFlutterHarnessTypeName(node)) {
      case 'ZukeFlutterHarness':
        _stepHarnesses[node] = _StepHarnessDeclaration(
          node: node,
          scenariosArgument: namedArgumentValue(
            node.argumentList.arguments,
            'scenarios',
          ),
          evidenceType: constantStringsArgument(
            node.argumentList.arguments,
            'evidenceType',
          ),
        );
      case 'ZukeFlutterEvidenceHarness':
        _evidenceHarnesses[node] = _EvidenceHarnessDeclaration(
          node: node,
          defaults: constantStringsArgument(
            node.argumentList.arguments,
            'defaultEvidenceTypes',
          ),
        );
      case 'FlutterEvidenceCase':
        _cases[node] = _EvidenceCaseDeclaration(
          node: node,
          scenarioArgument: namedArgumentValue(
            node.argumentList.arguments,
            'scenario',
          ),
          explicitKinds: constantStringsArgument(
            node.argumentList.arguments,
            'evidenceTypes',
          ),
        );
      case _:
        break;
    }
  }

  /// Turns the collected declarations into registrations.
  ///
  /// Ownership is decided here rather than during the walk because a harness may
  /// be declared anywhere in the library, including after the `registerAll` that
  /// reaches it. Attribution is per harness: a case inherits the defaults of the
  /// harness that registers it, so an unreadable default on one harness leaves a
  /// case registered by a different, readable one decidable.
  void resolve() {
    for (final call in _registerAlls) {
      final receiver = _receiverKeyOf(call.receiver);
      final step = receiver == null ? null : _stepHarnesses[receiver];
      if (step != null) {
        // The step harness names its own scenarios and kind; it inherits
        // nothing from a sibling.
        final List<String>? kinds = switch (step.evidenceType.state) {
          ConstantArgumentState.readable => step.evidenceType.values,
          ConstantArgumentState.absent => const [
            zukeHarnessDefaultEvidenceType,
          ],
          ConstantArgumentState.unreadable => null,
        };
        _recordScenarioArgument(step.scenariosArgument, kinds);
        continue;
      }
      final harness = receiver == null ? null : _evidenceHarnesses[receiver];
      if (harness == null) {
        // A `registerAll` on a receiver this walk cannot attribute. The method
        // is a harness one, so a harness exists and its cases are unknown rather
        // than absent.
        unresolvedRegistrations += 1;
        continue;
      }
      final List<String>? inherited = switch (harness.defaults.state) {
        ConstantArgumentState.readable =>
          harness.defaults.values!.toSet().toList()..sort(),
        // An absent default declares none, and an unreadable one cannot be seen.
        // Either way this harness does not determine its cases' kinds.
        _ => null,
      };
      final caseExpressions = _argumentListElements(call.arguments);
      if (caseExpressions == null) {
        unresolvedRegistrations += 1;
        continue;
      }
      for (final caseExpression in caseExpressions) {
        final key = _receiverKeyOf(caseExpression);
        final declaration = key == null ? null : _cases[key];
        if (declaration == null) {
          unresolvedRegistrations += 1;
          continue;
        }
        // An explicit override wins; one that cannot be read is unknown, never
        // the default it replaces.
        final List<String>? kinds = switch (declaration.explicitKinds.state) {
          ConstantArgumentState.readable => declaration.explicitKinds.values,
          ConstantArgumentState.unreadable => null,
          ConstantArgumentState.absent => inherited,
        };
        _recordScenarioArgument(declaration.scenarioArgument, kinds);
      }
    }
  }

  /// Resolves a receiver or case expression to its recorded construction site.
  Object? _receiverKeyOf(Expression expression) {
    final resolved = _resolveExpression(expression);
    return resolved is InstanceCreationExpression ? resolved : null;
  }

  /// Follows local aliases only. Cycles, assignments and dynamic factories are
  /// unknown rather than guessed from a variable's original value.
  Expression? _resolveExpression(Expression expression) {
    final seen = <Object>{};
    while (true) {
      if (expression is ParenthesizedExpression) {
        expression = expression.expression;
      } else if (expression is CascadeExpression) {
        expression = expression.target;
      } else {
        final element = _referenceElementOf(expression);
        if (element == null) return expression;
        if (_assigned.contains(element) || !seen.add(element)) return null;
        final initializer = _initializers[element];
        if (initializer == null) return null;
        expression = initializer;
      }
    }
  }

  static Object? _referenceElementOf(Expression expression) =>
      _declarationElementOf(switch (expression) {
        SimpleIdentifier() => expression.element,
        PrefixedIdentifier() => expression.identifier.element,
        PropertyAccess() => expression.propertyName.element,
        _ => null,
      });

  /// The declaration an expression reference names.
  ///
  /// A reference to a top-level or static variable resolves to the synthesized
  /// getter the language adds for it, while the declaration itself reports the
  /// variable. Normalising through [PropertyAccessorElement.variable] puts both
  /// sides on one key, which is what lets `harness.registerAll()` find the
  /// declaration the walk recorded.
  static Object? _declarationElementOf(Element? element) =>
      element is PropertyAccessorElement ? element.variable : element;

  /// The elements of the positional list argument, or null when an argument is
  /// present but is not a literal list this scan can read.
  ///
  /// Null rather than an empty list for the unreadable shapes: an empty list
  /// reads as "this harness registers nothing", which is a claim about the
  /// workspace. A spread or collection-if among the cases is one of those.
  ///
  /// No argument at all yields empty, because the step harness's `registerAll()`
  /// takes none: its scenarios live on its own declaration.
  ///
  /// The `ListLiteral` is tested directly because a positional argument *is* the
  /// expression, so its `childEntities` are the list's elements, not the list.
  List<Expression>? _argumentListElements(Iterable<AstNode> arguments) {
    for (final argument in arguments) {
      final raw = argument is Expression
          ? argument
          : _argumentExpressionOf(argument);
      final value = raw == null ? null : _resolveExpression(raw);
      if (value is! ListLiteral) return null;
      final elements = <Expression>[];
      for (final element in value.elements) {
        if (element is! Expression) return null;
        elements.add(element);
      }
      return elements;
    }
    return const [];
  }

  /// The value expression of a positional or named argument.
  ///
  /// Reads the shared token shape rather than the node type, because analyzer 12
  /// models a named argument as `NamedExpression` and analyzer 14 as
  /// `NamedArgument`.
  static Expression? _argumentExpressionOf(AstNode argument) {
    final expressions = argument.childEntities.whereType<Expression>();
    return expressions.isEmpty ? null : expressions.last;
  }

  /// Records every constant scenario ID reachable from [expression].
  ///
  /// [expression] is either a single scenario contract (`scenario:`) or an
  /// iterable of them (`scenarios:`). A list literal, an `X.all` constant, or an
  /// enum `.values` list all evaluate to a constant list of objects carrying an
  /// `id`; anything else is counted as unresolved rather than guessed at.
  ///
  /// Takes the resolved value rather than the argument list, because the callers
  /// get it differently: a managed entry point looks it up by name, while a
  /// harness declaration already carries it from the walk.
  void _recordScenarioArgument(
    Expression? expression,
    List<String>? evidenceTypes,
  ) {
    if (expression == null ||
        !_registerScenarioExpression(expression, evidenceTypes)) {
      // A registration that names no scenario is unresolved, not coverage.
      unresolvedRegistrations += 1;
    }
  }

  bool _registerScenarioExpression(
    Expression expression,
    List<String>? evidenceTypes,
  ) {
    if (expression is ListLiteral) {
      var complete = expression.elements.isNotEmpty;
      for (final element in expression.elements) {
        if (element is! Expression ||
            !_registerScenarioExpression(element, evidenceTypes)) {
          complete = false;
        }
      }
      return complete;
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
      var complete = items.isNotEmpty;
      for (final item in items) {
        if (!_registerScenarioId(_scenarioIdOf(item), evidenceTypes)) {
          complete = false;
        }
      }
      return complete;
    }
    return _registerScenarioId(_scenarioIdOf(value), evidenceTypes);
  }

  bool _registerScenarioId(String? scenarioId, List<String>? evidenceTypes) {
    if (scenarioId == null) return false;
    // Appended, never merged. Deduplicating by scenario here would combine two
    // registrations into one claim and attribute one's kinds to the other's
    // target, which satisfies a slot that was never registered. Coverage
    // grouping happens at the consumer, where both claims are still visible.
    managedScenarios.add(
      ManagedScenarioClaim(
        scenarioId: scenarioId,
        sourcePath: sourcePath,
        target: target,
        packageId: packageId,
        evidenceTypes: evidenceTypes == null
            ? null
            : List.unmodifiable(evidenceTypes.toSet().toList()..sort()),
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
