/// Supported application-facing HTTP scenario-driver API.
import 'package:zuke_runner/zuke_runner.dart';
import 'dart:convert';
import 'dart:io';

class HttpRequestSpec {
  final String endpointId;
  final String method;
  final Object? body;
  final Map<String, String> headers;
  const HttpRequestSpec({
    required this.endpointId,
    required this.method,
    this.body,
    this.headers = const {},
  });
}

class HttpResponseSpec {
  final int statusCode;
  final Object? body;
  final Duration latency;
  const HttpResponseSpec({
    required this.statusCode,
    this.body,
    this.latency = Duration.zero,
  });
}

/// Resolves a logical endpoint's base URL from declared runner configuration.
/// A feature never receives a host URL; deployments choose it through a named
/// environment variable such as `CALCULATOR_TEST_API_URL`.
final class EndpointBaseUrlResolver {
  const EndpointBaseUrlResolver();

  Uri resolve(
    Map<Object?, Object?> endpoint, {
    Map<String, String>? environment,
  }) {
    final inline = endpoint['baseUrl'];
    final fromEnvironment = endpoint['baseUrlFrom'];
    if (inline != null && fromEnvironment != null) {
      throw const FormatException(
        'Endpoint must declare exactly one of baseUrl or baseUrlFrom',
      );
    }
    final value = inline is String
        ? inline
        : fromEnvironment is String
        ? (environment ?? Platform.environment)[fromEnvironment]
        : null;
    if (value == null || value.trim().isEmpty) {
      final name = fromEnvironment is String
          ? ' environment $fromEnvironment'
          : '';
      throw FormatException('Endpoint base URL$name is not configured');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw FormatException('Endpoint base URL must be absolute: $value');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException('Endpoint base URL must use HTTP(S): $value');
    }
    return uri;
  }
}

abstract class HttpScenarioDriver<W extends ScenarioWorld>
    extends HttpDriverFactory<W> {
  const HttpScenarioDriver();
  Future<HttpResponseSpec> request(W world, HttpRequestSpec request);
  Future<void> resetFixtures(W world);
}

abstract interface class HttpServerFactory {
  Future<Uri> start();
  Future<void> stop();
  Future<void> resetFixtures();
}

