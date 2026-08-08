/// Parses the runner's stable scenario-ID allow-list.
Set<String> scenarioFilterFromEnvironment(Map<String, String> environment) =>
    (environment['ZUKE_SCENARIO_FILTER'] ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

/// Returns whether [scenarioId] is selected, treating an empty filter as all.
bool shouldRunScenario(String scenarioId, Set<String> selectedScenarioIds) =>
    selectedScenarioIds.isEmpty || selectedScenarioIds.contains(scenarioId);
