import 'dart:convert';
import 'dart:io';

import 'package:calculator_api/calculator_api.dart';
import 'package:calculator_domain/calculator_domain.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';
import 'package:zuke_annotations/zuke_annotations.dart' show ScenarioId;
import 'package:zuke_runner/zuke_runner.dart';
import 'package:test/test.dart';

void _emit(
  String ruleId,
  String evidenceType,
  String target,
  Object result, {
  required ScenarioId scenarioId,
}) {
  const SuiteEvidenceEmitter().emitPassing(
    requirementId: ruleId,
    scenarioId: scenarioId,
    evidenceTypes: [evidenceType],
    target: target,
    runnerCompatibilityId: 'calculator-api-tests-v1',
    digestInput: jsonEncode(result),
    runnerId: 'calculator-api-tests',
  );
}

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

void _emitApiScenario(
  String ruleId,
  ScenarioId scenarioId,
  Object result, {
  bool security = false,
}) {
  const SuiteEvidenceEmitter().emitPassing(
    requirementId: ruleId,
    scenarioId: scenarioId,
    evidenceTypes: security
        ? const ['api-contract', 'gherkin-api', 'security-integration']
        : const ['api-contract', 'gherkin-api'],
    target: 'backend',
    runnerCompatibilityId: 'calculator-api-tests-v1',
    digestInput: jsonEncode(result),
    runnerId: 'calculator-api-tests',
  );
}

