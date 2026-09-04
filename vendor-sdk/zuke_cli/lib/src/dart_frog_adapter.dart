import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dart_frog_gen/dart_frog_gen.dart';
import 'package:path/path.dart' as path;
import 'package:zuke_core/zuke_core.dart';

import 'generated/release_contract.dart';
import 'tooling/analyzer_sdk.dart';
import 'tooling/inspection.dart';

/// Compatibility identity for the public Dart Frog route configuration API.
const dartFrogCompatibilityId = releaseDartFrogCompatibilityId;

final class DartFrogAdapter implements FrameworkAdapter {
  const DartFrogAdapter();

  @override
  String get id => 'dart-frog';

  @override
  String get compatibilityId => dartFrogCompatibilityId;

  @override
  Future<AdapterOutput> extract(AdapterRequest request) async {
    final diagnostics = <Diagnostic>[];
    final nodes = <TopologyNode>[];
    late final RouteConfiguration configuration;
    try {
      configuration = buildRouteConfiguration(Directory(request.packageRoot));
    } catch (error) {
      return _failed(
        request,
        diagnostics,
        'ZK-DART-FROG-001',
        'Unable to build Dart Frog route configuration: $error',
      );
    }

    final normalizedRoot = path.normalize(
      Directory(request.packageRoot).absolute.path,
    );
    late final AnalysisContextCollection collection;
    try {
      collection = AnalysisContextCollection(
        includedPaths: [normalizedRoot],
        sdkPath: resolveAnalyzerSdkPath(),
      );
    } catch (error) {
      return _failed(
        request,
        diagnostics,
        'ZK-DART-FROG-ANALYZER-001',
        'Unable to initialize the Dart analyzer for topology extraction: $error',
      );
    }

    try {
      var routeComplete = configuration.rogueRoutes.isEmpty;
      for (final entry
          in configuration.endpoints.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) {
        if (entry.value.length != 1) {
          routeComplete = false;
          diagnostics.add(
            _error(
              'ZK-DART-FROG-002',
              'Conflicting Dart Frog route registration for ${entry.key}',
            ),
          );
        }
        for (final routeFile in entry.value) {
          final topologyPath = _canonicalTopologyPath(routeFile.path);
          final resolved = _resolveRoutePath(
            request.packageRoot,
            routeFile.path,
          );
          if (resolved == null) {
            routeComplete = false;
            diagnostics.add(
              _error(
                'ZK-DART-FROG-PATH-001',
                'Unsupported Dart Frog route path: ${routeFile.path}',
              ),
            );
            continue;
          }
          final source = File(resolved);
          final exists = source.existsSync();
          if (!exists) {
            routeComplete = false;
            diagnostics.add(
              _error(
                'ZK-DART-FROG-003',
                'Dart Frog route handler could not be resolved: ${routeFile.path}',
              ),
            );
          }
          final transport = exists
              ? await _classifyTransport(resolved, request, collection)
              : const _TransportResult(kind: 'route', complete: false);
          routeComplete = routeComplete && transport.complete;
          diagnostics.addAll(transport.diagnostics);
          final nodeId = _nodeId(request, 'route', entry.key);
          nodes.add(
            TopologyNode(
              id: nodeId,
              kind: transport.kind == 'websocket' ? 'websocket-route' : 'route',
              name: routeFile.name,
              path: topologyPath,
              attributes: {
                'route': entry.key,
                'parameters': routeFile.params,
                'wildcard': routeFile.wildcard,
                'alias': routeFile.name,
                'handlerResolved': exists,
                'transport': transport.kind,
                'transportResolved': transport.complete,
                if (transport.implementationTypes.isNotEmpty)
                  'implementationTypes': transport.implementationTypes,
              },
            ),
          );
          nodes.add(
            TopologyNode(
              id: _nodeId(request, 'route-alias', '${entry.key}|$topologyPath'),
              kind: 'route-alias',
              name: routeFile.name,
              path: topologyPath,
              attributes: {'route': entry.key, 'target': nodeId},
            ),
          );
        }
      }
      for (final route in configuration.rogueRoutes) {
        routeComplete = false;
        diagnostics.add(
          _error(
            'ZK-DART-FROG-004',
            'Rogue Dart Frog route is not part of the generated topology: ${route.path}',
          ),
        );
      }

      final middleware = await _extractMiddleware(
        request,
        configuration,
        nodes,
        collection,
      );
      diagnostics.addAll(middleware.diagnostics);
      final customEntrypoint =
          configuration.invokeCustomEntrypoint ||
          configuration.invokeCustomInit;
      return AdapterOutput(
        targetId: request.targetId,
        packageId: request.packageId,
        sourceAdapter: id,
        compatibilityId: compatibilityId,
        completeness: AdapterCompleteness(
          routeRegistration: routeComplete
              ? CompletenessStatus.complete
              : CompletenessStatus.incomplete,
          middlewareOrder: middleware.complete
              ? CompletenessStatus.complete
              : CompletenessStatus.indeterminate,
          dynamicRegistration: customEntrypoint
              ? CompletenessStatus.indeterminate
              : CompletenessStatus.complete,
          externalVisibility: customEntrypoint
              ? CompletenessStatus.indeterminate
              : CompletenessStatus.complete,
          failureFlow: CompletenessStatus.indeterminate,
          logFlow: CompletenessStatus.indeterminate,
        ),
        nodes: nodes,
        diagnostics: diagnostics,
      );
    } finally {
      await collection.dispose();
    }
  }

