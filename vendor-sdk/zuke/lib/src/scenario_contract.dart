import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

/// The parsed Gherkin nodes matched by a generated scenario contract.
final class ResolvedScenarioContract {
  final ZukeScenarioContract contract;
  final ParsedRule rule;
  final GherkinScenario scenario;

  const ResolvedScenarioContract({
    required this.contract,
    required this.rule,
    required this.scenario,
  });
}

/// Selects [contracts] in declaration order, requiring at least one match.
List<T> matchScenarioContracts<T extends ZukeScenarioContract>(
  Iterable<T> contracts,
  ZukeScenarioPattern pattern,
) {
  final selected = contracts.where(pattern.matches).toList();
  if (selected.isEmpty) {
    throw StateError('Scenario pattern matched no generated contracts');
  }
  return selected;
}

/// Matches and resolves generated contracts before a harness registers tests.
List<ResolvedScenarioContract>
resolveScenarioContracts<T extends ZukeScenarioContract>(
  ParsedFeature feature,
  Iterable<T> contracts,
  ZukeScenarioPattern pattern,
) => [
  for (final contract in matchScenarioContracts(contracts, pattern))
    resolveScenarioContract(feature, contract),
];

/// Resolves [contract] against [feature] and rejects any generated-contract
/// drift before a scenario can emit evidence.
ResolvedScenarioContract resolveScenarioContract(
  ParsedFeature feature,
  ZukeScenarioContract contract,
) {
  final matches = <ResolvedScenarioContract>[];
  for (final rule in feature.rules) {
    for (final scenario in rule.scenarios) {
      final ids = <String>{
        for (final tag in scenario.tags)
          if (tag.name.startsWith('SCN-')) tag.name,
        for (final examples in scenario.examples)
          for (final tag in examples.tags)
            if (tag.name.startsWith('SCN-')) tag.name,
      };
      if (ids.contains(contract.id.value)) {
        matches.add(
          ResolvedScenarioContract(
            contract: contract,
            rule: rule,
            scenario: scenario,
          ),
        );
      }
    }
  }
  if (matches.isEmpty) {
    throw StateError(
      'Generated scenario ${contract.id.value} is absent from Gherkin',
    );
  }
  if (matches.length != 1) {
    throw StateError(
      'Generated scenario ${contract.id.value} is ambiguous in Gherkin',
    );
  }
  final match = matches.single;
  if (match.rule.metadata.id != contract.requirementId.value) {
    throw StateError(
      'Generated scenario ${contract.id.value} belongs to ${match.rule.metadata.id}, '
      'not ${contract.requirementId.value}',
    );
  }
  if (match.scenario.scenarioElement.title != contract.title) {
    throw StateError(
      'Generated scenario ${contract.id.value} has title '
      '"${match.scenario.scenarioElement.title}", not "${contract.title}"',
    );
  }
  return match;
}
