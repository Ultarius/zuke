/// Supported application-facing executable HTTP registrations shared by the runtime and the Dart
/// extractor. The same immutable application object is dispatched in
/// production and inspected for assurance; decorative parallel metadata is
/// deliberately not supported.
library;

/// A middleware continuation that handles one HTTP request.
typedef ZukeRequestHandler =
    Future<ZukeHttpResponse> Function(ZukeHttpRequest request);

/// Immutable application topology used for dispatch and inspection.
class ZukeHttpApplication {
  /// Registered routes.
  final List<ZukeRouteRegistration> routes;

  /// Registered failure pipelines.
  final List<ZukeFailurePipelineRegistration> failurePipelines;

  /// Registered logging pipelines.
  final List<ZukeLoggingPipelineRegistration> loggingPipelines;

  /// Creates an application topology.
  const ZukeHttpApplication({
    this.routes = const [],
    this.failurePipelines = const [],
    this.loggingPipelines = const [],
  });

  /// Dispatches [request] through the matching route and pipelines.
  Future<ZukeHttpResponse> dispatch(ZukeHttpRequest request) async {
    final route = routes.cast<ZukeRouteRegistration?>().firstWhere(
      (candidate) =>
          candidate!.method.toUpperCase() == request.method.toUpperCase() &&
          candidate.path == request.path,
      orElse: () => null,
    );
    if (route == null) {
      return const ZukeHttpResponse(404, body: {'error': 'NOT_FOUND'});
    }
    final failure = _failure(route.failurePipelineId);
    try {
      Future<ZukeHttpResponse> invoke(ZukeHttpRequest value) =>
          route.controller.handle(value);
      var next = invoke;
      for (final middleware in route.middleware.reversed) {
        final downstream = next;
        next = (value) => middleware
            .handle(value, downstream)
            .then((response) => response ?? const ZukeHttpResponse(204));
      }
      final response = await next(request);
      _emitLogging(route, request, response);
      await route.publicEgress.write(response);
      return response;
    } catch (error) {
      if (failure == null) rethrow;
      final response = await _runFailure(failure, error, request);
      _emitLogging(route, request, response);
      await failure.publicEgress.write(response);
      return response;
    }
  }

  void _emitLogging(
    ZukeRouteRegistration route,
    ZukeHttpRequest request,
    ZukeHttpResponse response,
  ) {
    final event = <String, Object?>{
      'method': request.method,
      'path': request.path,
      if (request.body is Map) ...{
        'first': (request.body as Map)['firstOperand'],
        'second': (request.body as Map)['secondOperand'],
        'operator': (request.body as Map)['operator'],
      },
      'status': response.statusCode,
      'correlationId': request.correlationId,
    };
    final ids = route.loggingPipelineIds.isEmpty
        ? loggingPipelines.map((pipeline) => pipeline.id)
        : route.loggingPipelineIds;
    for (final id in ids) {
      final pipeline = loggingPipelines.where(
        (candidate) => candidate.id == id,
      );
      if (pipeline.isEmpty) continue;
      var processed = event;
      for (final processor in pipeline.single.processors) {
        processed = processor.process(processed);
      }
      pipeline.single.sink.write(processed);
    }
  }

  ZukeFailurePipelineRegistration? _failure(String? id) {
    if (id != null) {
      for (final pipeline in failurePipelines) {
        if (pipeline.id == id) return pipeline;
      }
    }
    return failurePipelines.length == 1 ? failurePipelines.single : null;
  }

  Future<ZukeHttpResponse> _runFailure(
    ZukeFailurePipelineRegistration pipeline,
    Object error,
    ZukeHttpRequest request,
  ) async {
    for (final handler in pipeline.handlers) {
      return handler.handle(error, request);
    }
    return const ZukeHttpResponse(500, body: {'error': 'INTERNAL_ERROR'});
  }
}

/// A logical HTTP route and its executable pipeline.
class ZukeRouteRegistration {
  /// Stable logical endpoint identifier.
  final String endpointId;

  /// HTTP method accepted by the route.
  final String method;

  /// Request path accepted by the route.
  final String path;

  /// Middleware executed before the controller.
  final List<ZukeMiddleware> middleware;

  /// Controller invoked for the route.
  final ZukeController controller;

  /// Egress that writes the public response.
  final ZukePublicEgress publicEgress;

