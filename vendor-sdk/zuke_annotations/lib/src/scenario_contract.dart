import 'package:zuke_core/zuke_core.dart';

/// A generated, stable reference to one governed Gherkin scenario.
abstract interface class ZukeScenarioContract {
  /// Stable `SCN-*` identifier.
  ScenarioId get id;

  /// Stable `RULE-*` identifier that owns this scenario.
  RuleId get requirementId;

  /// Human-readable Gherkin scenario title.
  String get title;

  /// Effective direct and security-profile controls for this scenario's rule.
  Set<ControlId> get controlIds;
}
