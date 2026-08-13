// GENERATED. DO NOT EDIT.
// Source: FEAT-CALC-002 (specs/features/calculator_security.feature)

import 'package:zuke_annotations/zuke_annotations.dart';

abstract final class FeatCalc002RequirementIds {
  static const bodySize = 'RULE-CALC-BODY-SIZE';
  static const bodySizeId = RuleId('RULE-CALC-BODY-SIZE');
  static const rateLimit = 'RULE-CALC-RATE-LIMIT';
  static const rateLimitId = RuleId('RULE-CALC-RATE-LIMIT');
  static const errorRedaction = 'RULE-CALC-ERROR-REDACTION';
  static const errorRedactionId = RuleId('RULE-CALC-ERROR-REDACTION');
}

abstract final class FeatCalc002ControlIds {
  static const bodySize = ControlId('CTRL-CALC-BODY-SIZE');
  static const errorRedaction = ControlId('CTRL-CALC-ERROR-REDACTION');
  static const logRedaction = ControlId('CTRL-CALC-LOG-REDACTION');
  static const rateLimit = ControlId('CTRL-CALC-RATE-LIMIT');
}

enum FeatCalc002Scenario implements ZukeScenarioContract {
  oversizedBody(
    ScenarioId('SCN-CALC-OVERSIZED-BODY'),
    RuleId('RULE-CALC-BODY-SIZE'),
    'Reject an oversized request body',
    <ControlId>{
      ControlId('CTRL-CALC-BODY-SIZE'),
      ControlId('CTRL-CALC-LOG-REDACTION'),
    },
  ),
  rateLimit(
    ScenarioId('SCN-CALC-RATE-LIMIT'),
    RuleId('RULE-CALC-RATE-LIMIT'),
    'Apply rate limiting after the request budget is exhausted',
    <ControlId>{
      ControlId('CTRL-CALC-LOG-REDACTION'),
      ControlId('CTRL-CALC-RATE-LIMIT'),
    },
  ),
  unexpectedFailure(
    ScenarioId('SCN-CALC-UNEXPECTED-FAILURE'),
    RuleId('RULE-CALC-ERROR-REDACTION'),
    'Sanitize an unexpected internal calculation failure',
    <ControlId>{
      ControlId('CTRL-CALC-ERROR-REDACTION'),
      ControlId('CTRL-CALC-LOG-REDACTION'),
    },
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
  final RuleId requirementId;
  @override
  final String title;
  @override
  final Set<ControlId> controlIds;
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
