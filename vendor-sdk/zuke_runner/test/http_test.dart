import 'package:zuke_runner/http.dart';
import 'package:zuke_runner/zuke_runner.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:test/test.dart';

void main() {
  test('JSON pointer assertions are deterministic and RFC6901 compatible', () {
    const response = HttpResponseSpec(
      statusCode: 200,
      body: {
        'error': {'message': 'invalid'},
        'items': [1, 2],
      },
    );
    expect(
      HttpAssertions.jsonPointer(response.body, '/error/message'),
      'invalid',
    );
    expect(HttpAssertions.jsonPointer(response.body, '/items/1'), 2);
    HttpAssertions.expectStatus(response, 200);
    HttpAssertions.expectJson(response, '/error/message', 'invalid');
    HttpAssertions.expectLatency(response, const Duration(seconds: 1));
  });

  test('unknown logical endpoint is rejected before network access', () async {
    final driver = JsonHttpDriver(
      baseUri: Uri.parse('http://127.0.0.1:1'),
      endpoints: const {},
    );
    final world = await driver.create();
    addTearDown(() => driver.dispose(world));
    await expectLater(
      driver.request(
        world,
        const HttpRequestSpec(endpointId: 'missing', method: 'GET'),
      ),
      throwsStateError,
    );
  });

  test('endpoint base URLs resolve only from declared safe configuration', () {
    const resolver = EndpointBaseUrlResolver();
    expect(
      resolver.resolve(
        const {'baseUrlFrom': 'CALCULATOR_TEST_API_URL'},
        environment: const {'CALCULATOR_TEST_API_URL': 'https://api.test/v1/'},
      ),
      Uri.parse('https://api.test/v1/'),
    );
    expect(
      () => resolver.resolve(const {
        'baseUrlFrom': 'MISSING',
      }, environment: const {}),
      throwsFormatException,
    );
    expect(
      () => resolver.resolve(const {'baseUrl': 'file:///tmp/api'}),
      throwsFormatException,
    );
    expect(
      () =>
          resolver.resolve(const {'baseUrl': 'https://a', 'baseUrlFrom': 'A'}),
      throwsFormatException,
    );
  });

  test('vendor steps assert the latest logical HTTP response', () async {
    const response = HttpResponseSpec(
      statusCode: 422,
      body: {
        'error': {'code': 'INVALID_INPUT', 'message': 'first operand missing'},
      },
    );
    final steps = httpVendorSteps<MapScenarioWorld>(
      latestResponse: (_) => response,
      matchesSchema: (_, schema) => schema == 'calculator-error',
    );
    final registry = StepRegistry<MapScenarioWorld>();
    for (final step in steps) registry.register(step);
    final world = MapScenarioWorld();

    for (final text in [
      'the response status is 422',
      'the response error code is "INVALID_INPUT"',
      'the response body at "/error/message" contains "missing"',
      'the response body at "/error/message" does not contain "secret"',
      'the response conforms to schema "calculator-error"',
    ]) {
      final step = GherkinStep(
        keyword: 'Then',
        text: text,
        source: const SourceLocation(file: 'vendor.feature', line: 1),
      );
      final match = registry.resolve(step);
      await match.definition.action(world, step, match.arguments);
      expect(match.definition.tier, StepTier.vendor);
    }
  });
}