  AdapterOutput _failed(
    AdapterRequest request,
    List<Diagnostic> diagnostics,
    String code,
    String message,
  ) {
    diagnostics.add(_error(code, message));
    return AdapterOutput(
      targetId: request.targetId,
      packageId: request.packageId,
      sourceAdapter: id,
      compatibilityId: compatibilityId,
      completeness: const AdapterCompleteness(
        routeRegistration: CompletenessStatus.incomplete,
        middlewareOrder: CompletenessStatus.incomplete,
        dynamicRegistration: CompletenessStatus.incomplete,
        externalVisibility: CompletenessStatus.incomplete,
      ),
      nodes: const [],
      diagnostics: diagnostics,
    );
  }

  Future<_MiddlewareResult> _extractMiddleware(
    AdapterRequest request,
    RouteConfiguration configuration,
    List<TopologyNode> nodes,
    AnalysisContextCollection collection,
  ) async {
    final diagnostics = <Diagnostic>[];
    final files = <String>{
      path.join(request.packageRoot, 'routes', '_middleware.dart'),
    };
    for (final middleware in configuration.middleware) {
      final resolved = _resolveRoutePath(request.packageRoot, middleware.path);
      if (resolved != null) files.add(resolved);
    }
    var complete = true;
    for (final filePath in files) {
      final file = File(filePath);
      if (!file.existsSync()) {
        complete = false;
        diagnostics.add(
          _error(
            'ZK-DART-FROG-005',
            'Dart Frog middleware file could not be resolved: $filePath',
          ),
        );
        continue;
      }
      final inspection = await _inspectMiddleware(
        filePath,
        request.packageRoot,
        collection,
      );
      complete = complete && inspection.complete;
      diagnostics.addAll(inspection.diagnostics);
      for (var index = 0; index < inspection.calls.length; index++) {
        final call = inspection.calls[index];
        final name = call.name;
        final topologyPath = _canonicalTopologyPath(
          path.relative(filePath, from: request.packageRoot),
        );
        nodes.add(
          TopologyNode(
            id: _nodeId(request, 'middleware', '$topologyPath|$name'),
            kind: 'middleware',
            name: name,
            path: topologyPath,
            attributes: {
              'incomingOrder': index,
              'chainResolved': true,
              if (call.controlId != null) 'controlId': call.controlId,
              if (call.implementationTypes.isNotEmpty)
                'implementationTypes': call.implementationTypes,
            },
          ),
        );
      }
    }
    return _MiddlewareResult(complete: complete, diagnostics: diagnostics);
  }