  /// Optional failure pipeline identifier.
  final String? failurePipelineId;

  /// Logging pipeline identifiers used by this route.
  final List<String> loggingPipelineIds;

  /// Creates a route registration.
  const ZukeRouteRegistration({
    required this.endpointId,
    required this.method,
    required this.path,
    required this.middleware,
    required this.controller,
    required this.publicEgress,
    this.failurePipelineId,
    this.loggingPipelineIds = const [],
  });
}

/// A route failure-handling pipeline.
class ZukeFailurePipelineRegistration {
  /// Stable pipeline identifier.
  final String id;

  /// Source identifier for the pipeline.
  final String sourceId;

  /// Error handlers in execution order.
  final List<ZukeErrorHandler> handlers;

  /// Egress that writes mapped failures.
  final ZukePublicEgress publicEgress;

  /// Creates a failure pipeline registration.
  const ZukeFailurePipelineRegistration({
    this.id = 'default-failure-pipeline',
    required this.sourceId,
    required this.handlers,
    required this.publicEgress,
  });
}

/// A route logging pipeline.
class ZukeLoggingPipelineRegistration {
  /// Stable pipeline identifier.
  final String id;

  /// Source identifier for the pipeline.
  final String sourceId;

  /// Processors applied to logging events.
  final List<ZukeLogProcessor> processors;

  /// Sink receiving processed events.
  final ZukeLogSink sink;

  /// Creates a logging pipeline registration.
  const ZukeLoggingPipelineRegistration({
    this.id = 'default-logging-pipeline',
    required this.sourceId,
    required this.processors,
    required this.sink,
  });
}

abstract interface class ZukeMiddleware {
  /// Stable middleware identifier.
  String get id;

  /// Handles a request and optionally calls [next].
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  );
}

abstract interface class ZukeController {
  /// Stable controller identifier.
  String get id;

  /// Handles one request.
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request);
}

abstract interface class ZukeErrorHandler {
  /// Stable error-handler identifier.
  String get id;

  /// Maps [error] to a public response.
  Future<ZukeHttpResponse> handle(Object error, ZukeHttpRequest request);
}

abstract interface class ZukeLogProcessor {
  /// Stable processor identifier.
  String get id;

  /// Processes one structured logging event.
  Map<String, Object?> process(Map<String, Object?> event);
}

abstract interface class ZukePublicEgress {
  /// Stable egress identifier.
  String get id;

  /// Writes a public response.
  Future<void> write(Object response);
}

abstract interface class ZukeLogSink {
  /// Stable sink identifier.
  String get id;

  /// Writes one processed logging event.
  void write(Map<String, Object?> event);
}

/// Immutable HTTP request data passed to the runtime topology.
class ZukeHttpRequest {
  /// HTTP method.
  final String method;

  /// Request path.
  final String path;

  /// Request headers.
  final Map<String, String> headers;

  /// Decoded request body.
  final Object? body;

  /// Original request bytes.
  final List<int> rawBody;

  /// Correlation identifier.
  final String correlationId;

  /// Runtime-specific request metadata.
  final Map<String, Object?> metadata;

  /// Creates an immutable request.
  const ZukeHttpRequest({
    required this.method,
    required this.path,
    this.headers = const {},
    this.body,
    this.rawBody = const [],
    this.correlationId = '',
    this.metadata = const {},
  });

  /// Returns a copy with the supplied body, bytes, or metadata replaced.
  ZukeHttpRequest copyWith({
    Object? body = _unset,
    List<int>? rawBody,
    Map<String, Object?>? metadata,
  }) => ZukeHttpRequest(
    method: method,
    path: path,
    headers: headers,
    body: identical(body, _unset) ? this.body : body,
    rawBody: rawBody ?? this.rawBody,
    correlationId: correlationId,
    metadata: metadata ?? this.metadata,
  );
}

const _unset = Object();

typedef ZukeHttpContext = ZukeHttpRequest;

/// Immutable HTTP response data returned by the runtime topology.
class ZukeHttpResponse {
  /// HTTP status code.
  final int statusCode;

  /// Response headers.
  final Map<String, String> headers;

  /// Encoded or decoded response body.
  final Object? body;

  /// Creates an immutable response.
  const ZukeHttpResponse(this.statusCode, {this.headers = const {}, this.body});
}
