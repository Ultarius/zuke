import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:zuke/runner.dart';

/// One direct Zuke registration found in a Dart source file.
final class ZukeRegistration {
  const ZukeRegistration({
    required this.file,
    required this.line,
    required this.column,
    required this.runner,
    this.target,
    required this.scenarioId,
    required this.caseId,
  });

  final String file;
  final int line;
  final int column;
  final String runner;
  final String? target;
  final String? scenarioId;
  final String? caseId;

  bool get isWidget => runner == 'zukeTestWidgets';

  Map<String, Object?> toJson() => {
    'file': file,
    'line': line,
    'column': column,
    'runner': runner,
    'target': target,
    'scenarioId': scenarioId,
    'caseId': caseId,
  };
}

/// A source-level diagnostic produced while inspecting direct registrations.
final class RegistrationAuditDiagnostic {
  const RegistrationAuditDiagnostic({
    required this.code,
    required this.message,
    required this.file,
    required this.line,
    required this.column,
  });

  final String code;
  final String message;
  final String file;
  final int line;
  final int column;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'file': file,
    'line': line,
    'column': column,
  };
}

/// Result of inspecting direct `zukeTest`, `zukeUnit`, and
/// `zukeTestWidgets` calls.
final class RegistrationAuditResult {
  const RegistrationAuditResult({
    required this.registrations,
    required this.diagnostics,
  });

  final List<ZukeRegistration> registrations;
  final List<RegistrationAuditDiagnostic> diagnostics;

  bool get passed => diagnostics.isEmpty;

  Map<String, Object?> toJson() => {
    'passed': passed,
    'registrations': registrations
        .map((registration) => registration.toJson())
        .toList(growable: false),
    'diagnostics': diagnostics
        .map((diagnostic) => diagnostic.toJson())
        .toList(growable: false),
  };
}

/// Result of comparing statically declared registrations with one fresh
/// managed execution. The comparison is case-aware: multiple evidence types
/// may be emitted for one case, but a missing, skipped, failed, duplicated, or
/// unexpected case is still an execution failure.
final class RegistrationExecutionAuditResult {
  const RegistrationExecutionAuditResult(this.diagnostics);

  final List<RegistrationAuditDiagnostic> diagnostics;

  bool get passed => diagnostics.isEmpty;
}

/// Reconciles direct registrations with the result artifacts produced by a
/// selected profile. This is intentionally separate from AST inspection so a
/// source registration cannot be mistaken for proof that the test actually
/// ran.
final class RegistrationExecutionAudit {
  const RegistrationExecutionAudit();

  RegistrationExecutionAuditResult reconcile({
    required Iterable<ZukeRegistration> registrations,
    required Iterable<ExecutionResult> executions,
    required Set<String> selectedScenarioIds,
    required String target,
  }) {
    final diagnostics = <RegistrationAuditDiagnostic>[];
    final expected = <String, ZukeRegistration>{};
    for (final registration in registrations) {
      final scenarioId = registration.scenarioId;
      if (scenarioId == null ||
          !selectedScenarioIds.contains(scenarioId) ||
          (registration.target != null && registration.target != target)) {
        continue;
      }
      final key = _caseKey(scenarioId, registration.caseId);
      final previous = expected[key];
      if (previous != null) {
        diagnostics.add(
          _diagnostic(
            code: 'ZK-EXECUTION-DUPLICATE-REGISTRATION',
            message:
                'Selected registration case $key is declared more than once for target $target.',
            registration: registration,
          ),
        );
      } else {
        expected[key] = registration;
      }
    }

    final observed = <String, Set<String>>{};
    for (final execution in executions) {
      final ids = execution.scenarioIds
          .map((id) => id.value)
          .where(selectedScenarioIds.contains)
          .toList(growable: false);
      final fallback = selectedScenarioIds.contains(execution.candidateId)
          ? [execution.candidateId]
          : const <String>[];
      final scenarioIds = ids.isEmpty ? fallback : ids;
      final status = execution.toJson()['status']?.toString();
      for (final scenarioId in scenarioIds) {
        final key = _caseKey(scenarioId, execution.caseId);
        final evidenceKeys = observed.putIfAbsent(key, () => <String>{});
        final evidenceKey = execution.evidenceType;
        if (!evidenceKeys.add(evidenceKey)) {
          diagnostics.add(
            _diagnostic(
              code: 'ZK-EXECUTION-DUPLICATE-CASE',
              message:
                  'Managed execution produced duplicate case $key for evidence type $evidenceKey on target $target.',
            ),
          );
        }
        if (status == 'skipped') {
          diagnostics.add(
            _diagnostic(
              code: 'ZK-EXECUTION-SKIPPED-CASE',
              message:
                  'Managed execution skipped selected case $key on target $target.',
            ),
          );
        } else if (!execution.isPassed) {
          diagnostics.add(
            _diagnostic(
              code: 'ZK-EXECUTION-FAILED-CASE',
              message:
                  'Managed execution failed selected case $key on target $target.',
            ),
          );
        }
      }
    }

    for (final entry in expected.entries) {
      if (!observed.containsKey(entry.key)) {
        diagnostics.add(
          _diagnostic(
            code: 'ZK-EXECUTION-MISSING-CASE',
            message:
                'Selected registration case ${entry.key} produced no managed execution result on target $target.',
            registration: entry.value,
          ),
        );
      }
    }
    for (final key in observed.keys) {
      if (!expected.containsKey(key)) {
        diagnostics.add(
          _diagnostic(
            code: 'ZK-EXECUTION-UNEXPECTED-CASE',
            message:
                'Managed execution produced unregistered selected case $key on target $target.',
          ),
        );
      }
    }
    return RegistrationExecutionAuditResult(List.unmodifiable(diagnostics));
  }