  String _canonicalTopologyPath(String value) => value.replaceAll('\\', '/');

  Future<_TransportResult> _classifyTransport(
    String filePath,
    AdapterRequest request,
    AnalysisContextCollection collection,
  ) async {
    final resolved = await _resolveUnit(filePath, collection);
    if (resolved == null) {
      return _TransportResult(
        kind: 'indeterminate',
        complete: false,
        diagnostics: [
          _warning(
            'ZK-DART-FROG-WS-001',
            'Dart Frog route transport could not be resolved: $filePath',
          ),
        ],
      );
    }
    var sawCandidate = false;
    var resolvedWebSocket = false;
    var unresolvedCandidate = false;
    final implementationTypes = <String>{};
    var unresolvedImplementationLink = false;
    resolved.unit.accept(
      _InvocationVisitor(
        onInvocation: (invocation) {
          final name = switch (invocation) {
            MethodInvocation value => value.methodName.name,
            FunctionExpressionInvocation value =>
              value.function is SimpleIdentifier
                  ? (value.function as SimpleIdentifier).name
                  : null,
            _ => null,
          };
          if (name != 'webSocketHandler') return;
          sawCandidate = true;
          final element = switch (invocation) {
            MethodInvocation value => value.methodName.element,
            FunctionExpressionInvocation value =>
              value.function is SimpleIdentifier
                  ? (value.function as SimpleIdentifier).element
                  : null,
            _ => null,
          };
          final uri = element?.library?.firstFragment.source.uri.toString();
          if (uri == 'package:dart_frog/dart_frog.dart' ||
              (uri?.startsWith('package:dart_frog/') ?? false) ||
              (uri?.startsWith('package:dart_frog_web_socket/') ?? false)) {
            resolvedWebSocket = true;
          } else {
            unresolvedCandidate = true;
          }
        },
        onMethodInvocation: (invocation) {
          if (invocation.methodName.name != 'read') return;
          final method = invocation.methodName.element;
          final enclosing = method?.enclosingElement;
          if (enclosing is! InterfaceElement ||
              enclosing.name != 'RequestContext') {
            return;
          }
          final arguments = invocation.typeArguments?.arguments ?? const [];
          if (arguments.length != 1) {
            unresolvedImplementationLink = true;
            return;
          }
          final type = arguments.single;
          final element = type.element;
          final name = element?.name ?? type.name.lexeme;
          if (element == null || name == null || name.isEmpty) {
            unresolvedImplementationLink = true;
            return;
          }
          implementationTypes.add(name);
        },
      ),
    );
    final linkedTypes = implementationTypes.toList()..sort();
    if (resolvedWebSocket) {
      return _TransportResult(
        kind: 'websocket',
        complete: !unresolvedImplementationLink,
        implementationTypes: linkedTypes,
        diagnostics: unresolvedImplementationLink
            ? [
                _warning(
                  'ZK-DART-FROG-IMPL-001',
                  'A RequestContext.read<T>() implementation link could not be resolved: $filePath',
                ),
              ]
            : const [],
      );
    }
    if (sawCandidate || unresolvedCandidate) {
      return _TransportResult(
        kind: 'indeterminate',
        complete: false,
        implementationTypes: linkedTypes,
        diagnostics: [
          _warning(
            'ZK-DART-FROG-WS-002',
            'webSocketHandler was found but did not resolve to Dart Frog: $filePath',
          ),
        ],
      );
    }
    return _TransportResult(
      kind: 'http',
      complete: !unresolvedImplementationLink,
      implementationTypes: linkedTypes,
      diagnostics: unresolvedImplementationLink
          ? [
              _warning(
                'ZK-DART-FROG-IMPL-001',
                'A RequestContext.read<T>() implementation link could not be resolved: $filePath',
              ),
            ]
          : const [],
    );
  }

