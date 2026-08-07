import 'package:zuke_cli/zuke_cli.dart';
import 'package:test/test.dart';

void main() {
  const summary = TestRunSummary(
    profile: 'pullRequest',
    runnersExecuted: true,
    selectionDigest: 'sha256:selection',
    scenarioIds: ['SCN-ONE'],
    evidenceRecords: 2,
    evidenceOutput: 'generated/evidence/records',
    evidenceObservation: 'generated/evidence/runs/1.json',
  );

  test('renders evidence publication details in text output', () {
    expect(
      summary.toTextLines(),
      containsAll([
        '  Profile: pullRequest',
        '  Selected scenarios: SCN-ONE',
        '  Evidence records: 2',
        '  Evidence output: generated/evidence/records',
        '  Evidence observation: generated/evidence/runs/1.json',
      ]),
    );
  });

  test('adds evidence publication details to the JSON result', () {
    expect(summary.toJson(), containsPair('evidenceRecords', 2));
    expect(
      summary.toJson(),
      containsPair('evidenceOutput', 'generated/evidence/records'),
    );
    expect(
      summary.toJson(),
      containsPair('evidenceObservation', 'generated/evidence/runs/1.json'),
    );
  });
}
