import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:test/test.dart';
import 'package:zuke_cli/src/coverage_command.dart';

void main() {
  test(
    'parses LCOV records and normalizes Windows paths at evaluation time',
    () {
      final report = parseLcov('''
TN:
SF:lib\\src\\service.dart
DA:1,1
DA:2,0
end_of_record
''');
      expect(report.total, 2);
      expect(report.covered, 1);
      expect(report.percent, 50);
      expect(
        report.toJson(
          changedLines: {
            'lib/src/service.dart': {1, 2},
          },
        )['changedLines'],
        {'covered': 1, 'total': 2, 'percent': 50.0},
      );
    },
  );

  test('rejects malformed LCOV records', () {
    expect(() => parseLcov('DA:1,1'), throwsFormatException);
    expect(() => parseLcov('SF:lib/a.dart\nDA:bad,1'), throwsFormatException);
    expect(() => parseLcov('TN:\nend_of_record\n'), throwsFormatException);
  });

  test('uses configured layer patterns and included roots in the report', () {
    final report = parseLcov('''
TN:
SF:routes/game.dart
DA:1,1
SF:lib/src/domain/value.dart
DA:1,0
end_of_record
''');

    expect(
      report.toJson(
        includedRoots: const ['lib', 'routes'],
        layers: const {
          'routes': ['routes/**'],
          'domain': ['lib/src/domain/**'],
        },
      ),
      containsPair('includedRoots', ['lib', 'routes']),
    );
    final layers =
        report.toJson(
              layers: const {
                'routes': ['routes/**'],
                'domain': ['lib/src/domain/**'],
              },
            )['layers']
            as Map;
    expect(layers.keys, containsAll(['routes', 'domain']));
  });

  test('scopes absolute Windows LCOV paths to production roots', () {
    final report = parseLcov('''
TN:
SF:C:\\workspace\\lib\\service.dart
DA:1,1
DA:2,0
SF:C:\\workspace\\test\\service_test.dart
DA:1,1
end_of_record
''').scoped(root: r'C:\workspace', includedRoots: const ['lib']);

    expect(report.files.single.path, 'lib/service.dart');
    expect(report.total, 2);
    expect(report.covered, 1);
  });

  test('applies governed exclusions and preserves their metadata', () {
    const exclusion = CoverageExclusion(
      path: 'lib/generated.dart',
      lines: {2},
      justification: 'Generated platform bridge',
      approvedBy: 'platform-owner',
    );
    final report =
        parseLcov('''
TN:
SF:lib/generated.dart
DA:1,1
DA:2,0
end_of_record
''').scoped(
          root: r'C:\workspace',
          includedRoots: const ['lib'],
          exclusions: const [exclusion],
        );

    expect(report.total, 1);
    expect(report.covered, 1);
    expect(exclusion.toJson(), {
      'path': 'lib/generated.dart',
      'lines': [2],
      'justification': 'Generated platform bridge',
      'approvedBy': 'platform-owner',
    });
  });

  test('rejects malformed coverage policy values and exclusions', () async {
    final directory = Directory.systemTemp.createTempSync(
      'zuke-coverage-policy-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory('${directory.path}/specs/features').createSync(recursive: true);
    Directory('${directory.path}/lib').createSync(recursive: true);
    File(
      '${directory.path}/specs/features/coverage.feature',
    ).writeAsStringSync('Feature: Coverage\n  Scenario: policy\n');
    File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: backend
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 101
  exclusions:
    - path: lib/generated.dart
      lines: [1]
''');
    File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
end_of_record
''');

    final result = await CoverageCommand(
      _args(directory.path, includeBaseline: false),
    ).execute();
    expect(result, 1);
  });

  test('compares coverage against a configured baseline', () async {
    final directory = Directory.systemTemp.createTempSync('zuke-coverage-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory('${directory.path}/specs/features').createSync(recursive: true);
    Directory('${directory.path}/lib').createSync(recursive: true);
    File(
      '${directory.path}/specs/features/coverage.feature',
    ).writeAsStringSync('Feature: Coverage\n  Scenario: baseline\n');
    File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: coverage-test
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: backend
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
''');
    File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
DA:2,0
end_of_record
''');
    File(
      '${directory.path}/baseline.json',
    ).writeAsStringSync('{"percent": 75}');
    final result = await CoverageCommand(_args(directory.path)).execute();
    expect(result, 1);
  });

  test(
    'rejects loss of a previously covered line even at the same percent',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'zuke-coverage-lines-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      Directory('${directory.path}/specs/features').createSync(recursive: true);
      Directory('${directory.path}/lib').createSync(recursive: true);
      File(
        '${directory.path}/specs/features/coverage.feature',
      ).writeAsStringSync('Feature: Coverage\n  Scenario: baseline\n');
      File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: coverage-lines
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
  baseline: baseline.json
''');
      File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
DA:2,0
end_of_record
''');
      File('${directory.path}/baseline.json').writeAsStringSync('''
{
  "kind": "zuke.coverage-baseline",
  "schemaVersion": 1,
  "percent": 50,
  "files": {
    "lib/service.dart": {
      "executableLines": [1, 2],
      "coveredLines": [1, 2]
    }
  }
}
''');

      final result = await CoverageCommand(_args(directory.path)).execute();
      expect(result, 1);
    },
  );

  test('maps covered lines across baseline and target diff hunks', () async {
    final directory = Directory.systemTemp.createTempSync(
      'zuke-coverage-diff-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory('${directory.path}/specs/features').createSync(recursive: true);
    Directory('${directory.path}/lib').createSync(recursive: true);
    File(
      '${directory.path}/specs/features/coverage.feature',
    ).writeAsStringSync('Feature: Coverage\n  Scenario: changed diff\n');
    File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: coverage-diff
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
  baseline: baseline.json
''');
    final source = File('${directory.path}/lib/service.dart')
      ..writeAsStringSync('''void service() {
  final value = 1;
  print(value);
}
''');
    _runGit(directory, const ['init']);
    _runGit(directory, const ['config', 'user.email', 'test@example.com']);
    _runGit(directory, const ['config', 'user.name', 'Coverage Test']);
    _runGit(directory, const ['add', '.']);
    _runGit(directory, const ['commit', '-m', 'baseline']);
    final baselineRevision =
        (Process.runSync('git', const [
                  'rev-parse',
                  'HEAD',
                ], workingDirectory: directory.path).stdout
                as String)
            .trim();

    source.writeAsStringSync(
      '\nvoid service() {\n  final value = 1;\n  print(value);\n}\n',
    );
    _runGit(directory, const ['add', 'lib/service.dart']);
    _runGit(directory, const ['commit', '-m', 'target base']);
    final changedSinceRevision =
        (Process.runSync('git', const [
                  'rev-parse',
                  'HEAD',
                ], workingDirectory: directory.path).stdout
                as String)
            .trim();
    source.writeAsStringSync('${source.readAsStringSync()}// current change\n');
    File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:4,1
end_of_record
''');
    File('${directory.path}/baseline.json').writeAsStringSync('''
{
  "kind": "zuke.coverage-baseline",
  "schemaVersion": 1,
  "revision": "$baselineRevision",
  "percent": 100,
  "files": {
    "lib/service.dart": {
      "executableLines": [3],
      "coveredLines": [3]
    }
  }
}
''');

    final result = await CoverageCommand(
      _args(directory.path, changedSince: changedSinceRevision),
    ).execute();

    expect(result, 0);
  });

  test(
    'fails clearly when a Git checkout lacks the baseline revision',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'zuke-coverage-missing-revision-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      Directory('${directory.path}/specs/features').createSync(recursive: true);
      Directory('${directory.path}/lib').createSync(recursive: true);
      File(
        '${directory.path}/specs/features/coverage.feature',
      ).writeAsStringSync('Feature: Coverage\n  Scenario: missing revision\n');
      File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
  baseline: baseline.json
''');
      File(
        '${directory.path}/lib/service.dart',
      ).writeAsStringSync('void service() {}\n');
      File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
end_of_record
''');
      File('${directory.path}/baseline.json').writeAsStringSync('''
{
  "kind": "zuke.coverage-baseline",
  "schemaVersion": 1,
  "revision": "0000000000000000000000000000000000000000",
  "percent": 100,
  "files": {
    "lib/service.dart": {
      "executableLines": [1],
      "coveredLines": [1]
    }
  }
}
''');
      _runGit(directory, const ['init']);
      _runGit(directory, const ['config', 'user.email', 'test@example.com']);
      _runGit(directory, const ['config', 'user.name', 'Coverage Test']);
      _runGit(directory, const ['add', '.']);
      _runGit(directory, const ['commit', '-m', 'coverage']);

      final resultPath = '${directory.path}/result.json';
      final result = await CoverageCommand(
        _args(directory.path, output: resultPath),
      ).execute();

      expect(result, 1);
      final document =
          jsonDecode(File(resultPath).readAsStringSync())
              as Map<String, dynamic>;
      final diagnostics = document['diagnostics'] as List<dynamic>;
      final diagnostic = diagnostics.single as Map<String, dynamic>;
      expect(
        diagnostic['message'],
        contains('baseline revision is unavailable'),
      );
      // The error must name the stale baseline so an operator can locate it.
      expect(diagnostic['message'], contains('baseline.json'));
      // The structured remediation must match the message, not the generic
      // input/policy text used for ordinary coverage failures.
      expect(diagnostic['remediation'], contains('Fetch the missing revision'));
    },
  );

  test(
    'retains the archive fallback when the root is not a Git worktree',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'zuke-coverage-archive-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      Directory('${directory.path}/specs/features').createSync(recursive: true);
      Directory('${directory.path}/lib').createSync(recursive: true);
      File(
        '${directory.path}/specs/features/coverage.feature',
      ).writeAsStringSync('Feature: Coverage\n  Scenario: archive\n');
      File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
  baseline: baseline.json
''');
      File(
        '${directory.path}/lib/service.dart',
      ).writeAsStringSync('void service() {}\n');
      File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
end_of_record
''');
      File('${directory.path}/baseline.json').writeAsStringSync('''
{
  "kind": "zuke.coverage-baseline",
  "schemaVersion": 1,
  "revision": "0000000000000000000000000000000000000000",
  "percent": 100,
  "files": {
    "lib/service.dart": {
      "executableLines": [1],
      "coveredLines": [1]
    }
  }
}
''');
      // A deterministic stand-in for a source archive: Git answers "no" to
      // every probe regardless of the checkout that contains the test.
      final invoked = <String>[];
      Future<ProcessResult> noGit(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async {
        invoked.add('$executable ${arguments.join(' ')}');
        return ProcessResult(0, 1, '', '');
      }

      final result = await CoverageCommand(
        _args(directory.path),
        processRunner: noGit,
      ).execute();

      expect(result, 0);
      expect(
        invoked.any((call) => call.contains('cat-file')),
        isTrue,
        reason: 'the recorded revision is probed before falling back',
      );
      expect(
        invoked.any((call) => call.contains('rev-parse')),
        isTrue,
        reason: 'a non-worktree root falls back instead of failing',
      );
    },
  );

  test(
    'snapshots preserve coverage measured after uncommitted edits',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'zuke-dirty-baseline-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      _writeSnapshotWorkspace(directory);
      _runGit(directory, const ['init']);
      _runGit(directory, const ['config', 'user.email', 'test@example.com']);
      _runGit(directory, const ['config', 'user.name', 'Coverage Test']);
      _runGit(directory, const ['add', '.']);
      _runGit(directory, const ['commit', '-m', 'original']);
      final source = File('${directory.path}/lib/service.dart');
      source.writeAsStringSync(
        '// uncommitted insertion\n${source.readAsStringSync()}',
      );
      File('${directory.path}/lcov.info').writeAsStringSync(
        'SF:lib/service.dart\nDA:2,0\nDA:3,1\nDA:4,0\nDA:5,1\nend_of_record\n',
      );
      final output = '${directory.path}/result.json';
      expect(
        await CoverageCommand(
          _args(directory.path, writeBaseline: true, output: output),
        ).execute(),
        0,
      );
      final document = jsonDecode(File(output).readAsStringSync()) as Map;
      expect(
        (document['policy'] as Map)['baseline'],
        isNot(contains('sourceLines')),
      );
      final baseline =
          jsonDecode(File('${directory.path}/baseline.json').readAsStringSync())
              as Map;
      expect(baseline, contains('sourceLines'));
      // HEAD still exists but its source lines precede the insertion.
      expect(await CoverageCommand(_args(directory.path)).execute(), 0);
      // Archives without a recorded SHA must also use their measured snapshot.
      baseline.remove('revision');
      File(
        '${directory.path}/baseline.json',
      ).writeAsStringSync(jsonEncode(baseline));
      expect(await CoverageCommand(_args(directory.path)).execute(), 0);
    },
  );

  test(
    'uses portable source snapshots after an amended commit disappears',
    () async {
      final original = Directory.systemTemp.createTempSync(
        'zuke-coverage-snapshot-original-',
      );
      final rewritten = Directory.systemTemp.createTempSync(
        'zuke-coverage-snapshot-rewritten-',
      );
      addTearDown(() {
        original.deleteSync(recursive: true);
        rewritten.deleteSync(recursive: true);
      });
      _writeSnapshotWorkspace(original);
      _runGit(original, const ['init']);
      _runGit(original, const ['config', 'user.email', 'test@example.com']);
      _runGit(original, const ['config', 'user.name', 'Coverage Test']);
      _runGit(original, const ['add', '.']);
      _runGit(original, const ['commit', '-m', 'source']);

      final baselineResult = await CoverageCommand(
        _args(original.path, includeBaseline: false, writeBaseline: true),
      ).execute();
      expect(baselineResult, 0);
      final baseline =
          jsonDecode(File('${original.path}/baseline.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(baseline['sourceSnapshotVersion'], 1);
      expect(
        (baseline['sourceLines'] as Map<String, dynamic>)['lib/service.dart'],
        isA<List<dynamic>>(),
      );

      for (final relativePath in [
        'zuke.yaml',
        'lcov.info',
        'baseline.json',
        'lib/service.dart',
      ]) {
        final destination = File('${rewritten.path}/$relativePath');
        destination.parent.createSync(recursive: true);
        File('${original.path}/$relativePath').copySync(destination.path);
      }
      _runGit(rewritten, const ['init']);
      _runGit(rewritten, const ['config', 'user.email', 'test@example.com']);
      _runGit(rewritten, const ['config', 'user.name', 'Coverage Test']);
      _runGit(rewritten, const ['add', '.']);
      _runGit(rewritten, const ['commit', '-m', 'amended source']);

      // The rewritten repository has a different root commit, so the
      // baseline's recorded revision is unavailable. The source snapshot
      // still maps covered lines across the inserted comment.
      File('${rewritten.path}/lib/service.dart').writeAsStringSync(
        'void service() {\n'
        '  // inserted by an amended commit\n'
        '  final value = 1;\n'
        '  print(value);\n'
        '}\n',
      );
      File('${rewritten.path}/lcov.info').writeAsStringSync(
        'TN:\n'
        'SF:lib/service.dart\n'
        'DA:1,0\n'
        'DA:3,1\n'
        'DA:4,0\n'
        'DA:5,1\n'
        'end_of_record\n',
      );
      final preserved = await CoverageCommand(_args(rewritten.path)).execute();
      expect(preserved, 0);

      // A deleted line must shift the later covered closing line while
      // retaining its identity in the snapshot diff.
      File('${rewritten.path}/lib/service.dart').writeAsStringSync(
        'void service() {\n'
        '  final value = 1;\n'
        '}\n',
      );
      File('${rewritten.path}/lcov.info').writeAsStringSync(
        'TN:\n'
        'SF:lib/service.dart\n'
        'DA:1,0\n'
        'DA:2,1\n'
        'DA:3,1\n'
        'end_of_record\n',
      );
      final deleted = await CoverageCommand(_args(rewritten.path)).execute();
      expect(deleted, 0);

      // Restore the inserted source for the same-percentage loss assertion.
      File('${rewritten.path}/lib/service.dart').writeAsStringSync(
        'void service() {\n'
        '  // inserted by an amended commit\n'
        '  final value = 1;\n'
        '  print(value);\n'
        '}\n',
      );

      // Keep the overall percentage unchanged while removing coverage from
      // the previously covered line, so the line-preservation assertion is
      // the failure that proves snapshot mapping is active.
      File('${rewritten.path}/lcov.info').writeAsStringSync(
        'TN:\n'
        'SF:lib/service.dart\n'
        'DA:1,0\n'
        'DA:3,0\n'
        'DA:4,1\n'
        'DA:5,1\n'
        'end_of_record\n',
      );
      final resultPath = '${rewritten.path}/result.json';
      final regressed = await CoverageCommand(
        _args(rewritten.path, output: resultPath),
      ).execute();
      expect(regressed, 1);
      final document =
          jsonDecode(File(resultPath).readAsStringSync())
              as Map<String, dynamic>;
      final diagnostic =
          (document['diagnostics'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(
        diagnostic['message'],
        contains('previously covered production line'),
      );
    },
  );

  test(
    'fails instead of silently falling back when a known revision cannot diff',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'zuke-coverage-diff-failure-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      Directory('${directory.path}/specs/features').createSync(recursive: true);
      Directory('${directory.path}/lib').createSync(recursive: true);
      File(
        '${directory.path}/specs/features/coverage.feature',
      ).writeAsStringSync('Feature: Coverage\n  Scenario: diff failure\n');
      File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
  baseline: baseline.json
''');
      File(
        '${directory.path}/lib/service.dart',
      ).writeAsStringSync('void service() {}\n');
      File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
end_of_record
''');
      File('${directory.path}/baseline.json').writeAsStringSync('''
{
  "kind": "zuke.coverage-baseline",
  "schemaVersion": 1,
  "revision": "1111111111111111111111111111111111111111",
  "percent": 100,
  "files": {
    "lib/service.dart": {
      "executableLines": [1],
      "coveredLines": [1]
    }
  }
}
''');
      // The revision exists, but the diff cannot complete. That must fail
      // loudly rather than silently comparing against a different base.
      Future<ProcessResult> diffFails(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async {
        if (arguments.contains('cat-file')) {
          return ProcessResult(0, 0, '', '');
        }
        return ProcessResult(0, 1, '', 'simulated diff failure');
      }

      final resultPath = '${directory.path}/result.json';
      final result = await CoverageCommand(
        _args(directory.path, output: resultPath),
        processRunner: diffFails,
      ).execute();

      expect(result, 1);
      final document =
          jsonDecode(File(resultPath).readAsStringSync())
              as Map<String, dynamic>;
      final diagnostics = document['diagnostics'] as List<dynamic>;
      final message = (diagnostics.single as Map<String, dynamic>)['message'];
      expect(message, contains('Unable to calculate changed lines'));
    },
  );

  test('writes a reproducible file and line baseline when requested', () async {
    final directory = Directory.systemTemp.createTempSync(
      'zuke-coverage-write-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory('${directory.path}/specs/features').createSync(recursive: true);
    Directory('${directory.path}/lib').createSync(recursive: true);
    File(
      '${directory.path}/specs/features/coverage.feature',
    ).writeAsStringSync('Feature: Coverage\n  Scenario: baseline\n');
    File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: coverage-write
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 0
  changedLineMinimum: 100
  baseline: quality/coverage-baseline.json
''');
    File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
DA:2,0
end_of_record
''');

    final result = await CoverageCommand(
      _args(directory.path, includeBaseline: false, writeBaseline: true),
    ).execute();

    expect(result, 0);
    final baseline =
        jsonDecode(
              File(
                '${directory.path}/quality/coverage-baseline.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(baseline['kind'], 'zuke.coverage-baseline');
    expect(baseline['files']['lib/service.dart']['coveredLines'], [1]);
  });

  test('does not replace an existing baseline when policy fails', () async {
    final directory = Directory.systemTemp.createTempSync(
      'zuke-coverage-write-failure-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory('${directory.path}/specs/features').createSync(recursive: true);
    Directory('${directory.path}/lib').createSync(recursive: true);
    File(
      '${directory.path}/specs/features/coverage.feature',
    ).writeAsStringSync('Feature: Coverage\n  Scenario: baseline\n');
    File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: coverage-write-failure
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib]
coverage:
  input: lcov.info
  includedRoots: [lib]
  minimumTotal: 100
  changedLineMinimum: 100
  baseline: quality/coverage-baseline.json
''');
    File('${directory.path}/lcov.info').writeAsStringSync('''
TN:
SF:lib/service.dart
DA:1,1
DA:2,0
end_of_record
''');
    final baselineFile = File(
      '${directory.path}/quality/coverage-baseline.json',
    )..createSync(recursive: true);
    const original = '{"kind":"original-baseline","percent":0}\n';
    baselineFile.writeAsStringSync(original);

    final result = await CoverageCommand(
      _args(
        directory.path,
        includeBaseline: false,
        writeBaseline: true,
        minimum: '100',
      ),
    ).execute();

    expect(result, 1);
    expect(baselineFile.readAsStringSync(), original);
  });
}

void _writeSnapshotWorkspace(Directory directory) {
  Directory('${directory.path}/specs/features').createSync(recursive: true);
  Directory('${directory.path}/lib').createSync(recursive: true);
  File(
    '${directory.path}/specs/features/coverage.feature',
  ).writeAsStringSync('Feature: Coverage\n  Scenario: snapshot\n');
  File('${directory.path}/zuke.yaml').writeAsStringSync(
    'schemaVersion: 3\n'
    'workspace:\n'
    '  name: coverage-snapshot\n'
    '  root: .\n'
    'specifications:\n'
    '  features: [specs/features/**/*.feature]\n'
    'targets:\n'
    '  backend:\n'
    '    language: dart\n'
    '    framework: dart\n'
    '    packages:\n'
    '      - id: app\n'
    '        path: .\n'
    '        roots: [lib]\n'
    'coverage:\n'
    '  input: lcov.info\n'
    '  includedRoots: [lib]\n'
    '  minimumTotal: 0\n'
    '  changedLineMinimum: 100\n'
    '  baseline: baseline.json\n',
  );
  File('${directory.path}/lib/service.dart').writeAsStringSync(
    'void service() {\n'
    '  final value = 1;\n'
    '  print(value);\n'
    '}\n',
  );
  File('${directory.path}/lcov.info').writeAsStringSync(
    'TN:\n'
    'SF:lib/service.dart\n'
    'DA:1,0\n'
    'DA:2,1\n'
    'DA:3,0\n'
    'DA:4,1\n'
    'end_of_record\n',
  );
}

ArgResults _args(
  String root, {
  bool includeBaseline = true,
  bool writeBaseline = false,
  String minimum = '0',
  String? changedSince,
  String? output,
}) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('input')
          ..addOption('changed-since')
          ..addOption('minimum')
          ..addOption('changed-line-minimum')
          ..addOption('baseline')
          ..addFlag('write-baseline')
          ..addOption('output')
          ..addOption('format', defaultsTo: 'json'))
        .parse([
          '--root',
          root,
          '--input',
          'lcov.info',
          if (includeBaseline) ...['--baseline', 'baseline.json'],
          '--minimum',
          minimum,
          if (changedSince != null) ...['--changed-since', changedSince],
          if (writeBaseline) '--write-baseline',
          if (output != null) ...['--output', output],
          '--format',
          'json',
        ]);

void _runGit(Directory root, List<String> arguments) {
  final result = Process.runSync('git', arguments, workingDirectory: root.path);
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
