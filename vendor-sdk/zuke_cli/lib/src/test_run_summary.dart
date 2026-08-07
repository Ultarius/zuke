class TestRunSummary {
  final String profile;
  final bool runnersExecuted;
  final String selectionDigest;
  final List<String> scenarioIds;
  final int evidenceRecords;
  final String evidenceOutput;
  final String? evidenceObservation;

  const TestRunSummary({
    required this.profile,
    required this.runnersExecuted,
    required this.selectionDigest,
    required this.scenarioIds,
    required this.evidenceRecords,
    required this.evidenceOutput,
    this.evidenceObservation,
  });

  Map<String, Object?> toJson() => {
    'schemaVersion': 'zuke.test-run.v1',
    'status': 'passed',
    'profile': profile,
    'runnersExecuted': runnersExecuted,
    'selectionDigest': selectionDigest,
    'scenarioIds': scenarioIds,
    'evidenceRecords': evidenceRecords,
    'evidenceOutput': evidenceOutput,
    if (evidenceObservation != null) 'evidenceObservation': evidenceObservation,
  };

  List<String> toTextLines() => [
    'Zuke test passed.',
    '  Profile: $profile',
    '  Selected scenarios: '
        '${scenarioIds.isEmpty ? '(runner-managed)' : scenarioIds.join(', ')}',
    '  Evidence records: $evidenceRecords',
    '  Evidence output: $evidenceOutput',
    if (evidenceObservation != null)
      '  Evidence observation: $evidenceObservation',
  ];
}
