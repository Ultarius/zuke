import 'dart:io';

/// Writes the smallest current configuration needed by generator tests.
///
/// Tests that exercise rejection of legacy or malformed configurations should
/// continue writing those documents explicitly; this helper is only for valid
/// schema-3 workspaces.
void writeSchema3Workspace(
  Directory root, {
  required String name,
  required String target,
  required String packageId,
  required String framework,
  required List<String> roots,
  String? sourceAdapter,
  String? sourceCompatibilityId,
  String? runnerCompatibilityId,
  String runnerId = 'sample-tests',
  String runnerKind = 'gherkin',
  String? contractOutput,
  String? generatedStepsOutput,
}) {
  if (roots.isEmpty) throw ArgumentError.value(roots, 'roots');
  final lines = <String>[
    'schemaVersion: 3',
    'workspace:',
    '  name: $name',
    '  root: .',
    'specifications:',
    '  features: [specs/features/**/*.feature]',
    'targets:',
    '  $target:',
    '    language: dart',
    '    framework: $framework',
    '    packages:',
    '      - id: $packageId',
    '        path: .',
    '        roots: [${roots.join(', ')}]',
  ];
  if (contractOutput != null) {
    lines.add('    contractOutput: $contractOutput');
  }
  if (sourceAdapter != null) {
    if (sourceCompatibilityId == null || runnerCompatibilityId == null) {
      throw ArgumentError(
        'source and runner compatibility IDs are required for a runner',
      );
    }
    lines.addAll([
      'execution:',
      '  runners:',
      '    - id: $runnerId',
      '      kind: $runnerKind',
      '      target: $target',
      '      sourcePackage: $packageId',
      '      sourceAdapter: $sourceAdapter',
      '      sourceCompatibilityId: $sourceCompatibilityId',
      '      runnerCompatibilityId: $runnerCompatibilityId',
    ]);
    if (generatedStepsOutput != null) {
      lines.add('      generatedStepsOutput: $generatedStepsOutput');
    }
  }
  File(
    '${root.path}${Platform.pathSeparator}zuke.yaml',
  ).writeAsStringSync('${lines.join('\n')}\n');
}
