import 'dart:convert';

import 'package:calculator_domain/calculator_domain.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

final class CalculatorApplication {
  final Calculator calculator;
  final List<Map<String, Object?>> logEvents = [];
  final List<Map<String, Object?>> events = [];
  late final ZukeHttpApplication registration;

  CalculatorApplication({Calculator? calculator})
    : calculator = calculator ?? Calculator() {
    registration = ZukeHttpApplication(
      routes: [
        ZukeRouteRegistration(
          endpointId: 'calculator.evaluate',
          method: 'POST',
          path: '/v1/calculations/evaluate',
          middleware: [
            RateLimitMiddleware(),
            BodyLimitMiddleware(),
            RequestValidationMiddleware(),
          ],
          controller: CalculatorController(this),
          publicEgress: PublicHttpEgress(),
          failurePipelineId: 'calculator.failure-pipeline',
          loggingPipelineIds: const ['calculator.logging-pipeline'],
        ),
      ],
      failurePipelines: [
        ZukeFailurePipelineRegistration(
          id: 'calculator.failure-pipeline',
          sourceId: 'calculator.failure',
          handlers: [PublicCalculatorErrorMapper()],
          publicEgress: PublicHttpEgress(),
        ),
      ],
      loggingPipelines: [
        ZukeLoggingPipelineRegistration(
          id: 'calculator.logging-pipeline',
          sourceId: 'calculator.sensitive-data',
          processors: [CalculatorLoggingInterceptor()],
          sink: CalculatorLogSink(logEvents),
        ),
      ],
    );
  }
}

@ImplementsRequirement([
  FeatCalc001RequirementIds.addition,
  FeatCalc001RequirementIds.subtraction,
  FeatCalc001RequirementIds.multiplication,
  FeatCalc001RequirementIds.division,
  FeatCalc001RequirementIds.validation,
  'RULE-CALC-BODY-SIZE',
  'RULE-CALC-RATE-LIMIT',
  'RULE-CALC-ERROR-REDACTION',
])
final class CalculatorController implements ZukeController {
  final CalculatorApplication app;
  CalculatorController(this.app);
  @override
  String get id => 'calculator.controller';

  @override
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request) async {
    final body = request.body is Map
        ? Map<String, Object?>.from(request.body as Map)
        : const <String, Object?>{};
    final command = CalculationCommand(
      firstOperand: '${body['firstOperand'] ?? ''}',
      secondOperand: '${body['secondOperand'] ?? ''}',
      operator: _operator(
        '${body['operator'] ?? ''}'.replaceAll('×', '*').replaceAll('÷', '/'),
      ),
    );
    final result = app.calculator.evaluate(command);
    if (!result.isSuccess) {
      throw CalculatorRequestFailure(result.errorCode ?? 'INVALID_REQUEST');
    }
    app.events.add({
      'name': 'calculator.calculation.completed',
      'ruleId': _ruleFor(command.operator),
    });
    return ZukeHttpResponse(
      200,
      headers: const {'content-type': 'application/json'},
      body: {'result': result.result},
    );
  }

  CalculatorOperator _operator(String value) => switch (value) {
    '+' || 'add' => CalculatorOperator.add,
    '-' || 'subtract' => CalculatorOperator.subtract,
    '*' || '×' || 'multiply' => CalculatorOperator.multiply,
    '/' || '÷' || 'divide' => CalculatorOperator.divide,
    _ => throw const CalculatorRequestFailure('UNSUPPORTED_OPERATOR'),
  };

  String _ruleFor(CalculatorOperator operator) => switch (operator) {
    CalculatorOperator.add => FeatCalc001RequirementIds.addition,
    CalculatorOperator.subtract => FeatCalc001RequirementIds.subtraction,
    CalculatorOperator.multiply => FeatCalc001RequirementIds.multiplication,
    CalculatorOperator.divide => FeatCalc001RequirementIds.division,
  };
}

/// An executable local gateway stand-in used by the reference service tests.
/// Production edge enforcement remains independently attested; this component
/// makes the requirement's API behavior observable in the reference product.
@ProvidesControl(
  ['CTRL-CALC-RATE-LIMIT'],
  kind: ControlProviderKind.requestMiddleware,
  layer: EnforcementLayer.application,
)
final class RateLimitMiddleware implements ZukeMiddleware {
  final int requestBudget;
  final Map<String, int> _requests = <String, int>{};

