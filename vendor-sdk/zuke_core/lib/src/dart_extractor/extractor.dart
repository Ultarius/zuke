import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' as analyzer_error;
import 'package:analyzer/source/line_info.dart';
import 'package:crypto/crypto.dart';
import '../adapter_sdk.dart';
import '../inspection.dart';

/// Resolved Dart extractor shared by the CLI and future analyzer/build-hook
/// surfaces.  It intentionally has no regex fallback: an unresolved source
/// fragment is unsafe evidence and is reported as an extraction error.
class DartExtractor implements FrameworkAdapter {
  static const annotationLibrary =
      'package:zuke_annotations/zuke_annotations.dart';

  @override
  AdapterInfo get adapterInfo => const AdapterInfo(
    id: 'zuke.dart',
    version: '1.0.0',
    compatibilityId: 'dart-analyzer-8.2-http-topology-v2',
  );

  @override
  Future<AdapterOutput> extract(
    String rootPath, {
    List<String> roots = const ['lib'],
  }) async {
    late final String root;
    try {
      root = Directory(rootPath).resolveSymbolicLinksSync();
    } catch (_) {
      root = Directory(rootPath).absolute.path;
    }
    final symbols = <ExtractedSymbol>[];
    final errors = <String>[];
    final graphNodes = <String, IrNode>{};
    final graphEdges = <IrEdge>[];
    var graphCompleteness = const GraphCompleteness(
      routeRegistration: CompletenessValue.notApplicable,
      middlewareOrder: CompletenessValue.notApplicable,
      failureFlow: CompletenessValue.notApplicable,
      logFlow: CompletenessValue.notApplicable,
      dynamicRegistration: CompletenessValue.notApplicable,
      externalVisibility: CompletenessValue.notApplicable,
    );
    final packageName = _packageName(root);
    final sourceDirectories = roots
        .map(
          (path) => Directory(
            path == '.' || path.isEmpty
                ? root
                : '$root${Platform.pathSeparator}$path',
          ),
        )
        .where((directory) => directory.existsSync())
        .toList();
    if (sourceDirectories.isEmpty) {
      return AdapterOutput(
        adapter: adapterInfo,
        completeness: const AdapterCompleteness(),
        symbols: const [],
        inputDigest: _computeDigest(root),
        diagnostics: const [],
        packageName: _packageName(root),
        packageRoot: root,
      );
    }

    final dartFiles =
        sourceDirectories
            .expand(
              (directory) =>
                  directory.listSync(recursive: true, followLinks: false),
            )
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .map((f) => f.absolute.resolveSymbolicLinksSync())
            .toSet()
            .toList()
          ..sort();

    final collection = AnalysisContextCollection(includedPaths: [root]);
    try {
      for (final file in dartFiles) {
        try {
          final result = await collection
              .contextFor(file)
              .currentSession
              .getResolvedUnit(file);
          if (result is! ResolvedUnitResult) {
            errors.add('$file: analyzer did not return a resolved unit');
            continue;
          }
          final severeErrors = result.diagnostics
              .where(
                (error) =>
                    error.diagnosticCode.severity ==
                    analyzer_error.DiagnosticSeverity.ERROR,
              )
              .toList();
          if (severeErrors.isNotEmpty) {
            for (final error in severeErrors) {
              errors.add('$file:${error.offset}: ${error.message}');
            }
            continue;
          }
          result.unit.accept(
            _ResolvedVisitor(
              packageName: packageName,
              file: file,
              lineInfo: result.lineInfo,
              symbols: symbols,
              errors: errors,
              graphNodes: graphNodes,
              graphEdges: graphEdges,
            ),
          );
        } catch (e) {
          errors.add('$file: resolution failed: $e');
        }
      }
    } finally {
      await collection.dispose();
    }

    // Registration topology and annotations are collected by separate AST
    // visits. Join an observed registered controller to its resolved
    // @ImplementsRequirement symbol only after every unit has been visited.
    for (final entry in graphNodes.entries.toList()) {
      final node = entry.value;
      if (node.kind != NodeKind.implementation ||
          !node.id.startsWith('implementation:')) {
        continue;
      }
      final typeName = node.id.substring('implementation:'.length);
      final implementation = symbols
          .where(
            (symbol) =>
                symbol.kind == 'requirementBoundary' &&
                symbol.symbolId.endsWith('#$typeName'),
          )
          .toList();
      if (implementation.length != 1) {
        errors.add(
          '${node.id}: registered controller must have exactly one '
          '@ImplementsRequirement declaration',
        );
        continue;
      }
      graphNodes[entry.key] = IrNode(
        id: node.id,
        kind: node.kind,
        target: implementation.single.target ?? node.target,
        role: node.role,
        variant: implementation.single.variant,
        slot: implementation.single.slot,
        source: node.source,
        properties: {
          ...node.properties,
          'requirementIds': implementation.single.requirementIds,
        },
      );
    }
    for (final entry in graphNodes.entries.toList()) {
      final node = entry.value;
      if (node.kind != NodeKind.provider || !node.id.startsWith('provider:')) {
        continue;
      }
      final typeName = node.id.substring('provider:'.length);
      final provider = symbols
          .where(
            (symbol) =>
                symbol.kind == 'controlProvider' &&
                symbol.symbolId.endsWith('#$typeName'),
          )
          .toList();
      if (provider.length != 1 || provider.single.controlIds.length != 1) {
        errors.add(
          '${node.id}: registered provider must have exactly one resolved '
          '@ProvidesControl declaration',
        );
        continue;
      }
      graphNodes[entry.key] = IrNode(
        id: node.id,
        kind: node.kind,
        target: provider.single.target ?? node.target,
        role: node.role,
        variant: provider.single.variant,
        slot: provider.single.slot,
        source: node.source,
        properties: {
          ...node.properties,
          'controlId': provider.single.controlIds.single,
          'providerKind': provider.single.providerKind,
          'layer': provider.single.layer,
        },
      );
    }

    symbols.sort((a, b) {
      final left = '${a.source.uri}:${a.source.offset}:${a.kind}:${a.symbolId}';
      final right =
          '${b.source.uri}:${b.source.offset}:${b.kind}:${b.symbolId}';
      return left.compareTo(right);
    });
    if (graphNodes.isNotEmpty) {
      final incomplete = errors.any((error) => error.contains('dynamic'));
      graphCompleteness = GraphCompleteness(
        routeRegistration: incomplete
            ? CompletenessValue.indeterminate
            : CompletenessValue.complete,
        middlewareOrder: incomplete
            ? CompletenessValue.indeterminate
            : CompletenessValue.complete,
        failureFlow: incomplete
            ? CompletenessValue.indeterminate
            : CompletenessValue.complete,
        logFlow: incomplete
            ? CompletenessValue.indeterminate
            : CompletenessValue.complete,
        dynamicRegistration: incomplete
            ? CompletenessValue.indeterminate
            : CompletenessValue.complete,
        externalVisibility: CompletenessValue.notApplicable,
      );
      // Runtime registrations are first-class provider candidates even when
      // the implementation class has no annotation.  They are emitted from
      // the same resolved constructor expressions as the graph, so mapping
      // cannot silently accept a decorative provider declaration.
      for (final node in graphNodes.values) {
        if (node.kind != NodeKind.provider) continue;
        final control = node.properties['controlId'];
        if (control is! String || control.isEmpty) continue;
        final sourceUri =
            node.properties['sourceUri']?.toString() ??
            'package:$packageName/unknown.dart';
        final line = (node.properties['sourceLine'] as num?)?.toInt() ?? 1;
        final providerKind = node.properties['providerKind']?.toString();
        if (providerKind == null || providerKind.isEmpty) {
          errors.add(
            '${node.id}: registered provider must resolve a declared '
            '@ProvidesControl provider kind',
          );
          continue;
        }
        symbols.add(
          ExtractedSymbol(
            kind: 'controlProvider',
            role: 'provider',
            symbolId: '$sourceUri#${node.id}',
            controlIds: [control],
            providerKind: providerKind,
            target: 'backend',
            source: ExtractedSourceLocation(
              uri: sourceUri,
              offset: 0,
              length: 0,
              line: line,
              column: 1,
            ),
          ),
        );
      }
    }
    symbols.sort((a, b) {
      final left = '${a.source.uri}:${a.source.offset}:${a.kind}:${a.symbolId}';
      final right =
          '${b.source.uri}:${b.source.offset}:${b.kind}:${b.symbolId}';
      return left.compareTo(right);
    });
    return AdapterOutput(
      adapter: adapterInfo,
      completeness: AdapterCompleteness(
        annotationTargets: errors.isEmpty
            ? CompletenessValue.complete
            : CompletenessValue.indeterminate,
        graph: graphCompleteness,
      ),
      symbols: symbols,
      inputDigest: _computeDigest(root),
      diagnostics: errors
          .map(
            (message) => Diagnostic(
              code: 'DART-EXTRACT-001',
              message: message,
              severity: DiagnosticSeverity.error,
            ),
          )
          .toList(),
      packageName: packageName,
      packageRoot: root,
      graph: graphNodes.isEmpty
          ? null
          : IrGraph(
              nodes: graphNodes.values.toList(),
              edges: graphEdges,
              completeness: graphCompleteness,
            ),
    );
  }

