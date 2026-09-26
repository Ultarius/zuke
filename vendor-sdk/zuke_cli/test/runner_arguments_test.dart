import 'package:test/test.dart';
import 'package:zuke_cli/src/runner_arguments.dart';

void main() {
  group('buildRunnerArguments', () {
    test('leaves a Flutter test runner untouched without --coverage', () {
      expect(
        buildRunnerArguments('flutter', const [
          'test',
          '--no-pub',
          '--reporter',
          'expanded',
        ], coverage: false),
        ['test', '--no-pub', '--reporter', 'expanded'],
      );
    });

    test('appends --coverage to a Flutter test runner', () {
      expect(
        buildRunnerArguments(r'C:\tools\flutter\bin\flutter.bat', const [
          'test',
          '--no-pub',
          '--reporter',
          'expanded',
        ], coverage: true),
        ['test', '--no-pub', '--reporter', 'expanded', '--coverage'],
      );
    });

    test('appends --coverage=coverage to a dart test runner', () {
      expect(
        buildRunnerArguments('dart', const [
          'test',
          '--reporter',
          'expanded',
        ], coverage: true),
        [
          '--disable-dart-dev',
          '--suppress-analytics',
          'test',
          '--reporter',
          'expanded',
          '--coverage=coverage',
        ],
      );
    });

    test('appends the dart prefix only once', () {
      expect(
        buildRunnerArguments('dart.exe', const [
          '--disable-dart-dev',
          'test',
        ], coverage: false),
        ['--disable-dart-dev', 'test'],
      );
    });

    test('never instruments a setup runner', () {
      // `flutter pub get` and `dart analyze` reject unknown flags.
      expect(
        buildRunnerArguments(
          'flutter',
          const ['pub', 'get'],
          coverage: true,
          setupRunner: true,
        ),
        ['pub', 'get'],
      );
      expect(
        buildRunnerArguments(
          'dart',
          const ['analyze'],
          coverage: true,
          setupRunner: true,
        ),
        ['--disable-dart-dev', '--suppress-analytics', 'analyze'],
      );
    });

    test('never instruments a non-test invocation, even when not setup', () {
      expect(
        buildRunnerArguments('flutter', const [
          'run',
          '-d',
          'windows',
        ], coverage: true),
        ['run', '-d', 'windows'],
      );
      expect(
        buildRunnerArguments('dart', const [
          'run',
          'tool/regenerate.dart',
        ], coverage: true),
        [
          '--disable-dart-dev',
          '--suppress-analytics',
          'run',
          'tool/regenerate.dart',
        ],
      );
    });

    test('respects an explicit coverage flag the runner already passed', () {
      expect(
        buildRunnerArguments('flutter', const [
          'test',
          '--coverage',
        ], coverage: true),
        ['test', '--coverage'],
      );
      expect(
        buildRunnerArguments('dart', const [
          'test',
          '--coverage=build/cov',
        ], coverage: true),
        [
          '--disable-dart-dev',
          '--suppress-analytics',
          'test',
          '--coverage=build/cov',
        ],
      );
    });

    test('finds the subcommand behind tool flags', () {
      expect(
        buildRunnerArguments('dart', const [
          '--suppress-analytics',
          'test',
        ], coverage: true),
        [
          '--disable-dart-dev',
          '--suppress-analytics',
          'test',
          '--coverage=coverage',
        ],
      );
      expect(
        buildRunnerArguments('flutter', const [
          '--suppress-analytics',
          '--dart-define=A=1',
          'test',
        ], coverage: true),
        ['--suppress-analytics', '--dart-define=A=1', 'test', '--coverage'],
      );
    });
  });

  group('runnerPrimaryCommand', () {
    test('skips flags and known value-taking global options', () {
      expect(runnerPrimaryCommand(const []), isNull);
      expect(runnerPrimaryCommand(const ['--verbose']), isNull);
      expect(runnerPrimaryCommand(const ['--verbose', 'test']), 'test');
      expect(runnerPrimaryCommand(const ['test', '--verbose']), 'test');
      expect(runnerPrimaryCommand(const ['--dart-define=A=1', 'run']), 'run');
      expect(
        runnerPrimaryCommand(const ['--dart-define', 'A=1', 'test']),
        'test',
      );
      expect(runnerPrimaryCommand(const ['-d', 'windows', 'test']), 'test');
    });
  });
}