  RateLimitMiddleware({this.requestBudget = 2});

  @override
  String get id => 'calculator.rate-limit';

  @override
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  ) {
    final identity = request.headers['x-rate-limit-identity'] ?? 'anonymous';
    final count = (_requests[identity] ?? 0) + 1;
    _requests[identity] = count;
    if (count > requestBudget) {
      return Future.value(
        const ZukeHttpResponse(
          429,
          headers: {'retry-after': '60'},
          body: {
            'error': {
              'code': 'RATE_LIMIT_EXCEEDED',
              'message': 'Too many requests.',
            },
          },
        ),
      );
    }
    return next(request);
  }
}

@ProvidesControl(
  ['CTRL-CALC-BODY-SIZE'],
  kind: ControlProviderKind.requestMiddleware,
  layer: EnforcementLayer.application,
)
final class BodyLimitMiddleware implements ZukeMiddleware {
  @override
  String get id => 'calculator.body-limit';
  @override
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  ) async {
    if (request.rawBody.length > 16 * 1024) {
      return const ZukeHttpResponse(
        413,
        body: {
          'error': {
            'code': 'REQUEST_TOO_LARGE',
            'message': 'Request body exceeds the permitted size.',
          },
        },
      );
    }
    try {
      final text = utf8.decode(request.rawBody, allowMalformed: false);
      final body = text.isEmpty ? const <String, Object?>{} : jsonDecode(text);
      return next(request.copyWith(body: body));
    } on FormatException {
      throw const CalculatorRequestFailure('INVALID_REQUEST');
    }
  }
}

@ProvidesControl(
  ['CTRL-CALC-INPUT-VALIDATION'],
  kind: ControlProviderKind.requestValidator,
  layer: EnforcementLayer.application,
)
final class RequestValidationMiddleware implements ZukeMiddleware {
  @override
  String get id => 'calculator.request-validation';
  @override
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  ) {
    final body = request.body;
    if (body is! Map ||
        !body.containsKey('firstOperand') ||
        !body.containsKey('secondOperand') ||
        !body.containsKey('operator')) {
      return Future.value(
        const ZukeHttpResponse(
          400,
          body: {
            'error': {'code': 'INVALID_REQUEST'},
          },
        ),
      );
    }
    return next(request);
  }
}

@ProvidesControl(
  ['CTRL-CALC-ERROR-REDACTION'],
  kind: ControlProviderKind.publicErrorMapper,
  layer: EnforcementLayer.application,
)
final class PublicCalculatorErrorMapper implements ZukeErrorHandler {
  @override
  String get id => 'calculator.public-error-mapper';
  @override
  Future<ZukeHttpResponse> handle(Object error, ZukeHttpRequest request) async {
    final failure = error is CalculatorRequestFailure
        ? error.code
        : 'CALCULATION_FAILED';
    final status = switch (failure) {
      'DIVISION_BY_ZERO' => 422,
      'CALCULATION_FAILED' => 500,
      _ => 400,
    };
    return ZukeHttpResponse(
      status,
      body: {
        'error': {
          'code': failure,
          'message': status == 500
              ? 'An unexpected error occurred.'
              : 'Invalid calculation request.',
        },
      },
    );
  }
}

final class CalculatorRequestFailure implements Exception {
  final String code;
  const CalculatorRequestFailure(this.code);
}

@ProvidesControl(
  ['CTRL-CALC-LOG-REDACTION'],
  kind: ControlProviderKind.loggingInterceptor,
  layer: EnforcementLayer.application,
)
final class CalculatorLoggingInterceptor implements ZukeLogProcessor {
  @override
  String get id => 'calculator.logging-redaction';
  @override
  Map<String, Object?> process(Map<String, Object?> event) => {
    ...event,
    'first': '[REDACTED]',
    'second': '[REDACTED]',
  };
}

final class CalculatorLogSink implements ZukeLogSink {
  final List<Map<String, Object?>> events;
  CalculatorLogSink(this.events);
  @override
  String get id => 'calculator.log-sink';
  @override
  void write(Map<String, Object?> event) => events.add(event);
}

final class PublicHttpEgress implements ZukePublicEgress {
  @override
  String get id => 'calculator.public-http-response';
  @override
  Future<void> write(Object response) async {}
}