  Future<_MiddlewareInspection> _inspectMiddleware(
    String filePath,
    String packageRoot,
    AnalysisContextCollection collection,
  ) async {
    final resolved = await _resolveUnit(filePath, collection);
    if (resolved == null) {
      return _MiddlewareInspection(
        complete: false,
        calls: const [],
        diagnostics: [
          _warning(
            'ZK-DART-FROG-006',
            'Dart Frog middleware could not be resolved: $filePath',
          ),
        ],
      );
    }
    final controls = <String, String>{};
    resolved.unit.accept(_ControlVisitor(controls));
    final middleware = resolved.unit.declarations
        .whereType<FunctionDeclaration>()
        .where((declaration) => declaration.name.lexeme == 'middleware')
        .toList();
    if (middleware.length != 1) {
      return _MiddlewareInspection(
        complete: false,
        calls: const [],
        diagnostics: [
          _warning(
            'ZK-DART-FROG-006',
            'Dart Frog middleware declaration is missing or ambiguous: $filePath',
          ),
        ],
      );
    }
    final expression = _returnedExpression(middleware.single);
    if (expression == null) {
      return _MiddlewareInspection(
        complete: false,
        calls: const [],
        diagnostics: [
          _warning(
            'ZK-DART-FROG-007',
            'Dart Frog middleware return expression is unresolved: $filePath',
          ),
        ],
      );
    }
    final chain = <MethodInvocation>[];
    Expression? cursor = expression;
    while (cursor is MethodInvocation && cursor.methodName.name == 'use') {
      chain.add(cursor);
      cursor = cursor.target;
    }
    if (chain.isEmpty || cursor == null) {
      return _MiddlewareInspection(
        complete: false,
        calls: const [],
        diagnostics: [
          _warning(
            'ZK-DART-FROG-008',
            'Dart Frog middleware chain contains no statically resolved use calls: $filePath',
          ),
        ],
      );
    }
    final diagnostics = <Diagnostic>[];
    var complete = true;
    final calls = <_MiddlewareCall>[];
    // The outermost call is the first incoming middleware in Dart Frog's
    // composed handler. Walking from the returned expression toward the
    // base handler therefore yields the effective incoming order directly.
    for (final invocation in chain) {
      final arguments = invocation.argumentList.arguments;
      final argument = arguments.length == 1 ? arguments.single : null;
      final name = argument == null ? null : _middlewareName(argument);
      if (argument == null || name == null) {
        complete = false;
        diagnostics.add(
          _warning(
            'ZK-DART-FROG-009',
            'Dart Frog middleware use argument is dynamic or unsupported: $filePath',
          ),
        );
        continue;
      }
      final implementationTypes = await _middlewareImplementationTypes(
        argument,
        packageRoot,
        collection,
      );
      calls.add(
        _MiddlewareCall(
          name: name,
          controlId: controls[name],
          implementationTypes: implementationTypes,
        ),
      );
    }
    return _MiddlewareInspection(
      complete: complete,
      calls: calls,
      diagnostics: diagnostics,
    );
  }

