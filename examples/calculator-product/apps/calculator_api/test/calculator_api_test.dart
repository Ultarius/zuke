import 'dart:convert';
import 'dart:io';

import 'package:calculator_api/calculator_api.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:calculator_domain/calculator_domain.dart';
import 'package:test/test.dart';
import 'package:zuke/zuke.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

Future<Map<String, Object?>> _post(
  CalculatorServer server,
  Map<String, Object?> body, {
  String identity = 'default',
  String correlationId = 'corr-test',
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/calculations/evaluate'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('x-rate-limit-identity', identity);
    request.headers.set('x-correlation-id', correlationId);
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return {
      'status': response.statusCode,
      'headers': {'retry-after': response.headers.value('retry-after')},
      'body': jsonDecode(text),
    };
  } finally {
    client.close(force: true);
  }
}

Future<CalculatorServer> _server({Calculator? calculator}) async {
  final server = CalculatorServer(
    application: CalculatorApplication(calculator: calculator),
  );
  await server.start();
  addTearDown(server.stop);
  return server;
}

Future<void> _runBasicCalculation({
  required String first,
  required String second,
  required String operator,
  required String expected,
  required String ruleId,
}) async {
  final server = await _server();
  expect(server.port, greaterThan(0));
  expect(server.application.registration.routes, isNotEmpty);
  final response = await _post(server, {
    'firstOperand': first,
    'secondOperand': second,
    'operator': operator,
  });
  expect(response['status'], 200);
  expect((response['body'] as Map)['result'], expected);
  expect(server.application.events, hasLength(1));
  expect(
    server.application.events.single['name'],
    'calculator.calculation.completed',
  );
  expect(server.application.events.single['ruleId'], ruleId);
}

Future<void> _runDivideByZero() async {
  final server = await _server();
  final response = await _post(server, {
    'firstOperand': '10',
    'secondOperand': '0',
    'operator': '/',
  });
  expect(response['status'], 422);
  final body = response['body'] as Map;
  expect((body['error'] as Map)['code'], 'DIVISION_BY_ZERO');
  expect(jsonEncode(body), isNot(contains('stack')));
  expect(jsonEncode(body), isNot(contains('source')));
  expect(server.application.events, isEmpty);
}

Future<void> _runBadOperator() async {
  final server = await _server();
  final response = await _post(server, {
    'firstOperand': '2',
    'secondOperand': '3',
    'operator': 'exec',
  });
  expect(response['status'], 400);
  expect(
    ((response['body'] as Map)['error'] as Map)['code'],
    'UNSUPPORTED_OPERATOR',
  );
  expect(server.application.events, isEmpty);
}

Future<void> _runBadOperand() async {
  for (final input in [
    'one',
    'NaN',
    'Infinity',
    '<script>alert(1)</script>',
    '../../configuration',
  ]) {
    final server = await _server();
    final response = await _post(server, {
      'firstOperand': input,
      'secondOperand': '3',
      'operator': '+',
    });
    expect(response['status'], 400);
    final body = response['body'] as Map;
    expect((body['error'] as Map)['code'], 'INVALID_OPERAND');
    expect(jsonEncode(body), isNot(contains(input)));
    expect(server.application.events, isEmpty);
  }
}

Future<void> _runOversizedBody() async {
  final application = CalculatorApplication();
  final response = await application.registration.dispatch(
    ZukeHttpRequest(
      method: 'POST',
      path: '/v1/calculations/evaluate',
      rawBody: List<int>.filled(16 * 1024 + 1, 65),
    ),
  );
  expect(response.statusCode, 413);
  expect(((response.body as Map)['error'] as Map)['code'], 'REQUEST_TOO_LARGE');
  expect(application.events, isEmpty);
}

Future<void> _runRateLimit() async {
  final server = await _server();
  final body = {'firstOperand': '2', 'secondOperand': '3', 'operator': '+'};
  await _post(server, body, identity: 'limited');
  await _post(server, body, identity: 'limited');
  final completedBeforeBlocked = server.application.events.length;
  final blocked = await _post(server, body, identity: 'limited');
  final completedAfterBlocked = server.application.events.length;
  final allowed = await _post(server, body, identity: 'other');
  expect(blocked['status'], 429);
  expect((blocked['headers'] as Map)['retry-after'], '60');
  expect(
    ((blocked['body'] as Map)['error'] as Map)['code'],
    'RATE_LIMIT_EXCEEDED',
  );
  expect(
    ((blocked['body'] as Map)['error'] as Map)['message'],
    'Too many requests.',
  );
  expect(allowed['status'], 200);
  expect(completedBeforeBlocked, 2);
  expect(completedAfterBlocked, completedBeforeBlocked);
  expect(server.application.events.length, completedBeforeBlocked + 1);
}

