// GENERATED. DO NOT EDIT.

import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:library_catalog/src/generated/feat_library_001_contracts.g.dart'
    as c0;

export 'package:library_catalog/src/generated/feat_library_001_contracts.g.dart';

/// Generated identities only; catalog membership is not execution evidence.
final Map<String, ZukeScenarioContract> generatedScenarioContracts =
    Map.unmodifiable(<String, ZukeScenarioContract>{
      for (final scenario in c0.FeatLibrary001Scenario.values)
        scenario.id.value: scenario,
    });

ZukeScenarioContract zukeScenarioContract(String id) =>
    generatedScenarioContracts[id] ??
    (throw StateError('No generated contract exists for $id'));
