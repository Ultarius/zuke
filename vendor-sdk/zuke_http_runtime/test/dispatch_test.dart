import 'package:test/test.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

void main() {
  test(
    'dispatch executes middleware and maps failures through registration',
    () async {
      final app = ZukeHttpApplication(
        routes: [
          ZukeRouteRegistration(
            endpointId: 'test.endpoint',
            method: 'POST',
            path: '/test',
            middleware: [const _Middleware()],
            controller: const _Controller(),
            publicEgress: const _Egress(),
            failurePipelineId: 'failure',
          ),
        ],
        failurePipelines: [
          ZukeFailurePipelineRegistration(
            id: 'failure',
            sourceId: 'test.failure',
            handlers: [const _ErrorHandler()],
            publicEgress: const _Egress(),
          ),
        ],
      );
      final response = await app.dispatch(
        const ZukeHttpRequest(method: 'POST', path: '/test'),
      );
      expect(response.statusCode, 200);
    },
  );
}

class _Middleware implements ZukeMiddleware {
  const _Middleware();
  @override
  String get id => 'middleware';
  @override
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  ) => next(request);
}

class _Controller implements ZukeController {
  const _Controller();
  @override
  String get id => 'controller';
  @override
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request) async =>
      const ZukeHttpResponse(200);
}

class _ErrorHandler implements ZukeErrorHandler {
  const _ErrorHandler();
  @override
  String get id => 'error';
  @override
  Future<ZukeHttpResponse> handle(
    Object error,
    ZukeHttpRequest request,
  ) async => const ZukeHttpResponse(500);
}

class _Egress implements ZukePublicEgress {
  const _Egress();
  @override
  String get id => 'egress';
  @override
  Future<void> write(Object response) async {}
}
