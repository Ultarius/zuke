// GENERATED. DO NOT EDIT.
// Source: FEAT-CALC-002 (specs/features/calculator_security.feature)

import 'package:zuke_annotations/zuke_annotations.dart';

abstract final class FeatCalc002RequirementIds {
  static const bodySize = 'RULE-CALC-BODY-SIZE';
  static const rateLimit = 'RULE-CALC-RATE-LIMIT';
  static const errorRedaction = 'RULE-CALC-ERROR-REDACTION';
}

enum FeatCalc002Scenario implements ZukeScenarioContract {
  oversizedBody(
    ScenarioId('SCN-CALC-OVERSIZED-BODY'),
    'RULE-CALC-BODY-SIZE',
    'Reject an oversized request body',
    <String>{'CTRL-CALC-BODY-SIZE', 'CTRL-CALC-LOG-REDACTION'},
  ),
  rateLimit(
    ScenarioId('SCN-CALC-RATE-LIMIT'),
    'RULE-CALC-RATE-LIMIT',
    'Apply rate limiting after the request budget is exhausted',
    <String>{'CTRL-CALC-LOG-REDACTION', 'CTRL-CALC-RATE-LIMIT'},
  ),
  unexpectedFailure(
    ScenarioId('SCN-CALC-UNEXPECTED-FAILURE'),
    'RULE-CALC-ERROR-REDACTION',
    'Sanitize an unexpected internal calculation failure',
    <String>{'CTRL-CALC-ERROR-REDACTION', 'CTRL-CALC-LOG-REDACTION'},
  );

  const FeatCalc002Scenario(
    this.id,
    this.requirementId,
    this.title,
    this.controlIds,
  );
  @override
  final ScenarioId id;
  @override
  final String requirementId;
  @override
  final String title;
  @override
  final Set<String> controlIds;
}

abstract final class FeatCalc002Scenarios {
  static const all = FeatCalc002Scenario.values;
  static final Map<ScenarioId, FeatCalc002Scenario> byId = Map.unmodifiable(
    <ScenarioId, FeatCalc002Scenario>{
      ScenarioId('SCN-CALC-OVERSIZED-BODY'): FeatCalc002Scenario.oversizedBody,
      ScenarioId('SCN-CALC-RATE-LIMIT'): FeatCalc002Scenario.rateLimit,
      ScenarioId('SCN-CALC-UNEXPECTED-FAILURE'):
          FeatCalc002Scenario.unexpectedFailure,
    },
  );
  static final Map<String, List<FeatCalc002Scenario>> byRule = Map.unmodifiable(
    <String, List<FeatCalc002Scenario>>{
      'RULE-CALC-BODY-SIZE': List.unmodifiable(<FeatCalc002Scenario>[
        FeatCalc002Scenario.oversizedBody,
      ]),
      'RULE-CALC-RATE-LIMIT': List.unmodifiable(<FeatCalc002Scenario>[
        FeatCalc002Scenario.rateLimit,
      ]),
      'RULE-CALC-ERROR-REDACTION': List.unmodifiable(<FeatCalc002Scenario>[
        FeatCalc002Scenario.unexpectedFailure,
      ]),
    },
  );
  static List<FeatCalc002Scenario> matching(ZukeScenarioPattern pattern) =>
      all.where(pattern.matches).toList(growable: false);
}

abstract final class BodySizeScenarios {
  static const oversizedBody = FeatCalc002Scenario.oversizedBody;
  static const all = <ZukeScenarioContract>[FeatCalc002Scenario.oversizedBody];
}

abstract final class RateLimitScenarios {
  static const rateLimit = FeatCalc002Scenario.rateLimit;
  static const all = <ZukeScenarioContract>[FeatCalc002Scenario.rateLimit];
}

abstract final class ErrorRedactionScenarios {
  static const unexpectedFailure = FeatCalc002Scenario.unexpectedFailure;
  static const all = <ZukeScenarioContract>[
    FeatCalc002Scenario.unexpectedFailure,
  ];
}