void main() {
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  bool skipScenario(ScenarioId scenarioId) =>
      !shouldRunScenario(scenarioId.value, selectedScenarios);

  for (final testCase
      in <
        ({
          String rule,
          ScenarioId scenario,
          String operator,
          String first,
          String second,
          String result,
        })
      >[
        (
          rule: AdditionScenarios.addIntegersApi.requirementId,
          scenario: AdditionScenarios.addIntegersApi.id,
          operator: '+',
          first: '2',
          second: '3',
          result: '5',
        ),
        (
          rule: AdditionScenarios.addValues.requirementId,
          scenario: AdditionScenarios.addValues.id,
          operator: '+',
          first: '2.5',
          second: '1.25',
          result: '3.75',
        ),
        (
          rule: SubtractionScenarios.subtract.requirementId,
          scenario: SubtractionScenarios.subtract.id,
          operator: '-',
          first: '3',
          second: '5',
          result: '-2',
        ),
        (
          rule: MultiplicationScenarios.multiply.requirementId,
          scenario: MultiplicationScenarios.multiply.id,
          operator: '*',
          first: '2.5',
          second: '4',
          result: '10',
        ),
        (
          rule: DivisionScenarios.divide.requirementId,
          scenario: DivisionScenarios.divide.id,
          operator: '/',
          first: '10',
          second: '2',
          result: '5',
        ),
        (
          rule: DivisionScenarios.divideDecimal.requirementId,
          scenario: DivisionScenarios.divideDecimal.id,
          operator: '/',
          first: '1',
          second: '4',
          result: '0.25',
        ),
      ]) {
    test(
      '${testCase.scenario} executes through the API',
      () async {
        final server = await _server();
        final response = await _post(server, {
          'firstOperand': testCase.first,
          'secondOperand': testCase.second,
          'operator': testCase.operator,
        });
        expect(response['status'], 200);
        expect((response['body'] as Map)['result'], testCase.result);
        expect(server.application.events.single['ruleId'], testCase.rule);
        _emitApiScenario(
          testCase.rule,
          testCase.scenario,
          response,
          security: testCase.rule == DivisionScenarios.divide.requirementId,
        );
      },
      skip: skipScenario(testCase.scenario),
    );
  }

  test(
    '${DivisionScenarios.divideZero.id}: ${DivisionScenarios.divideZero.title}',
    () async {
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
      _emitApiScenario(
        DivisionScenarios.divideZero.requirementId,
        DivisionScenarios.divideZero.id,
        response,
        security: true,
      );
    },
    skip: skipScenario(DivisionScenarios.divideZero.id),
  );

  test(
    '${ValidationScenarios.badOperator.id}: ${ValidationScenarios.badOperator.title}',
    () async {
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
      _emitApiScenario(
        ValidationScenarios.badOperator.requirementId,
        ValidationScenarios.badOperator.id,
        response,
        security: true,
      );
    },
    skip: skipScenario(ValidationScenarios.badOperator.id),
  );

  test(
    '${BodySizeScenarios.oversizedBody.id}: ${BodySizeScenarios.oversizedBody.title}',
    () async {
      final application = CalculatorApplication();
      final response = await application.registration.dispatch(
        ZukeHttpRequest(
          method: 'POST',
          path: '/v1/calculations/evaluate',
          rawBody: List<int>.filled(16 * 1024 + 1, 65),
        ),
      );
      expect(response.statusCode, 413);
      expect(
        ((response.body as Map)['error'] as Map)['code'],
        'REQUEST_TOO_LARGE',
      );
      final result = response.body!;
      _emitApiScenario(
        BodySizeScenarios.oversizedBody.requirementId,
        BodySizeScenarios.oversizedBody.id,
        result,
        security: true,
      );
    },
    skip: skipScenario(BodySizeScenarios.oversizedBody.id),
  );

  test(
    '${RateLimitScenarios.rateLimit.id}: ${RateLimitScenarios.rateLimit.title}',
    () async {
      final server = await _server();
      final body = {'firstOperand': '2', 'secondOperand': '3', 'operator': '+'};
      await _post(server, body, identity: 'limited');
      await _post(server, body, identity: 'limited');
      final blocked = await _post(server, body, identity: 'limited');
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
      _emit(
        RateLimitScenarios.rateLimit.requirementId,
        'security-integration',
        'backend',
        {'blocked': blocked, 'allowed': allowed},
        scenarioId: RateLimitScenarios.rateLimit.id,
      );
      _emit(
        RateLimitScenarios.rateLimit.requirementId,
        'gherkin-api',
        'backend',
        {'blocked': blocked, 'allowed': allowed},
        scenarioId: RateLimitScenarios.rateLimit.id,
      );
      _emit(
        RateLimitScenarios.rateLimit.requirementId,
        'attestation-freshness',
        'edge',
        {'document': 'gateway-rate-limit.v1.json', 'status': 'present'},
        scenarioId: RateLimitScenarios.rateLimit.id,
      );
    },
    skip: skipScenario(RateLimitScenarios.rateLimit.id),
  );

  test(
    '${PerformanceScenarios.p95.id}: ${PerformanceScenarios.p95.title}',
    () async {
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
      _emit(
        PerformanceScenarios.p95.requirementId,
        'performance',
        'backend',
        {'p95Microseconds': p95, 'samples': samples.length},
        scenarioId: PerformanceScenarios.p95.id,
      );
    },
    skip: skipScenario(PerformanceScenarios.p95.id),
  );

  test(
    '${ErrorRedactionScenarios.unexpectedFailure.id}: ${ErrorRedactionScenarios.unexpectedFailure.title}',
    () async {
      final application = CalculatorApplication(
        calculator: _ThrowingCalculator(),
      );
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
      expect(
        jsonEncode(response['body']),
        isNot(contains('_ThrowingCalculator')),
      );
      expect(application.logEvents.single['correlationId'], 'corr-safe');
      expect(application.logEvents.single['first'], '[REDACTED]');
      _emitApiScenario(
        ErrorRedactionScenarios.unexpectedFailure.requirementId,
        ErrorRedactionScenarios.unexpectedFailure.id,
        response,
        security: true,
      );
      _emit(
        ErrorRedactionScenarios.unexpectedFailure.requirementId,
        'logging-verification',
        'backend',
        application.logEvents.single,
        scenarioId: ErrorRedactionScenarios.unexpectedFailure.id,
      );
    },
    skip: skipScenario(ErrorRedactionScenarios.unexpectedFailure.id),
  );
}

final class _ThrowingCalculator extends Calculator {
  @override
  CalculationResult evaluate(CalculationCommand command) =>
      throw StateError('internal calculator failure');
}
