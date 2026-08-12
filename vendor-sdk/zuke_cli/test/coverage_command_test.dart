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
}

ArgResults _args(String root, {bool includeBaseline = true}) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('input')
          ..addOption('changed-since')
          ..addOption('minimum')
          ..addOption('changed-line-minimum')
          ..addOption('baseline')
          ..addOption('output')
          ..addOption('format', defaultsTo: 'json'))
        .parse([
          '--root',
          root,
          '--input',
          'lcov.info',
          if (includeBaseline) ...['--baseline', 'baseline.json'],
          '--minimum',
          '0',
          '--format',
          'json',
        ]);