Future<void> _runPerformanceBudget() async {
  final server = await _server();
  final samples = <int>[];
  for (var index = 0; index < 20; index++) {
    final stopwatch = Stopwatch()..start();
    final response = await _post(server, {
      'firstOperand': '2',
      'secondOperand': '3',
      'operator': '+',
    }, identity: 'performance-$index');
    stopwatch.stop();
    expect(response['status'], 200);
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  final p95 = samples[(samples.length * .95).ceil() - 1];
  expect(p95, lessThan(100000));
}

Future<void> _runUnexpectedFailure() async {
  final application = CalculatorApplication(calculator: _ThrowingCalculator());
  final server = CalculatorServer(application: application);
  await server.start();
  addTearDown(server.stop);
  final response = await _post(server, {
    'firstOperand': '2',
    'secondOperand': '3',
    'operator': '+',
  }, correlationId: 'corr-safe');
  expect(response['status'], 500);
  expect(
    ((response['body'] as Map)['error'] as Map)['code'],
    'CALCULATION_FAILED',
  );
  expect(jsonEncode(response['body']), isNot(contains('_ThrowingCalculator')));
  expect(application.logEvents.single['correlationId'], 'corr-safe');
  expect(application.logEvents.single['first'], '[REDACTED]');
}

void main() {
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  bool skipScenario(ZukeScenarioContract scenario) =>
      !shouldRunScenario(scenario.id.value, selectedScenarios);

  zukeTest(
    () => _runBasicCalculation(
      first: '2',
      second: '3',
      operator: '+',
      expected: '5',
      ruleId: FeatCalc001RequirementIds.addition,
    ),
    scenario: AdditionScenarios.addIntegersApi,
    evidenceTypes: const ['api-contract', 'gherkin-api'],
    skip: skipScenario(AdditionScenarios.addIntegersApi),
  );
  zukeTest(
    () => _runBasicCalculation(
      first: '2.5',
      second: '1.25',
      operator: '+',
      expected: '3.75',
      ruleId: FeatCalc001RequirementIds.addition,
    ),
    scenario: AdditionScenarios.addValues,
    evidenceTypes: const ['api-contract', 'gherkin-api'],
    skip: skipScenario(AdditionScenarios.addValues),
  );
  zukeTest(
    () => _runBasicCalculation(
      first: '3',
      second: '5',
      operator: '-',
      expected: '-2',
      ruleId: FeatCalc001RequirementIds.subtraction,
    ),
    scenario: SubtractionScenarios.subtract,
    evidenceTypes: const ['api-contract', 'gherkin-api'],
    skip: skipScenario(SubtractionScenarios.subtract),
  );
  zukeTest(
    () => _runBasicCalculation(
      first: '2.5',
      second: '4',
      operator: '*',
      expected: '10',
      ruleId: FeatCalc001RequirementIds.multiplication,
    ),
    scenario: MultiplicationScenarios.multiply,
    evidenceTypes: const ['api-contract', 'gherkin-api'],
    skip: skipScenario(MultiplicationScenarios.multiply),
  );
  zukeTest(
    () => _runBasicCalculation(
      first: '10',
      second: '2',
      operator: '/',
      expected: '5',
      ruleId: FeatCalc001RequirementIds.division,
    ),
    scenario: DivisionScenarios.divide,
    evidenceTypes: const [
      'api-contract',
      'gherkin-api',
      'security-integration',
    ],
    skip: skipScenario(DivisionScenarios.divide),
  );
  zukeTest(
    () => _runBasicCalculation(
      first: '1',
      second: '4',
      operator: '/',
      expected: '0.25',
      ruleId: FeatCalc001RequirementIds.division,
    ),
    scenario: DivisionScenarios.divideDecimal,
    evidenceTypes: const ['api-contract', 'gherkin-api'],
    skip: skipScenario(DivisionScenarios.divideDecimal),
  );
  zukeTest(
    _runDivideByZero,
    scenario: DivisionScenarios.divideZero,
    evidenceTypes: const [
      'api-contract',
      'gherkin-api',
      'security-integration',
    ],
    skip: skipScenario(DivisionScenarios.divideZero),
  );
  zukeTest(
    _runBadOperator,
    scenario: ValidationScenarios.badOperator,
    evidenceTypes: const [
      'api-contract',
      'gherkin-api',
      'security-integration',
    ],
    skip: skipScenario(ValidationScenarios.badOperator),
  );
  zukeTest(
    _runBadOperand,
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const [
      'api-contract',
      'gherkin-api',
      'security-integration',
    ],
    skip: skipScenario(ValidationScenarios.badOperand),
  );
  zukeTest(
    _runOversizedBody,
    scenario: BodySizeScenarios.oversizedBody,
    evidenceTypes: const [
      'api-contract',
      'gherkin-api',
      'security-integration',
    ],
    skip: skipScenario(BodySizeScenarios.oversizedBody),
  );
  zukeTest(
    _runRateLimit,
    scenario: RateLimitScenarios.rateLimit,
    evidenceTypes: const ['gherkin-api', 'security-integration'],
    skip: skipScenario(RateLimitScenarios.rateLimit),
  );
  zukeTest(
    _runPerformanceBudget,
    scenario: PerformanceScenarios.p95,
    evidenceTypes: const ['performance'],
    skip: skipScenario(PerformanceScenarios.p95),
  );
  zukeTest(
    _runUnexpectedFailure,
    scenario: ErrorRedactionScenarios.unexpectedFailure,
    evidenceTypes: const [
      'api-contract',
      'gherkin-api',
      'security-integration',
      'logging-verification',
    ],
    skip: skipScenario(ErrorRedactionScenarios.unexpectedFailure),
  );
}

final class _ThrowingCalculator extends Calculator {
  @override
  CalculationResult evaluate(CalculationCommand command) =>
      throw StateError('internal calculator failure');
}
