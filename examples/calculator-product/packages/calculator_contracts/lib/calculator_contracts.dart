// GENERATED. DO NOT EDIT.

import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:calculator_contracts/src/generated/feat_calc_001_contracts.g.dart'
    as c0;
import 'package:calculator_contracts/src/generated/feat_calc_002_contracts.g.dart'
    as c1;

export 'package:calculator_contracts/src/generated/feat_calc_001_contracts.g.dart';
export 'package:calculator_contracts/src/generated/feat_calc_002_contracts.g.dart';

/// Generated identities only; catalog membership is not execution evidence.
final Map<String, ZukeScenarioContract> generatedScenarioContracts =
    Map.unmodifiable(<String, ZukeScenarioContract>{
      for (final scenario in c0.FeatCalc001Scenario.values)
        scenario.id.value: scenario,
      for (final scenario in c1.FeatCalc002Scenario.values)
        scenario.id.value: scenario,
    });

ZukeScenarioContract zukeScenarioContract(String id) =>
    generatedScenarioContracts[id] ??
    (throw StateError('No generated contract exists for $id'));