  Expression? _returnedExpression(FunctionDeclaration declaration) {
    final body = declaration.functionExpression.body;
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody) {
      final returns = body.block.statements.whereType<ReturnStatement>();
      if (returns.length == 1) return returns.single.expression;
    }
    return null;
  }

  String? _middlewareName(Expression expression) {
    if (expression is ParenthesizedExpression) {
      return _middlewareName(expression.expression);
    }
    if (expression is MethodInvocation) {
      if (expression.methodName.element == null) return null;
      return expression.methodName.name;
    }
    if (expression is FunctionExpressionInvocation) {
      final function = expression.function;
      if (function is SimpleIdentifier && function.element != null) {
        return function.name;
      }
      if (function is PrefixedIdentifier &&
          function.identifier.element != null) {
        return function.identifier.name;
      }
      return null;
    }
    if (expression is SimpleIdentifier) {
      return expression.element == null ? null : expression.name;
    }
    if (expression is PrefixedIdentifier) {
      return expression.identifier.element == null
          ? null
          : expression.identifier.name;
    }
    return null;
  }

  Future<List<String>> _middlewareImplementationTypes(
    Expression expression,
    String packageRoot,
    AnalysisContextCollection collection,
  ) async {
    final function = switch (expression) {
      FunctionExpressionInvocation invocation => invocation.function,
      _ => null,
    };
    final element = switch (expression) {
      MethodInvocation invocation => invocation.methodName.element,
      _ => switch (function) {
        SimpleIdentifier identifier => identifier.element,
        PrefixedIdentifier identifier => identifier.identifier.element,
        _ => null,
      },
    };
    if (element is! ExecutableElement) return const [];

    final types = <String>{};
    final visited = <String>{};

    late Future<void> Function(ExecutableElement) inspectExecutable;
    late Future<void> Function(AstNode) inspectBody;

    inspectExecutable = (ExecutableElement executable) async {
      final source = executable.library.firstFragment.source;
      final filePath = path.normalize(source.fullName);
      final root = path.normalize(File(packageRoot).absolute.path);
      final rootWithSeparator = '$root${path.separator}';
      if (filePath != root && !filePath.startsWith(rootWithSeparator)) return;
      if (!visited.add('${filePath}|${executable.name}')) return;

      final resolved = await _resolveUnit(filePath, collection);
      if (resolved == null) return;
      final declarations = resolved.unit.declarations
          .whereType<FunctionDeclaration>()
          .where((candidate) => candidate.name.lexeme == executable.name)
          .toList(growable: false);
      final declaration = declarations.length == 1 ? declarations.single : null;
      if (declaration == null) {
        final owner = executable.enclosingElement;
        for (final classDeclaration
            in resolved.unit.declarations.whereType<ClassDeclaration>()) {
          if (owner is! InterfaceElement ||
              classDeclaration.name.lexeme != owner.name) {
            continue;
          }
          if (executable is ConstructorElement) {
            final constructors = classDeclaration.members
                .whereType<ConstructorDeclaration>()
                .where(
                  (candidate) =>
                      (candidate.name?.lexeme ?? '') == executable.name,
                )
                .toList(growable: false);
            if (constructors.length == 1) {
              await inspectBody(constructors.single.body);
              return;
            }
            continue;
          }
          final methods = classDeclaration.members
              .whereType<MethodDeclaration>()
              .where((candidate) => candidate.name.lexeme == executable.name)
              .toList(growable: false);
          if (methods.length == 1) {
            await inspectBody(methods.single.body);
            return;
          }
        }
        return;
      }
      await inspectBody(declaration.functionExpression.body);
    };

    inspectBody = (AstNode body) async {
      final invocations = <ExecutableElement>{};
      body.accept(
        _InitializationVisitor(
          onType: (name) {
            if (name != null && name.isNotEmpty) types.add(name);
          },
          onExecutable: (candidate) {
            if (candidate != null) invocations.add(candidate);
          },
        ),
      );
      for (final invocation in invocations) {
        await inspectExecutable(invocation);
      }
    };

    await inspectExecutable(element);
    return types.toList()..sort();
  }

  Future<ResolvedUnitResult?> _resolveUnit(
    String filePath,
    AnalysisContextCollection collection,
  ) async {
    final normalizedFile = path.normalize(File(filePath).absolute.path);
    final result = await collection
        .contextFor(normalizedFile)
        .currentSession
        .getResolvedUnit(normalizedFile);
    return result is ResolvedUnitResult ? result : null;
  }

  String? _resolveRoutePath(String packageRoot, String generatedPath) {
    final normalized = generatedPath.replaceAll('\\', '/');
    final segments = normalized.split('/')
      ..removeWhere((segment) => segment.isEmpty);
    if (segments.length < 3 || segments[0] != '..' || segments[1] != 'routes') {
      return null;
    }
    final relative = segments.sublist(2);
    if (relative.any((segment) => segment == '..' || segment == '.')) {
      return null;
    }
    final root = path.normalize(path.join(packageRoot, 'routes'));
    final resolved = path.normalize(path.joinAll([root, ...relative]));
    final rootWithSeparator = '$root${path.separator}';
    if (resolved != root && !resolved.startsWith(rootWithSeparator)) {
      return null;
    }
    return resolved;
  }

  String _nodeId(AdapterRequest request, String kind, String name) =>
      '${request.targetId}/${request.packageId}/$kind/$name';

  Diagnostic _error(String code, String message) => Diagnostic(
    code: code,
    stage: 'extract',
    severity: DiagnosticSeverity.error,
    owner: DiagnosticOwner.zuke,
    message: message,
    remediation:
        'Resolve the Dart Frog topology or mark the dimension indeterminate.',
  );

  Diagnostic _warning(String code, String message) => Diagnostic(
    code: code,
    stage: 'extract',
    severity: DiagnosticSeverity.warning,
    owner: DiagnosticOwner.zuke,
    message: message,
    remediation:
        'Resolve the Dart Frog topology or retain the affected dimension as indeterminate.',
  );
}

