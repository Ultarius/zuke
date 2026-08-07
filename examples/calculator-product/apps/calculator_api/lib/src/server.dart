import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'application.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

class CalculatorServer {
  final CalculatorApplication application;
  HttpServer? _server;
  CalculatorServer({CalculatorApplication? application})
    : application = application ?? CalculatorApplication();

  int get port => _server?.port ?? 0;

  Future<void> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    unawaited(_serve());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      // Route matching, middleware, failures, logging, and egress are all
      // owned by the registered application.  The server is only a transport
      // boundary and must not recreate topology in imperative branches.
      const maxBodyBytes = 16 * 1024;
      final bytes = <int>[];
      await for (final chunk in request) {
        final remaining = maxBodyBytes + 1 - bytes.length;
        if (remaining <= 0) break;
        bytes.addAll(chunk.take(remaining));
        if (bytes.length > maxBodyBytes) break;
      }
      final response = await application.registration.dispatch(
        ZukeHttpRequest(
          method: request.method,
          path: request.uri.path,
          headers: {
            'content-type': request.headers.contentType?.mimeType ?? '',
            if (request.headers.value('x-correlation-id') != null)
              'x-correlation-id': request.headers.value('x-correlation-id')!,
            if (request.headers.value('x-rate-limit-identity') != null)
              'x-rate-limit-identity': request.headers.value(
                'x-rate-limit-identity',
              )!,
          },
          rawBody: bytes,
          // Decoding happens in the registered body-size middleware, after
          // the size proof has had an opportunity to reject the request.
          body: null,
          correlationId: request.headers.value('x-correlation-id') ?? '',
        ),
      );
      request.response.statusCode = response.statusCode;
      response.headers.forEach(request.response.headers.set);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response.body));
      await request.response.close();
    }
  }
}