  String _caseKey(String scenarioId, String? caseId) =>
      '$scenarioId|${caseId == null || caseId.isEmpty ? '(default)' : caseId}';

  RegistrationAuditDiagnostic _diagnostic({
    required String code,
    required String message,
    ZukeRegistration? registration,
  }) => RegistrationAuditDiagnostic(
    code: code,
    message: message,
    file: registration?.file ?? '<managed-execution>',
    line: registration?.line ?? 1,
    column: registration?.column ?? 1,
  );
}

/// Analyzer-backed inspection for direct Zuke test registrations.
///
/// This deliberately does not execute tests and does not parse Gherkin step
/// text. It visits the Dart AST, so comments and unused declarations cannot be
/// mistaken for registrations. Local aliases and generated enum constants are
/// resolved from their declarations when they are statically visible.
final class RegistrationAuditSnapshot {
  const RegistrationAuditSnapshot({
    required this.files,
    required this.parsedUnits,
    required this.generatedScenarioIds,
    required this.parseDiagnostics,
  });

  final List<File> files;
  final Map<File, CompilationUnit> parsedUnits;
  final Map<String, String> generatedScenarioIds;
  final List<RegistrationAuditDiagnostic> parseDiagnostics;
}

final class RegistrationAudit {
  const RegistrationAudit();

  RegistrationAuditSnapshot prepareFiles(Iterable<File> files) {
    final normalizedFiles =
        files
            .where((file) => file.existsSync() && file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final parsedUnits = <File, CompilationUnit>{};
    final generatedScenarioIds = <String, String>{};
    final parseDiagnostics = <RegistrationAuditDiagnostic>[];
    for (final file in normalizedFiles) {
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      );
      for (final error in parsed.errors) {
        parseDiagnostics.add(
          RegistrationAuditDiagnostic(
            code: 'ZK-REGISTRATION-SYNTAX',
            message:
                'Analyzer could not parse this Dart source: ${error.message}',
            file: file.path,
            line: 1,
            column: 1,
          ),
        );
      }
      parsedUnits[file] = parsed.unit;
      _GeneratedScenarioCollector(generatedScenarioIds).collect(parsed.unit);
    }
    return RegistrationAuditSnapshot(
      files: List.unmodifiable(normalizedFiles),
      parsedUnits: Map.unmodifiable(parsedUnits),
      generatedScenarioIds: Map.unmodifiable(generatedScenarioIds),
      parseDiagnostics: List.unmodifiable(parseDiagnostics),
    );
  }