  String _packageName(String root) {
    final pubspec = File('$root${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) {
      throw FormatException('Dart package root has no pubspec.yaml: $root');
    }
    final match = RegExp(
      r'^name:\s*([A-Za-z0-9_]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    final name = match?.group(1);
    if (name == null || name.isEmpty) {
      throw FormatException('pubspec.yaml has no valid package name: $root');
    }
    return name;
  }

  String _computeDigest(String root) {
    final files = <File>[];
    for (final path in [
      '$root${Platform.pathSeparator}pubspec.yaml',
      '$root${Platform.pathSeparator}analysis_options.yaml',
    ]) {
      final file = File(path);
      if (file.existsSync()) files.add(file);
    }
    for (final rootName in ['lib', 'test']) {
      final directory = Directory('$root${Platform.pathSeparator}$rootName');
      if (directory.existsSync()) {
        files.addAll(
          directory
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
        );
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final bytes = <int>[];
    final normalizedRoot = root
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/$'), '');
    for (final file in files) {
      final normalized = file.absolute.path.replaceAll('\\', '/');
      final relative = normalized.startsWith('$normalizedRoot/')
          ? normalized.substring(normalizedRoot.length + 1)
          : normalized;
      bytes.addAll(utf8.encode(relative));
      bytes.add(0);
      bytes.addAll(canonicalDigestBytes(relative, file.readAsBytesSync()));
      bytes.add(0);
    }
    bytes.addAll(utf8.encode('${adapterInfo.id}@${adapterInfo.version}'));
    return sha256.convert(bytes).toString();
  }
}

class _ResolvedVisitor extends RecursiveAstVisitor<void> {
  final String packageName;
  final String file;
  final LineInfo lineInfo;
  final List<ExtractedSymbol> symbols;
  final List<String> errors;
  final Map<String, IrNode> graphNodes;
  final List<IrEdge> graphEdges;

  _ResolvedVisitor({
    required this.packageName,
    required this.file,
    required this.lineInfo,
    required this.symbols,
    required this.errors,
    required this.graphNodes,
    required this.graphEdges,
  });

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _visitRuntimeRegistration(node);
    super.visitInstanceCreationExpression(node);
  }

  void _visitRuntimeRegistration(InstanceCreationExpression node) {
    final type = node.constructorName.type.element;
    final uri = type?.library?.firstFragment.source.uri.toString();
    final name = node.constructorName.type.name.lexeme;

    final isMatchingName = const {
      'ZukeHttpApplication',
      'ZukeRouteRegistration',
      'ZukeFailurePipelineRegistration',
      'ZukeLoggingPipelineRegistration',
    }.contains(name);

    if (isMatchingName &&
        uri != 'package:zuke_http_runtime/zuke_http_runtime.dart') {
      errors.add(
        '${file}:${lineInfo.getLocation(node.offset).lineNumber}: '
        'unresolved registration for $name',
      );
    }

    final isRuntimeType =
        uri == 'package:zuke_http_runtime/zuke_http_runtime.dart' &&
        isMatchingName;
    if (!isRuntimeType) return;
    final args = <String, Expression>{};
    for (final argument in node.argumentList.arguments) {
      if (argument is NamedExpression) {
        args[argument.name.label.name] = argument.expression;
      }
    }
    String? stringValue(Expression? expression) =>
        expression is StringLiteral ? expression.stringValue : null;

    List<Expression> creations(Expression? expression, String fieldName) {
      if (expression == null) return const [];
      if (expression is! ListLiteral) {
        errors.add(
          '${file}:${lineInfo.getLocation(expression.offset).lineNumber}: '
          '$fieldName must be a list literal',
        );
        return const [];
      }
      final results = <Expression>[];
      for (final element in expression.elements) {
        if (element is Expression) {
          results.add(element);
        } else {
          errors.add(
            '${file}:${lineInfo.getLocation(element.offset).lineNumber}: '
            'mutation or dynamic element in registration list $fieldName is not supported',
          );
        }
      }
      return results;
    }

    List<String> resolveTypes(Expression? expr) {
      if (expr == null) return const [];
      if (expr is InstanceCreationExpression) {
        final name =
            expr.constructorName.type.element?.name ??
            expr.constructorName.type.name.lexeme;
        return [name];
      }
      if (expr is ConditionalExpression) {
        return [
          ...resolveTypes(expr.thenExpression),
          ...resolveTypes(expr.elseExpression),
        ];
      }
      if (expr is MethodInvocation) {
        final target = expr.target;
        if (target is SimpleIdentifier) {
          if (target.name.startsWith(RegExp(r'[A-Z]'))) {
            return [target.name];
          }
        }
        final methodElement = expr.methodName.element;
        if (methodElement is MethodElement) {
          final enclosing = methodElement.enclosingElement;
          if (enclosing is InterfaceElement) {
            final name = enclosing.name;
            if (name != null) return [name];
          }
        }
      }
      return ['<dynamic>'];
    }

    IrNode nodeFor(
      String id,
      NodeKind kind, {
      String? flow,
      Map<String, Object?> properties = const {},
    }) {
      return graphNodes.putIfAbsent(
        id,
        () => IrNode(
          id: id,
          kind: kind,
          target: kind == NodeKind.provider || kind == NodeKind.implementation
              ? 'backend'
              : null,
          role: kind == NodeKind.provider
              ? 'provider'
              : kind == NodeKind.implementation
              ? 'implementation'
              : null,
          properties: {
            'sourceUri': 'package:$packageName/${_relativeLibPath(file)}',
            'sourceLine': lineInfo.getLocation(node.offset).lineNumber,
            if (flow != null) 'flow': flow,
            ...properties,
          },
        ),
      );
    }

    IrEdge edge(String source, String target, EdgeKind kind) {
      final value = IrEdge(sourceId: source, targetId: target, kind: kind);
      if (!graphEdges.any(
        (e) => e.sourceId == source && e.targetId == target && e.kind == kind,
      )) {
        graphEdges.add(value);
      }
      return value;
    }

    if (name == 'ZukeHttpApplication') {
      for (final route in creations(args['routes'], 'routes')) {
        final routeArgs = <String, Expression>{};
        if (route is InstanceCreationExpression) {
          for (final argument in route.argumentList.arguments) {
            if (argument is NamedExpression) {
              routeArgs[argument.name.label.name] = argument.expression;
            }
          }
        } else {
          errors.add(
            '${file}:${lineInfo.getLocation(route.offset).lineNumber}: dynamic ZukeRouteRegistration',
          );
          continue;
        }
        final endpoint = stringValue(routeArgs['endpointId']);
        final path = stringValue(routeArgs['path']);
        if (endpoint == null || path == null) {
          errors.add(
            '${file}:${lineInfo.getLocation(route.offset).lineNumber}: dynamic ZukeRouteRegistration',
          );
          continue;
        }
        final ingress = 'ingress:$endpoint';
        final routeId = 'route:$endpoint';
        nodeFor(
          ingress,
          NodeKind.entryPoint,
          flow: 'ingress',
          properties: {'endpointId': endpoint},
        );
        nodeFor(
          routeId,
          NodeKind.entryPoint,
          properties: {'endpointId': endpoint, 'path': path},
        );
        edge(ingress, routeId, EdgeKind.routesTo);
        var previous = routeId;
        for (final middleware in creations(
          routeArgs['middleware'],
          'middleware',
        )) {
          final middlewareIds = resolveTypes(middleware);
          for (final middlewareId in middlewareIds) {
            final id = 'provider:$middlewareId';
            nodeFor(
              id,
              NodeKind.provider,
              properties: {'providerKind': middlewareId},
            );
            edge(previous, id, EdgeKind.precedes);
            previous = id;
          }
        }
        final controllers = resolveTypes(routeArgs['controller']);
        for (final controller in controllers) {
          final implementation = 'implementation:$controller';
          nodeFor(
            implementation,
            NodeKind.implementation,
            properties: const {},
          );
          edge(previous, implementation, EdgeKind.precedes);
        }
      }
      for (final failure in creations(
        args['failurePipelines'],
        'failurePipelines',
      )) {
        if (failure is InstanceCreationExpression) {
          _visitFailurePipeline(
            failure,
            nodeFor,
            edge,
            stringValue,
            resolveTypes,
            creations,
          );
        } else {
          errors.add(
            '${file}:${lineInfo.getLocation(failure.offset).lineNumber}: dynamic ZukeFailurePipelineRegistration',
          );
        }
      }
      for (final logging in creations(
        args['loggingPipelines'],
        'loggingPipelines',
      )) {
        if (logging is InstanceCreationExpression) {
          _visitLoggingPipeline(
            logging,
            nodeFor,
            edge,
            stringValue,
            resolveTypes,
            creations,
          );
        } else {
          errors.add(
            '${file}:${lineInfo.getLocation(logging.offset).lineNumber}: dynamic ZukeLoggingPipelineRegistration',
          );
        }
      }
    }
  }

  void _visitFailurePipeline(
    InstanceCreationExpression pipeline,
    IrNode Function(
      String,
      NodeKind, {
      String? flow,
      Map<String, Object?> properties,
    })
    nodeFor,
    IrEdge Function(String, String, EdgeKind) edge,
    String? Function(Expression?) stringValue,
    List<String> Function(Expression?) resolveTypes,
    List<Expression> Function(Expression?, String) creations,
  ) {
    final args = <String, Expression>{};
    for (final argument in pipeline.argumentList.arguments) {
      if (argument is NamedExpression)
        args[argument.name.label.name] = argument.expression;
    }
    final source = stringValue(args['sourceId']);
    if (source == null) {
      errors.add('$file: dynamic ZukeFailurePipelineRegistration source');
      return;
    }
    final sourceId = 'failure:$source';
    nodeFor(sourceId, NodeKind.entryPoint, flow: 'failure');
    if (args['publicEgress'] == null) {
      errors.add('$file: dynamic ZukeFailurePipelineRegistration publicEgress');
      return;
    }
    final handlers = creations(args['handlers'], 'handlers');
    var previous = sourceId;
    for (final handler in handlers) {
      final handlerIds = resolveTypes(handler);
      for (final handlerId in handlerIds) {
        final id = 'provider:$handlerId';
        nodeFor(
          id,
          NodeKind.provider,
          flow: 'error-handler',
          properties: const {},
        );
        edge(previous, id, EdgeKind.flowsTo);
        previous = id;
      }
    }
    final egressIds = resolveTypes(args['publicEgress']);
    if (egressIds.contains('<dynamic>')) {
      errors.add('$file: dynamic ZukeFailurePipelineRegistration publicEgress');
      return;
    }
    for (final egressId in egressIds) {
      final egress = 'egress:$egressId';
      nodeFor(egress, NodeKind.entryPoint, flow: 'public-egress');
      edge(previous, egress, EdgeKind.flowsTo);
    }
  }

  void _visitLoggingPipeline(
    InstanceCreationExpression pipeline,
    IrNode Function(
      String,
      NodeKind, {
      String? flow,
      Map<String, Object?> properties,
    })
    nodeFor,
    IrEdge Function(String, String, EdgeKind) edge,
    String? Function(Expression?) stringValue,
    List<String> Function(Expression?) resolveTypes,
    List<Expression> Function(Expression?, String) creations,
  ) {
    final args = <String, Expression>{};
    for (final argument in pipeline.argumentList.arguments) {
      if (argument is NamedExpression)
        args[argument.name.label.name] = argument.expression;
    }
    final source = stringValue(args['sourceId']);
    if (source == null) {
      errors.add('$file: dynamic ZukeLoggingPipelineRegistration source');
      return;
    }
    final sourceId = 'sensitive:$source';
    nodeFor(sourceId, NodeKind.entryPoint, flow: 'sensitive-data');
    if (args['sink'] == null) {
      errors.add('$file: dynamic ZukeLoggingPipelineRegistration sink');
      return;
    }
    final processors = creations(args['processors'], 'processors');
    var previous = sourceId;
    for (final processor in processors) {
      final processorIds = resolveTypes(processor);
      for (final processorId in processorIds) {
        final id = 'provider:$processorId';
        nodeFor(
          id,
          NodeKind.provider,
          flow: 'log-processor',
          properties: const {},
        );
        edge(previous, id, EdgeKind.flowsTo);
        previous = id;
      }
    }
    final sinkIds = resolveTypes(args['sink']);
    if (sinkIds.contains('<dynamic>')) {
      errors.add('$file: dynamic ZukeLoggingPipelineRegistration sink');
      return;
    }
    for (final sinkId in sinkIds) {
      final sink = 'sink:$sinkId';
      nodeFor(sink, NodeKind.sink, flow: 'log-sink');
      edge(previous, sink, EdgeKind.flowsTo);
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _visitDeclaration(node, node.name.lexeme, 'class');
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _visitDeclaration(node, node.name.lexeme, 'mixin');
    super.visitMixinDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _visitDeclaration(node, node.name.lexeme, 'function');
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _visitDeclaration(
      node,
      node.name.lexeme,
      node.isGetter ? 'getter' : 'method',
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _visitDeclaration(node, node.name.lexeme, 'extensionType');
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _visitDeclaration(node, node.name?.lexeme ?? '<extension>', 'extension');
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _visitDeclaration(node, node.name.lexeme, 'enum');
    super.visitEnumDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _visitDeclaration(
      node,
      node.name?.lexeme ?? '<constructor>',
      'constructor',
    );
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _visitDeclaration(node, node.name.lexeme, 'typedef');
    super.visitGenericTypeAlias(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final name = node.fields.variables.isEmpty
        ? '<field>'
        : node.fields.variables.first.name.lexeme;
    _visitDeclaration(node, name, 'field');
    super.visitFieldDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    final name = node.variables.variables.isEmpty
        ? '<top-level>'
        : node.variables.variables.first.name.lexeme;
    _visitDeclaration(node, name, 'topLevelVariable');
    super.visitTopLevelVariableDeclaration(node);
  }

  void _visitDeclaration(AnnotatedNode node, String name, String targetKind) {
    for (final annotation in node.metadata) {
      final elementAnnotation = annotation.elementAnnotation;
      final element = elementAnnotation?.element;
      if (element == null || !isZukeAnnotation(element)) continue;
      final annotationName = zukeAnnotationName(element)!;
      final offset = annotation.offset;
      final location = lineInfo.getLocation(offset);
      final source = ExtractedSourceLocation(
        uri: 'package:$packageName/${_relativeLibPath(file)}',
        offset: offset,
        length: annotation.length,
        line: location.lineNumber,
        column: location.columnNumber,
      );
      final value = elementAnnotation!.computeConstantValue();
      if (value == null || value.hasKnownValue == false) {
        errors.add(
          '${source.uri}:${source.line}: $annotationName must be a compile-time constant',
        );
        continue;
      }
      if (!supportsZukeAnnotationTarget(annotationName, targetKind)) {
        errors.add(
          '${source.uri}:${source.line}: @$annotationName is not supported '
          'on $targetKind declarations',
        );
        continue;
      }
      switch (annotationName) {
        case 'ImplementsRequirement':
          _addIds(
            value,
            'requirementIds',
            'requirementBoundary',
            'domain',
            name,
            source,
            target: _fieldString(value, 'target') ?? 'backend',
            variant: _fieldString(value, 'variant') ?? 'default',
            slot: _fieldString(value, 'slot') ?? 'primary',
          );
          break;
        case 'PresentsRequirement':
          _addIds(
            value,
            'requirementIds',
            'presentationBoundary',
            'flutter',
            name,
            source,
            target: _fieldString(value, 'target') ?? 'flutter',
            variant: _fieldString(value, 'variant') ?? 'default',
            slot: _fieldString(value, 'slot') ?? 'primary',
          );
          break;
        case 'VerifiesRequirement':
          _addIds(
            value,
            'requirementIds',
            'verificationBoundary',
            'test',
            name,
            source,
            evidenceType: _fieldString(value, 'evidenceType'),
            target: _fieldString(value, 'target'),
            variant: _fieldString(value, 'variant') ?? 'default',
            scenarioIds: _strings(value.getField('scenarioIds')) ?? const [],
          );
          break;
        case 'ProvidesControl':
          _addProvider(value, name, source);
          break;
        case 'ZukeBinding':
          _addBinding(value, name, source);
          break;
        default:
          break;
      }
      if (annotationName != 'ZukeBinding' &&
          annotationName != 'ImplementsRequirement' &&
          annotationName != 'PresentsRequirement' &&
          annotationName != 'VerifiesRequirement' &&
          annotationName != 'ProvidesControl') {
        continue;
      }
    }
  }

  void _addIds(
    DartObject value,
    String field,
    String kind,
    String role,
    String name,
    ExtractedSourceLocation source, {
    String? evidenceType,
    String? target,
    String variant = 'default',
    String slot = 'primary',
    List<String> scenarioIds = const [],
  }) {
    final ids = _strings(value.getField(field));
    if (ids == null || ids.isEmpty) {
      errors.add(
        '${source.uri}:${source.line}: annotation field $field must be a non-empty constant list',
      );
      return;
    }
    symbols.add(
      ExtractedSymbol(
        kind: kind,
        role: role,
        symbolId: '${source.uri}#$name',
        requirementIds: ids,
        variant: variant,
        slot: slot,
        target: target,
        evidenceType: evidenceType,
        scenarioIds: scenarioIds,
        source: source,
      ),
    );
  }

  void _addProvider(
    DartObject value,
    String name,
    ExtractedSourceLocation source,
  ) {
    final ids = _strings(value.getField('controlIds'));
    if (ids == null || ids.isEmpty) {
      errors.add(
        '${source.uri}:${source.line}: @ProvidesControl requires constant control IDs',
      );
      return;
    }
    final kind = _enumName(value.getField('kind'));
    final layer = _enumName(value.getField('layer'));
    symbols.add(
      ExtractedSymbol(
        kind: 'controlProvider',
        role: 'provider',
        symbolId: '${source.uri}#$name',
        controlIds: ids,
        providerKind: kind,
        layer: layer,
        target: _fieldString(value, 'target') ?? 'backend',
        variant: _fieldString(value, 'variant') ?? 'default',
        slot: _fieldString(value, 'slot') ?? 'primary',
        source: source,
      ),
    );
  }

  void _addBinding(
    DartObject value,
    String name,
    ExtractedSourceLocation source,
  ) {
    final field = value.getField('bindingId');
    final bindingId = field?.toStringValue();
    if (bindingId == null || bindingId.isEmpty) {
      errors.add(
        '${source.uri}:${source.line}: @ZukeBinding requires a constant binding ID',
      );
      return;
    }
    symbols.add(
      ExtractedSymbol(
        kind: 'binding',
        role: 'flutter',
        symbolId: '${source.uri}#$name',
        bindingId: bindingId,
        variant: _fieldString(value, 'variant') ?? 'default',
        target: _fieldString(value, 'target') ?? 'flutter',
        source: source,
      ),
    );
  }

  List<String>? _strings(DartObject? value) {
    if (value == null) return null;
    final list = value.toListValue();
    if (list == null) return null;
    final result = <String>[];
    for (final item in list) {
      final string = item.toStringValue();
      if (string == null || string.isEmpty) return null;
      result.add(string);
    }
    return result;
  }

  String? _enumName(DartObject? value) => value?.variable?.name;

  String _relativeLibPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final marker = '/lib/';
    final index = normalized.indexOf(marker);
    return index >= 0
        ? normalized.substring(index + marker.length)
        : normalized.split('/').last;
  }

  String? _fieldString(DartObject value, String field) =>
      value.getField(field)?.toStringValue();
}