/// A bounded, deterministic request assertion surface used by generated HTTP
/// steps. It intentionally accepts logical endpoint IDs only.
class HttpAssertions {
  static Object? jsonPointer(Object? value, String pointer) {
    if (pointer.isEmpty || pointer == '/') return value;
    var current = value;
    for (final token in pointer.split('/').skip(1)) {
      final key = token.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is Map) {
        current = current[key];
      } else if (current is List) {
        final index = int.tryParse(key);
        if (index == null) return null;
        if (index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  static void expectStatus(HttpResponseSpec response, int status) {
    if (response.statusCode != status) {
      throw StateError('Expected HTTP $status, got ${response.statusCode}');
    }
  }

  static void expectJson(
    HttpResponseSpec response,
    String pointer,
    Object? expected,
  ) {
    final actual = jsonPointer(response.body, pointer);
    if (actual != expected) {
      throw StateError('Expected $pointer=$expected, got $actual');
    }
  }

  static void expectLatency(HttpResponseSpec response, Duration maximum) {
    if (response.latency > maximum) {
      throw StateError('Latency ${response.latency} exceeded $maximum');
    }
  }
}

/// Reusable HTTP vocabulary. Projects supply the response produced by their
/// preceding logical-endpoint step; vendor steps never embed an environment
/// URL or make a second request.
List<StepDefinition<W>> httpVendorSteps<W extends ScenarioWorld>({
  required HttpResponseSpec? Function(W world) latestResponse,
  bool Function(Object? body, String schemaId)? matchesSchema,
}) => [
  StepDefinition(
    tier: StepTier.vendor,
    target: 'http',
    pattern: RegExp(r'^the response status is (\d+)$'),
    action: (world, _, arguments) {
      HttpAssertions.expectStatus(
        _requireResponse(latestResponse(world)),
        int.parse(arguments['1']!),
      );
    },
  ),
  StepDefinition(
    tier: StepTier.vendor,
    target: 'http',
    pattern: RegExp(r'^the response error code is "([^"]+)"$'),
    action: (world, _, arguments) {
      HttpAssertions.expectJson(
        _requireResponse(latestResponse(world)),
        '/error/code',
        arguments['1'],
      );
    },
  ),
  StepDefinition(
    tier: StepTier.vendor,
    target: 'http',
    pattern: RegExp(r'^the response body at "([^"]+)" contains "([^"]*)"$'),
    action: (world, _, arguments) {
      final value = HttpAssertions.jsonPointer(
        _requireResponse(latestResponse(world)).body,
        arguments['1']!,
      );
      if (value is! String || !value.contains(arguments['2']!)) {
        throw StateError(
          'Expected ${arguments['1']} to contain ${arguments['2']}',
        );
      }
    },
  ),
  StepDefinition(
    tier: StepTier.vendor,
    target: 'http',
    pattern: RegExp(
      r'^the response body at "([^"]+)" does not contain "([^"]*)"$',
    ),
    action: (world, _, arguments) {
      final value = HttpAssertions.jsonPointer(
        _requireResponse(latestResponse(world)).body,
        arguments['1']!,
      );
      if (value is String && value.contains(arguments['2']!)) {
        throw StateError(
          'Expected ${arguments['1']} not to contain ${arguments['2']}',
        );
      }
    },
  ),
  StepDefinition(
    tier: StepTier.vendor,
    target: 'http',
    pattern: RegExp(r'^the response conforms to schema "([^"]+)"$'),
    action: (world, _, arguments) {
      if (matchesSchema == null) {
        throw StateError(
          'No schema matcher is configured for vendor HTTP steps',
        );
      }
      if (!matchesSchema(
        _requireResponse(latestResponse(world)).body,
        arguments['1']!,
      )) {
        throw StateError(
          'Response does not conform to schema ${arguments['1']}',
        );
      }
    },
  ),
];

HttpResponseSpec _requireResponse(HttpResponseSpec? response) {
  if (response == null) throw StateError('No HTTP response is available');
  return response;
}

/// Project-owned HTTP driver primitive. Endpoint IDs are resolved through the
/// generated contract map; features never carry environment URLs.
class JsonHttpDriver extends HttpScenarioDriver<MapScenarioWorld> {
  final Uri baseUri;
  final Map<String, String> endpoints;
  final HttpClient client;

  JsonHttpDriver({
    required this.baseUri,
    required this.endpoints,
    HttpClient? client,
  }) : client = client ?? HttpClient();

  @override
  Future<MapScenarioWorld> create() async => MapScenarioWorld();

  @override
  Future<void> dispose(MapScenarioWorld world) async =>
      client.close(force: true);

  @override
  Future<void> resetFixtures(MapScenarioWorld world) async {}

  @override
  Future<HttpResponseSpec> request(
    MapScenarioWorld world,
    HttpRequestSpec request,
  ) async {
    final path = endpoints[request.endpointId];
    if (path == null)
      throw StateError('Unknown logical endpoint: ${request.endpointId}');
    final uri = baseUri.resolve(path);
    final stopwatch = Stopwatch()..start();
    final httpRequest = await client.openUrl(request.method, uri);
    httpRequest.headers.contentType = ContentType.json;
    request.headers.forEach(httpRequest.headers.set);
    if (request.body != null) httpRequest.write(jsonEncode(request.body));
    final response = await httpRequest.close();
    final bodyText = await utf8.decoder.bind(response).join();
    stopwatch.stop();
    Object? body;
    if (bodyText.isNotEmpty) {
      try {
        body = jsonDecode(bodyText);
      } on FormatException {
        body = bodyText;
      }
    }
    return HttpResponseSpec(
      statusCode: response.statusCode,
      body: body,
      latency: stopwatch.elapsed,
    );
  }
}
