/// Supported application-facing executable HTTP registrations shared by the runtime and the Dart
/// extractor. The same immutable application object is dispatched in
/// production and inspected for assurance; decorative parallel metadata is
/// deliberately not supported.
library;

typedef ZukeRequestHandler =
    Future<ZukeHttpResponse> Function(ZukeHttpRequest request);

class ZukeHttpApplication {
  final List<ZukeRouteRegistration> routes;
  final List<ZukeFailurePipelineRegistration> failurePipelines;
  final List<ZukeLoggingPipelineRegistration> loggingPipelines;

  const ZukeHttpApplication({
    this.routes = const [],
    this.failurePipelines = const [],
    this.loggingPipelines = const [],
  });

  Future<ZukeHttpResponse> dispatch(ZukeHttpRequest request) async {
    final route = routes.cast<ZukeRouteRegistration?>().firstWhere(
      (candidate) =>
          candidate!.method.toUpperCase() == request.method.toUpperCase() &&
          candidate.path == request.path,
      orElse: () => null,
    );
    if (route == null)
      return const ZukeHttpResponse(404, body: {'error': 'NOT_FOUND'});
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

class ZukeRouteRegistration {
  final String endpointId;
  final String method;
  final String path;
  final List<ZukeMiddleware> middleware;
  final ZukeController controller;
  final ZukePublicEgress publicEgress;
  final String? failurePipelineId;
  final List<String> loggingPipelineIds;

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

class ZukeFailurePipelineRegistration {
  final String id;
  final String sourceId;
  final List<ZukeErrorHandler> handlers;
  final ZukePublicEgress publicEgress;

  const ZukeFailurePipelineRegistration({
    this.id = 'default-failure-pipeline',
    required this.sourceId,
    required this.handlers,
    required this.publicEgress,
  });
}

class ZukeLoggingPipelineRegistration {
  final String id;
  final String sourceId;
  final List<ZukeLogProcessor> processors;
  final ZukeLogSink sink;

  const ZukeLoggingPipelineRegistration({
    this.id = 'default-logging-pipeline',
    required this.sourceId,
    required this.processors,
    required this.sink,
  });
}

abstract interface class ZukeMiddleware {
  String get id;
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  );
}

abstract interface class ZukeController {
  String get id;
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request);
}

abstract interface class ZukeErrorHandler {
  String get id;
  Future<ZukeHttpResponse> handle(Object error, ZukeHttpRequest request);
}

abstract interface class ZukeLogProcessor {
  String get id;
  Map<String, Object?> process(Map<String, Object?> event);
}

abstract interface class ZukePublicEgress {
  String get id;
  Future<void> write(Object response);
}

abstract interface class ZukeLogSink {
  String get id;
  void write(Map<String, Object?> event);
}

class ZukeHttpRequest {
  final String method;
  final String path;
  final Map<String, String> headers;
  final Object? body;
  final List<int> rawBody;
  final String correlationId;
  final Map<String, Object?> metadata;

  const ZukeHttpRequest({
    required this.method,
    required this.path,
    this.headers = const {},
    this.body,
    this.rawBody = const [],
    this.correlationId = '',
    this.metadata = const {},
  });

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

class ZukeHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Object? body;

  const ZukeHttpResponse(this.statusCode, {this.headers = const {}, this.body});
}