  RegistrationAuditResult inspectFiles(
    Iterable<File> files, {
    Set<String> expectedScenarioIds = const {},
    Set<String>? knownScenarioIds,
    Map<String, Iterable<String?>> scenarioCaseIds = const {},
    String? Function(File file)? targetForFile,
  }) => inspectSnapshot(
    prepareFiles(files),
    expectedScenarioIds: expectedScenarioIds,
    knownScenarioIds: knownScenarioIds,
    scenarioCaseIds: scenarioCaseIds,
    targetForFile: targetForFile,
  );

  RegistrationAuditResult inspectSnapshot(
    RegistrationAuditSnapshot snapshot, {
    Iterable<File>? files,
    Set<String> expectedScenarioIds = const {},
    Set<String>? knownScenarioIds,
    Map<String, Iterable<String?>> scenarioCaseIds = const {},
    String? Function(File file)? targetForFile,
  }) {
    final registrations = <ZukeRegistration>[];
    final diagnostics = <RegistrationAuditDiagnostic>[
      ...snapshot.parseDiagnostics,
    ];
    final selectedPaths = files
        ?.map((file) => file.absolute.uri.normalizePath().toString())
        .toSet();
    final selectedFiles = snapshot.files.where(
      (file) =>
          selectedPaths == null ||
          selectedPaths.contains(file.absolute.uri.normalizePath().toString()),
    );
    // `expectedScenarioIds` is profile-scoped. Keep the complete configured
    // scenario set separate so a valid registration excluded by a profile
    // (for example a nightly-only selection) is not misreported as unknown.
    final known = knownScenarioIds ?? expectedScenarioIds;
    for (final file in selectedFiles) {
      final unit = snapshot.parsedUnits[file]!;
      final visitor = _RegistrationVisitor(
        file: file,
        lineInfo: unit.lineInfo,
        target: targetForFile?.call(file),
        expectedScenarioIds: expectedScenarioIds,
        knownScenarioIds: known,
        scenarioCaseIds: scenarioCaseIds,
        generatedScenarioIds: snapshot.generatedScenarioIds,
      );
      unit.accept(visitor);
      registrations.addAll(visitor.registrations);
      diagnostics.addAll(visitor.diagnostics);
    }
    final identities = <String, ZukeRegistration>{};
    for (final registration in registrations) {
      final scenarioId = registration.scenarioId;
      if (scenarioId == null) continue;
      final identity =
          '${registration.runner}|${registration.target ?? '(unknown)'}|'
          '$scenarioId|${registration.caseId ?? '(default)'}';
      final previous = identities[identity];
      if (previous != null) {
        diagnostics.add(
          RegistrationAuditDiagnostic(
            code: 'ZK-REGISTRATION-DUPLICATE-IDENTITY',
            message:
                'Registration identity $identity is declared more than once; '
                'give each case a unique literal caseId.',
            file: registration.file,
            line: registration.line,
            column: registration.column,
          ),
        );
      } else {
        identities[identity] = registration;
      }
    }
    if (expectedScenarioIds.isNotEmpty) {
      final registeredScenarioIds = registrations
          .map((registration) => registration.scenarioId)
          .whereType<String>()
          .toSet();
      for (final scenarioId
          in expectedScenarioIds.difference(registeredScenarioIds).toList()
            ..sort()) {
        diagnostics.add(
          RegistrationAuditDiagnostic(
            code: 'ZK-REGISTRATION-EXPECTED-MISSING',
            message:
                'Configured scenario $scenarioId has no direct zukeTest, '
                'zukeUnit, or zukeTestWidgets registration.',
            file: '<configured-specification>',
            line: 1,
            column: 1,
          ),
        );
      }
    }
    return RegistrationAuditResult(
      registrations: List.unmodifiable(registrations),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  RegistrationAuditResult inspectDirectory(
    Directory root, {
    Set<String> expectedScenarioIds = const {},
    Set<String>? knownScenarioIds,
    Map<String, Iterable<String?>> scenarioCaseIds = const {},
    String? Function(File file)? targetForFile,
  }) {
    if (!root.existsSync()) {
      return RegistrationAuditResult(
        registrations: const [],
        diagnostics: [
          RegistrationAuditDiagnostic(
            code: 'ZK-REGISTRATION-ROOT-MISSING',
            message: 'Registration source root does not exist.',
            file: root.path,
            line: 1,
            column: 1,
          ),
        ],
      );
    }
    return inspectFiles(
      root.listSync(recursive: true, followLinks: false).whereType<File>(),
      expectedScenarioIds: expectedScenarioIds,
      knownScenarioIds: knownScenarioIds,
      scenarioCaseIds: scenarioCaseIds,
      targetForFile: targetForFile,
    );
  }
}

enum _FlutterHarnessKind { gherkin, evidence }

final class _RegistrationVisitor extends RecursiveAstVisitor<void> {
  _RegistrationVisitor({
    required this.file,
    required this.lineInfo,
    required this.target,
    required this.expectedScenarioIds,
    required this.knownScenarioIds,
    required this.scenarioCaseIds,
    required Map<String, String> generatedScenarioIds,
  }) : _generatedScenarioIds = generatedScenarioIds;

  final File file;
  final LineInfo lineInfo;
  final String? target;
  final Set<String> expectedScenarioIds;
  final Set<String> knownScenarioIds;
  final Map<String, Iterable<String?>> scenarioCaseIds;
  final registrations = <ZukeRegistration>[];
  final diagnostics = <RegistrationAuditDiagnostic>[];
  final _aliases = <String, String>{};
  final Map<String, String> _generatedScenarioIds;
  final _functionStack = <String>[];
  final _flutterHarnessAliases = <String, _FlutterHarnessKind>{};

  @override
  void visitCompilationUnit(CompilationUnit node) {
    super.visitCompilationUnit(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _functionStack.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
    _functionStack.removeLast();
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final declarations = node.parent;
    final immutable =
        declarations is VariableDeclarationList &&
        (declarations.isFinal || declarations.isConst);
    final resolved = immutable ? _resolve(node.initializer) : null;
    final harnessKind = immutable
        ? _flutterHarnessKind(node.initializer)
        : null;
    _aliases.remove(node.name.lexeme);
    _flutterHarnessAliases.remove(node.name.lexeme);
    if (harnessKind != null) {
      _flutterHarnessAliases[node.name.lexeme] = harnessKind;
    }
    if (resolved != null) _aliases[node.name.lexeme] = resolved;
    super.visitVariableDeclaration(node);
  }

  @override
  void visitBlock(Block node) {
    final aliases = Map<String, String>.of(_aliases);
    final harnesses = Map<String, _FlutterHarnessKind>.of(
      _flutterHarnessAliases,
    );
    super.visitBlock(node);
    _aliases
      ..clear()
      ..addAll(aliases);
    _flutterHarnessAliases
      ..clear()
      ..addAll(harnesses);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final aliases = Map<String, String>.of(_aliases);
    final harnesses = Map<String, _FlutterHarnessKind>.of(
      _flutterHarnessAliases,
    );
    for (final parameter
        in node.parameters?.parameters ?? <FormalParameter>[]) {
      _aliases.remove(parameter.name?.lexeme);
      _flutterHarnessAliases.remove(parameter.name?.lexeme);
    }
    super.visitFunctionExpression(node);
    _aliases
      ..clear()
      ..addAll(aliases);
    _flutterHarnessAliases
      ..clear()
      ..addAll(harnesses);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final runner = node.methodName.name;
    if (runner == 'registerAll' && _isFlutterHarnessRegistration(node)) {
      _inspectFlutterHarnessRegistration(node);
      super.visitMethodInvocation(node);
      return;
    }
    if (runner != 'zukeTest' &&
        runner != 'zukeUnit' &&
        runner != 'zukeTestWidgets') {
      super.visitMethodInvocation(node);
      return;
    }
    if (_functionStack.isNotEmpty && _functionStack.last != 'main') {
      _diagnostic(
        'ZK-REGISTRATION-UNREACHABLE',
        'Direct $runner registration is inside a named helper rather than an executable main entry point; move the registration into main or explicitly invoke the helper from main.',
        node,
      );
      super.visitMethodInvocation(node);
      return;
    }
    final line = _line(node.offset);
    final scenarioArgument = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'scenario')
        .toList();
    final caseArgument = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'caseId')
        .toList();
    final provedControlsArgument = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'provedControls')
        .toList();
    if (provedControlsArgument.length > 1) {
      _diagnostic(
        'ZK-REGISTRATION-CONTROLS-DUPLICATE',
        'Direct registration contains more than one provedControls argument.',
        node,
      );
    } else if (provedControlsArgument.length == 1 &&
        _isBlanketControlProof(provedControlsArgument.single.expression)) {
      _diagnostic(
        'ZK-REGISTRATION-CONTROLS-BLANKET',
        'provedControls must name only controls asserted by this test; '
            'scenario.controlIds and controlsFor(...) would automatically claim '
            'future specification controls.',
        provedControlsArgument.single,
      );
    }
    final scenarioId = scenarioArgument.length == 1
        ? _resolve(scenarioArgument.single.expression)
        : null;
    if (scenarioArgument.length != 1) {
      _diagnostic(
        'ZK-REGISTRATION-SCENARIO-MISSING',
        'Direct $runner registration must contain exactly one named scenario argument.',
        node,
      );
    } else if (scenarioId == null) {
      _diagnostic(
        'ZK-REGISTRATION-DYNAMIC',
        'Unable to statically resolve the scenario contract for $runner. Use a generated contract or a local alias initialized from one.',
        scenarioArgument.single,
      );
    } else if (knownScenarioIds.isNotEmpty &&
        !knownScenarioIds.contains(scenarioId)) {
      _diagnostic(
        'ZK-REGISTRATION-UNKNOWN-SCENARIO',
        'Registration resolves to $scenarioId, which is not present in the configured specification set.',
        scenarioArgument.single,
      );
    }
    String? caseId = runner == 'zukeUnit' ? scenarioId : null;
    if (caseArgument.length > 1) {
      _diagnostic(
        'ZK-REGISTRATION-CASE-DUPLICATE',
        'Direct registration contains more than one caseId argument.',
        node,
      );
    } else if (caseArgument.length == 1) {
      final expression = caseArgument.single.expression;
      caseId = _resolveCaseId(expression);
      if (caseId == null) {
        _diagnostic(
          'ZK-REGISTRATION-CASE-DYNAMIC',
          'caseId must be a string literal or a statically resolved scenario.id.value expression so registration identity is deterministic.',
          caseArgument.single,
        );
      }
    }
    registrations.add(
      ZukeRegistration(
        file: file.path,
        line: line.lineNumber,
        column: line.columnNumber,
        runner: runner,
        target: target,
        scenarioId: scenarioId,
        caseId: caseId,
      ),
    );
    super.visitMethodInvocation(node);
  }

