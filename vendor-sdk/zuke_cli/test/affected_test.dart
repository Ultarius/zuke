import 'dart:io';
import 'package:test/test.dart';
import 'cli_test_helper.dart';

void main() {
  group('zuke affected', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('affected_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('affected selects rule IDs from changed feature files', () async {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''schemaVersion: 3
workspace:
  name: test-workspace
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets: {}
''');

      final featureDir = Directory('${tempDir.path}/specs/features')
        ..createSync(recursive: true);
      File('${featureDir.path}/calc.feature').writeAsStringSync('''# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-001
# spec-end

@FEAT-CALC-001
Feature: Calculator
  Rule: Addition
    # spec-begin
    # schemaVersion: 1
    # id: RULE-CALC-ADD
    # spec-end
    Example: basic add
      Given a step
''');

      Process.runSync('git', ['init'], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'config',
        'user.name',
        'test',
      ], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'config',
        'user.email',
        'test@test.com',
      ], workingDirectory: tempDir.path);
      Process.runSync('git', ['add', '.'], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'commit',
        '-m',
        'initial',
      ], workingDirectory: tempDir.path);

      File('${featureDir.path}/calc.feature').writeAsStringSync('''# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-001
# spec-end

@FEAT-CALC-001
Feature: Calculator
  Rule: Addition
    # spec-begin
    # schemaVersion: 1
    # id: RULE-CALC-ADD
    # spec-end
    Example: advanced add
      Given an updated step
''');

      Process.runSync('git', ['add', '.'], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'commit',
        '-m',
        'update calc',
      ], workingDirectory: tempDir.path);

      final gitResult = Process.runSync('git', [
        'diff',
        '--name-only',
        'HEAD~1...HEAD',
      ], workingDirectory: tempDir.path);
      expect(gitResult.exitCode, equals(0));
      expect(gitResult.stdout, contains('calc.feature'));

      final result = await runInProcessCli([
        'affected',
        '--root',
        tempDir.path,
        '--changed-since',
        'HEAD~1',
      ]);

      expect(result.exitCode, equals(0));
    });
  });
}