final class _TransportResult {
  final String kind;
  final bool complete;
  final List<String> implementationTypes;
  final List<Diagnostic> diagnostics;

  const _TransportResult({
    required this.kind,
    required this.complete,
    this.implementationTypes = const [],
    this.diagnostics = const [],
  });
}

final class _MiddlewareCall {
  final String name;
  final String? controlId;
  final List<String> implementationTypes;

  const _MiddlewareCall({
    required this.name,
    this.controlId,
    this.implementationTypes = const [],
  });
}

final class _MiddlewareInspection {
  final bool complete;
  final List<_MiddlewareCall> calls;
  final List<Diagnostic> diagnostics;

  const _MiddlewareInspection({
    required this.complete,
    required this.calls,
    required this.diagnostics,
  });
}

final class _InvocationVisitor extends RecursiveAstVisitor<void> {
  final void Function(InvocationExpression invocation) onInvocation;
  final void Function(MethodInvocation invocation)? onMethodInvocation;

  const _InvocationVisitor({
    required this.onInvocation,
    this.onMethodInvocation,
  });

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onInvocation(node);
    onMethodInvocation?.call(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    onInvocation(node);
    super.visitFunctionExpressionInvocation(node);
  }
}

final class _InitializationVisitor extends RecursiveAstVisitor<void> {
  final void Function(String? name) onType;
  final void Function(ExecutableElement? executable) onExecutable;

  const _InitializationVisitor({
    required this.onType,
    required this.onExecutable,
  });

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Provider factories and other callbacks are executed later, when a
    // request is handled. They are not process-initialization edges.
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    onType(
      node.constructorName.type.element?.name ??
          node.constructorName.type.name.lexeme,
    );
    final constructor = node.constructorName.element;
    if (constructor is ExecutableElement) onExecutable(constructor);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.element;
    final owner = method?.enclosingElement;
    if (owner is ClassElement) onType(owner.name);
    if (method is ExecutableElement) onExecutable(method);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    final element = switch (function) {
      SimpleIdentifier identifier => identifier.element,
      PrefixedIdentifier identifier => identifier.identifier.element,
      _ => null,
    };
    if (element is ExecutableElement) onExecutable(element);
    super.visitFunctionExpressionInvocation(node);
  }
}

final class _ControlVisitor extends RecursiveAstVisitor<void> {
  final Map<String, String> controls;

  const _ControlVisitor(this.controls);

  void _record(AnnotatedNode node, String name) {
    for (final annotation in node.metadata) {
      final element = annotation.elementAnnotation?.element;
      if (element == null || !isZukeAnnotation(element)) continue;
      if (zukeAnnotationName(element) != 'ProvidesControl') continue;
      final value = annotation.elementAnnotation?.computeConstantValue();
      final ids = value == null ? null : constantStrings(value, 'controlIds');
      if (ids != null && ids.isNotEmpty) controls[name] = ids.first;
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _record(node, node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _record(node, node.name.lexeme);
    super.visitMethodDeclaration(node);
  }
}

final class _MiddlewareResult {
  final bool complete;
  final List<Diagnostic> diagnostics;

  const _MiddlewareResult({required this.complete, required this.diagnostics});
}