  /// Recognizes the supported Flutter harness form:
  ///
  /// ```dart
  /// ZukeFlutterHarness<World>(
  ///   scenarios: GeneratedScenarios.all,
  ///   ...
  /// ).registerAll();
  /// ```
  ///
  /// The harness registers one widget case for every generated contract. It
  /// is therefore equivalent to direct [zukeTestWidgets] registrations for
  /// static registration auditing, while execution reconciliation still
  /// proves that those cases actually ran.
  bool _isFlutterHarnessRegistration(MethodInvocation node) {
    final target = node.target;
    if (target is InstanceCreationExpression) {
      return _flutterHarnessKind(target) != null;
    }
    // With unresolved source-only Analyzer units, a generic constructor call
    // such as `ZukeFlutterHarness<World>(...)` is represented as a
    // MethodInvocation. The shape is still unambiguous because it is the
    // receiver of the chained registerAll() call.
    if (target is MethodInvocation && target.target == null) {
      return _flutterHarnessKind(target) != null;
    }
    return target is SimpleIdentifier &&
        _flutterHarnessAliases.containsKey(target.name);
  }

  void _inspectFlutterHarnessRegistration(MethodInvocation node) {
    if (_functionStack.isNotEmpty && _functionStack.last != 'main') {
      _diagnostic(
        'ZK-REGISTRATION-UNREACHABLE',
        'ZukeFlutterHarness registration is inside a named helper rather '
            'than an executable main entry point; move the registration into '
            'main or explicitly invoke the helper from main.',
        node,
      );
      return;
    }
    final harnessTarget = node.target;
    final arguments = switch (harnessTarget) {
      InstanceCreationExpression(:final argumentList) => argumentList.arguments,
      MethodInvocation(:final argumentList) => argumentList.arguments,
      _ => const <Expression>[],
    };
    final harnessKind = _flutterHarnessKind(harnessTarget);
    final aliasKind = harnessTarget is SimpleIdentifier
        ? _flutterHarnessAliases[harnessTarget.name]
        : null;

    // ZukeFlutterEvidenceHarness is the lightweight, non-Gherkin Flutter
    // harness. Its registerAll call receives a static list of
    // FlutterEvidenceCase objects rather than a named `scenarios` collection.
    // Treat each statically resolved case as the equivalent direct
    // zukeTestWidgets registration. This keeps the audit aligned with the
    // actual runner API without accepting arbitrary registerAll calls.
    if (harnessKind == _FlutterHarnessKind.evidence ||
        aliasKind == _FlutterHarnessKind.evidence) {
      _inspectEvidenceHarnessCases(node);
      return;
    }
    final scenariosArgument = arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'scenarios')
        .toList();
    if (scenariosArgument.length != 1) {
      _diagnostic(
        'ZK-REGISTRATION-SCENARIOS-MISSING',
        'ZukeFlutterHarness registration must contain exactly one named '
            'scenarios argument that resolves to generated contracts.',
        node,
      );
      return;
    }
    final scenarioIds = _resolveScenarioCollection(
      scenariosArgument.single.expression,
    );
    if (scenarioIds == null || scenarioIds.isEmpty) {
      _diagnostic(
        'ZK-REGISTRATION-DYNAMIC',
        'Unable to statically resolve the ZukeFlutterHarness scenarios '
            'collection. Use a generated scenario collection such as '
            'GeneratedScenarios.all.',
        scenariosArgument.single,
      );
      return;
    }
    final location = _line(node.offset);
    for (final scenarioId in scenarioIds) {
      if (knownScenarioIds.isNotEmpty &&
          !knownScenarioIds.contains(scenarioId)) {
        _diagnostic(
          'ZK-REGISTRATION-UNKNOWN-SCENARIO',
          'Harness registration resolves to $scenarioId, which is not '
              'present in the configured specification set.',
          scenariosArgument.single,
        );
      }
      final cases = scenarioCaseIds[scenarioId]?.toList(growable: false);
      final caseIds = cases == null || cases.isEmpty
          ? const <String?>[null]
          : cases;
      for (final caseId in caseIds) {
        registrations.add(
          ZukeRegistration(
            file: file.path,
            line: location.lineNumber,
            column: location.columnNumber,
            runner: 'zukeTestWidgets',
            target: target,
            scenarioId: scenarioId,
            caseId: caseId,
          ),
        );
      }
    }
  }

  void _inspectEvidenceHarnessCases(MethodInvocation node) {
    final arguments = node.argumentList.arguments;
    if (arguments.length != 1 || arguments.single is! ListLiteral) {
      _diagnostic(
        'ZK-REGISTRATION-SCENARIOS-MISSING',
        'ZukeFlutterEvidenceHarness.registerAll must contain exactly one '
            'static list of FlutterEvidenceCase registrations.',
        node,
      );
      return;
    }
    final cases = (arguments.single as ListLiteral).elements;
    final location = _line(node.offset);
    for (final element in cases) {
      final caseArguments = switch (element) {
        InstanceCreationExpression(:final constructorName, :final argumentList)
            when constructorName.type.name.lexeme == 'FlutterEvidenceCase' =>
          argumentList.arguments,
        MethodInvocation(:final methodName, :final argumentList)
            when methodName.name == 'FlutterEvidenceCase' =>
          argumentList.arguments,
        _ => null,
      };
      if (caseArguments == null) {
        _diagnostic(
          'ZK-REGISTRATION-DYNAMIC',
          'Unable to statically resolve a FlutterEvidenceCase in '
              'ZukeFlutterEvidenceHarness.registerAll. Use a literal '
              'FlutterEvidenceCase with a generated scenario contract.',
          element,
        );
        continue;
      }
      final scenarioArguments = caseArguments
          .whereType<NamedExpression>()
          .where((argument) => argument.name.label.name == 'scenario')
          .toList();
      if (scenarioArguments.length != 1) {
        _diagnostic(
          'ZK-REGISTRATION-SCENARIO-MISSING',
          'FlutterEvidenceCase must contain exactly one named scenario '
              'argument.',
          element,
        );
        continue;
      }
      final scenarioId = _resolve(scenarioArguments.single.expression);
      if (scenarioId == null) {
        _diagnostic(
          'ZK-REGISTRATION-DYNAMIC',
          'Unable to statically resolve the FlutterEvidenceCase scenario. '
              'Use a generated contract or a local alias initialized from '
              'one.',
          scenarioArguments.single,
        );
        continue;
      }
      if (knownScenarioIds.isNotEmpty &&
          !knownScenarioIds.contains(scenarioId)) {
        _diagnostic(
          'ZK-REGISTRATION-UNKNOWN-SCENARIO',
          'Evidence harness registration resolves to $scenarioId, which is '
              'not present in the configured specification set.',
          scenarioArguments.single,
        );
      }
      registrations.add(
        ZukeRegistration(
          file: file.path,
          line: location.lineNumber,
          column: location.columnNumber,
          runner: 'zukeTestWidgets',
          target: target,
          scenarioId: scenarioId,
          caseId: null,
        ),
      );
    }
  }

  _FlutterHarnessKind? _flutterHarnessKind(Expression? expression) {
    if (expression is InstanceCreationExpression) {
      final name = expression.constructorName.type.name.lexeme;
      return switch (name) {
        'ZukeFlutterHarness' => _FlutterHarnessKind.gherkin,
        'ZukeFlutterEvidenceHarness' => _FlutterHarnessKind.evidence,
        _ => null,
      };
    }
    if (expression is MethodInvocation && expression.target == null) {
      return switch (expression.methodName.name) {
        'ZukeFlutterHarness' => _FlutterHarnessKind.gherkin,
        'ZukeFlutterEvidenceHarness' => _FlutterHarnessKind.evidence,
        _ => null,
      };
    }
    return null;
  }

  Set<String>? _resolveScenarioCollection(Expression expression) {
    final parts = _qualifiedParts(expression);
    if (parts == null || parts.length < 2 || parts.last != 'all') {
      return null;
    }
    // Generated scenario collections consistently use the plural `Scenarios`
    // suffix and are backed by a corresponding `...Scenario` enum. Resolve
    // from the Analyzer-collected enum constants rather than accepting an
    // arbitrary variable named `all`.
    final collectionName = parts[parts.length - 2];
    if (!collectionName.endsWith('Scenarios')) return null;
    final enumName =
        '${collectionName.substring(0, collectionName.length - 1)}';
    final ids = _generatedScenarioIds.entries
        .where((entry) => entry.key.startsWith('$enumName.'))
        .map((entry) => entry.value)
        .toSet();
    return ids.isEmpty ? null : ids;
  }

  String? _resolve(Expression? expression) {
    if (expression == null) return null;
    if (expression is StringLiteral) return null;
    if (expression is SimpleIdentifier) return _aliases[expression.name];
    if (expression is PrefixedIdentifier) {
      return _generatedScenarioIds['${expression.prefix.name}.${expression.identifier.name}'];
    }
    if (expression is PropertyAccess && expression.target is SimpleIdentifier) {
      return _generatedScenarioIds['${(expression.target as SimpleIdentifier).name}.${expression.propertyName.name}'];
    }
    return null;
  }

  String? _resolveCaseId(Expression expression) {
    if (expression is StringLiteral) return expression.stringValue;
    // Consumer registrations commonly use `scenarioAlias.id.value`. The
    // alias has already been resolved from generated contract
    // declarations above, so this remains deterministic without requiring a
    // string duplicated beside the scenario argument.
    final parts = _qualifiedParts(expression);
    if (parts != null &&
        parts.length >= 3 &&
        parts[parts.length - 2] == 'id' &&
        parts.last == 'value') {
      return _aliases[parts.sublist(0, parts.length - 2).join('.')];
    }
    return null;
  }

  bool _isBlanketControlProof(Expression expression) {
    if (expression is MethodInvocation &&
        expression.methodName.name == 'controlsFor') {
      return true;
    }
    final parts = _qualifiedParts(expression);
    return parts != null && parts.isNotEmpty && parts.last == 'controlIds';
  }

  List<String>? _qualifiedParts(Expression? expression) {
    if (expression == null) return null;
    if (expression is SimpleIdentifier) return [expression.name];
    if (expression is PrefixedIdentifier) {
      final prefix = _qualifiedParts(expression.prefix);
      if (prefix == null) return null;
      return [...prefix, expression.identifier.name];
    }
    if (expression is PropertyAccess) {
      final target = _qualifiedParts(expression.target);
      if (target == null) return null;
      return [...target, expression.propertyName.name];
    }
    return null;
  }

  CharacterLocation _line(int offset) => lineInfo.getLocation(offset);

  void _diagnostic(String code, String message, AstNode node) {
    final location = _line(node.offset);
    diagnostics.add(
      RegistrationAuditDiagnostic(
        code: code,
        message: message,
        file: file.path,
        line: location.lineNumber,
        column: location.columnNumber,
      ),
    );
  }
}

