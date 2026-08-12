/// Deterministic summary emitted after a successful Zuke test run.
class TestRunSummary {
  /// Selected execution profile.
  final String profile;

  /// Whether configured runners executed.
  final bool runnersExecuted;

  /// Digest of the scenario selection.
  final String selectionDigest;

  /// Selected governed scenario identifiers.
  final List<String> scenarioIds;

  /// Number of evidence records produced.
  final int evidenceRecords;

  /// Evidence output path.
  final String evidenceOutput;

  /// Optional observation path.
  final String? evidenceObservation;

  /// Creates a test-run summary.
  const TestRunSummary({
    required this.profile,
    required this.runnersExecuted,
    required this.selectionDigest,
    required this.scenarioIds,
    required this.evidenceRecords,
    required this.evidenceOutput,
    this.evidenceObservation,
  });

  /// Encodes the summary as a stable JSON object.
  Map<String, Object?> toJson() => {
    'kind': 'zuke.command-result',
    'command': 'test',
    'stage': 'test',
    'exitCode': 0,
    'status': 'passed',
    'eligible': true,
    'diagnostics': const <Object?>[],
    'profile': profile,
    'runnersExecuted': runnersExecuted,
    'selectionDigest': selectionDigest,
    'scenarioIds': scenarioIds,
    'evidenceRecords': evidenceRecords,
    'evidenceOutput': evidenceOutput,
    if (evidenceObservation != null) 'evidenceObservation': evidenceObservation,
  };

  /// Renders the summary as human-readable lines.
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