final class _GeneratedScenarioCollector {
  _GeneratedScenarioCollector(this.output);

  final Map<String, String> output;

  void collect(CompilationUnit node) {
    for (final declaration in node.declarations) {
      if (declaration is! EnumDeclaration) continue;
      final enumName = declaration.name.lexeme;
      if (!enumName.endsWith('Scenario')) continue;
      for (final constant in declaration.constants) {
        final visitor = _ScenarioIdVisitor();
        constant.arguments?.accept(visitor);
        if (visitor.ids.length == 1) {
          output['$enumName.${constant.name.lexeme}'] = visitor.ids.single;
        }
      }
    }
    // Generated contracts also expose readable feature/rule aliases such as
    // `AdditionScenarios.addIntegersApi`. Resolve those aliases after the
    // enum constants are known so applications can use the generated public
    // contract API without falling back to dynamic registration.
    node.accept(_GeneratedScenarioAliasCollector(output));
  }
}

final class _GeneratedScenarioAliasCollector extends RecursiveAstVisitor<void> {
  _GeneratedScenarioAliasCollector(this.output);

  final Map<String, String> output;
  String? _className;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previous = _className;
    _className = node.name.lexeme;
    super.visitClassDeclaration(node);
    _className = previous;
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final className = _className;
    final initializer = node.initializer;
    final declarationList = node.parent;
    final immutable =
        declarationList is VariableDeclarationList &&
        (declarationList.isFinal || declarationList.isConst);
    final field = declarationList?.parent;
    if (className != null &&
        initializer != null &&
        immutable &&
        field is FieldDeclaration &&
        field.isStatic) {
      final parts = _qualifiedParts(initializer);
      if (parts != null && parts.length >= 2) {
        final resolved = output[parts.join('.')];
        if (resolved != null) {
          output['$className.${node.name.lexeme}'] = resolved;
        }
      }
    }
    super.visitVariableDeclaration(node);
  }

  List<String>? _qualifiedParts(Expression? expression) {
    if (expression is SimpleIdentifier) return [expression.name];
    if (expression is PrefixedIdentifier) {
      final prefix = _qualifiedParts(expression.prefix);
      if (prefix == null) return null;
      return [...prefix, expression.identifier.name];
    }
    if (expression is PropertyAccess) {
      final target = _qualifiedParts(expression.target);
      if (target == null) return null;
      return [...target, expression.propertyName.name];
    }
    return null;
  }
}

/// Finds the semantic ScenarioId constructor without depending on the AST
/// shape used for enum arguments by one particular Analyzer release.
final class _ScenarioIdVisitor extends RecursiveAstVisitor<void> {
  final ids = <String>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.toSource().endsWith('ScenarioId')) {
      final arguments = node.argumentList.arguments;
      if (arguments.length == 1 && arguments.single is StringLiteral) {
        final value = (arguments.single as StringLiteral).stringValue;
        if (value != null) ids.add(value);
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'ScenarioId') {
      final arguments = node.argumentList.arguments;
      if (arguments.length == 1 && arguments.single is StringLiteral) {
        final value = (arguments.single as StringLiteral).stringValue;
        if (value != null) ids.add(value);
      }
    }
    super.visitMethodInvocation(node);
  }
}
