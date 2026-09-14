import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:zuke_cli/zuke_cli.dart';
import 'package:test/test.dart';
import 'package:zuke_cli/tooling.dart';
import 'cli_test_helper.dart';

void main() {
  group('GenerateCommand', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('zuke-generate-test-');
      _writeWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    for (final output in [
      'lib/contracts',
      'packages/contracts/lib/contracts',
    ]) {
      test('catalog executes through a custom barrel in $output', () async {
        final lib = output.substring(0, output.lastIndexOf('/'));
        final barrel = '$lib/api/contracts.dart';
        _configureCatalog(root, output: output, barrel: barrel);
        final packageRoot =
            lib == 'lib' ? root : Directory('${root.path}/packages/contracts')
              ..createSync(recursive: true);
        final packageName = lib == 'lib'
            ? 'generator_fixture'
            : 'actual_contracts';
        if (lib != 'lib') {
          File(
            '${packageRoot.path}/pubspec.yaml',
          ).writeAsStringSync('name: $packageName\n');
        }
        final second = File('${root.path}/specs/features/second.feature');
        second.writeAsStringSync(
          File(
            '${root.path}/specs/features/fixture.feature',
          ).readAsStringSync().replaceAll('TEST', 'SECOND'),
        );
        expect(await _run(root), 0);
        expect(await _run(root, check: true), 0);
        final generated = File('${root.path}/$barrel');
        final original = generated.readAsStringSync();
        expect(
          original,
          contains(
            "import 'package:$packageName/contracts/feat_test_001_contracts.g.dart'",
          ),
        );
        final probe = File('${root.path}/catalog_probe.dart')
          ..writeAsStringSync('''
import '$barrel';
void check(bool value) { if (!value) throw StateError('catalog mismatch'); }
void main() {
  check(generatedScenarioContracts.length == 2);
  final scenario = zukeScenarioContract('SCN-TEST-001');
  check(identical(scenario, FeatTest001Scenario.id001));
  check(scenario.requirementId.value == 'RULE-TEST-001');
  check(scenario.title == 'Fixture scenario');
  check(identical(zukeScenarioContract('SCN-SECOND-001'),
      FeatSecond001Scenario.id001));
  try { zukeScenarioContract('SCN-UNKNOWN-001'); }
  on StateError { return checkImmutable(); }
  throw StateError('unknown id accepted');
}
void checkImmutable() {
  try { generatedScenarioContracts.clear(); }
  on UnsupportedError { return; }
  throw StateError('catalog is mutable');
}
''');
        final sourceConfig = (await Isolate.packageConfig)!;
        final packageConfig =
            jsonDecode(File.fromUri(sourceConfig).readAsStringSync())
                as Map<String, dynamic>;
        for (final package in packageConfig['packages'] as List) {
          package['rootUri'] = sourceConfig
              .resolve(package['rootUri'] as String)
              .toString();
        }
        (packageConfig['packages'] as List).add({
          'name': packageName,
          'rootUri': packageRoot.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        });
        final configFile = File('${root.path}/probe_packages.json')
          ..writeAsStringSync(jsonEncode(packageConfig));
        final executed = await Process.run(Platform.resolvedExecutable, [
          '--packages=${configFile.path}',
          probe.path,
        ]);
        expect(
          executed.exitCode,
          0,
          reason: '${executed.stdout}${executed.stderr}',
        );

        // An edited generated barrel is refreshable, and check never writes it.
        generated.writeAsStringSync('$original\n// stale\n');
        expect(await _run(root, check: true), 1);
        expect(generated.readAsStringSync(), '$original\n// stale\n');
        expect(await _run(root), 0);
        expect(generated.readAsStringSync(), original);

        // Removing a feature removes its identity and only its managed file.
        second.deleteSync();
        expect(await _run(root, check: true), 1);
        expect(await _run(root), 0);
        expect(generated.readAsStringSync(), isNot(contains('FeatSecond')));
        expect(
          File(
            '${root.path}/$output/feat_second_001_contracts.g.dart',
          ).existsSync(),
          isFalse,
        );
        expect(await _run(root, check: true), 0);
      });
    }

    test(
      'catalog generation rejects duplicates before replacing outputs',
      () async {
        _configureCatalog(root);
        expect(await _run(root), 0);
        final barrel = File('${root.path}/lib/contracts.dart');
        final before = barrel.readAsBytesSync();
        File('${root.path}/specs/features/second.feature').writeAsStringSync(
          File('${root.path}/specs/features/fixture.feature')
              .readAsStringSync()
              .replaceAll('FEAT-TEST', 'FEAT-SECOND')
              .replaceAll('RULE-TEST', 'RULE-SECOND'),
        );
        expect(await _run(root), 1);
        expect(barrel.readAsBytesSync(), before);
      },
    );

    test('catalog remains valid when the last feature is removed', () async {
      _configureCatalog(root);
      expect(await _run(root), 0);
      File('${root.path}/specs/features/fixture.feature').deleteSync();
      expect(await _run(root), 0);
      expect(await _run(root, check: true), 0);
      final probe = File('${root.path}/empty_probe.dart')
        ..writeAsStringSync('''
import 'lib/contracts.dart';
void main() {
  if (generatedScenarioContracts.isNotEmpty) throw StateError('stale catalog');
}
''');
      final executed = await Process.run(Platform.resolvedExecutable, [
        '--packages=${(await Isolate.packageConfig)!.toFilePath()}',
        probe.path,
      ]);
      expect(
        executed.exitCode,
        0,
        reason: '${executed.stdout}${executed.stderr}',
      );
    });

    test(
      'catalog refuses handwritten barrels and upgrades legacy exports',
      () async {
        _configureCatalog(root);
        final barrel = File('${root.path}/lib/contracts.dart');
        barrel.parent.createSync(recursive: true);
        barrel.writeAsStringSync(
          '// Public aggregate maintained by the app.\n',
        );
        expect(await _run(root), 1);
        expect(
          barrel.readAsStringSync(),
          '// Public aggregate maintained by the app.\n',
        );
        barrel.deleteSync();
        expect(await _run(root), 0);
        const legacy =
            "export 'src/generated/feat_test_001_contracts.g.dart';\n";
        barrel.writeAsStringSync(legacy);
        expect(await _run(root, check: true), 1);
        expect(barrel.readAsStringSync(), legacy);
        expect(await _run(root), 0);
        expect(await _run(root, check: true), 0);
        barrel.writeAsStringSync('$legacy// Handwritten addition\n');
        expect(await _run(root), 1);
        expect(barrel.readAsStringSync(), '$legacy// Handwritten addition\n');
      },
    );

    test(
      'catalog rejects a barrel that overwrites a feature contract',
      () async {
        _configureCatalog(
          root,
          barrel: 'lib/src/generated/feat_test_001_contracts.g.dart',
        );
        expect(await _run(root), 1);
        expect(
          File(
            '${root.path}/lib/src/generated/feat_test_001_contracts.g.dart',
          ).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'generate --check detects missing or modified generated files',
      () async {
        // Run check before generating -> missing files -> exit code 1
        var res = await runInProcessCli([
          'generate',
          '--root',
          root.path,
          '--check',
        ]);
        expect(res.exitCode, 1);

        // Generate first
        expect(await _run(root), 0);

        // Check after generating -> all OK -> exit code 0
        res = await runInProcessCli([
          'generate',
          '--root',
          root.path,
          '--check',
        ]);
        expect(res.exitCode, 0);

        // Modify a generated file -> stale -> exit code 1
        final generatedFile = File(
          '${root.path}/packages/contracts/lib/src/generated/feat_test_001_contracts.g.dart',
        );
        generatedFile.writeAsStringSync('// modified content\n');
        res = await runInProcessCli([
          'generate',
          '--root',
          root.path,
          '--check',
        ]);
        expect(res.exitCode, 1);
      },
    );

    test('removes only stale files listed in the previous manifest', () async {
      expect(await _run(root), 0);
      final output = Directory(
        '${root.path}/packages/contracts/lib/src/generated',
      );
      final stale = File('${output.path}/old_contract.g.dart')
        ..writeAsStringSync('// GENERATED. DO NOT EDIT.\n');
      final unmanaged = File('${output.path}/unmanaged.g.dart')
        ..writeAsStringSync('// GENERATED. DO NOT EDIT.\n// owned elsewhere\n');
      final manifest = File(
        '${root.path}/packages/contracts/.zuke-generated.json',
      );
      final value = jsonDecode(manifest.readAsStringSync()) as Map;
      final entries =
          (value['files'] as List)
              .map((entry) => Map<String, Object?>.from(entry as Map))
              .toList()
            ..add({
              'path':
                  'packages/contracts/lib/src/generated/old_contract.g.dart',
              'contentHash': 'stale',
            });
      manifest.writeAsStringSync(jsonEncode({...value, 'files': entries}));

      expect(await _run(root), 0);
      expect(stale.existsSync(), isFalse);
      expect(unmanaged.existsSync(), isTrue);
    });

    test(
      'generates generic Flutter binding identities without Flutter imports',
      () async {
        expect(await _run(root), 0);
        final generated = File(
          '${root.path}/packages/contracts/lib/src/generated/'
          'feat_test_001_contracts.g.dart',
        ).readAsStringSync();

        expect(
          generated,
          contains(
            'abstract interface class FeatTest001FlutterBindings<T extends Object>',
          ),
        );
        expect(generated, contains('T get submit;'));
        expect(generated, contains('sealed class FeatTest001FlutterBinding'));
        expect(
          generated,
          contains(
            'final class FeatTest001SubmitBinding '
            'extends FeatTest001FlutterBinding',
          ),
        );
        expect(generated, contains("'calculator.submit' => submit"));
        expect(
          generated,
          contains('Unknown Flutter binding for FEAT-TEST-001'),
        );
        expect(generated, contains("static const id001 = 'RULE-TEST-001';"));
        expect(generated, isNot(contains('package:flutter')));
      },
    );

    test('generated Dart is formatter-stable and remains current', () async {
      expect(await _run(root), 0);
      final generated =
          '${root.path}/packages/contracts/lib/src/generated/'
          'feat_test_001_contracts.g.dart';
      final format = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'format',
        '--output=none',
        '--set-exit-if-changed',
        generated,
      ]);

      expect(format.exitCode, 0, reason: '${format.stdout}${format.stderr}');
      expect(await _run(root, check: true), 0);
    });

    test(
      'CLI separates progress from failures and supports quiet mode',
      () async {
        final generated = await _runCli(root);
        expect(generated.exitCode, 0);
        expect(generated.stdout, contains('Generating contracts...'));
        expect(generated.stdout, contains('WROTE:'));
        expect(generated.stderr, isEmpty);

        final checked = await _runCli(root, check: true);
        expect(checked.exitCode, 0);
        expect(checked.stdout, contains('OK:'));
        expect(checked.stdout, contains('.zuke-generated.json'));
        expect(checked.stdout, contains('.zuke/analyzer-index.json'));
        expect(checked.stdout, isNot(contains('Timing:')));
        expect(checked.stderr, isEmpty);

        final quiet = await _runCli(root, quiet: true, check: true);
        expect(quiet.exitCode, 0);
        expect(quiet.stdout, isEmpty);
        expect(quiet.stderr, isEmpty);

        final output = File(
          '${root.path}/packages/contracts/lib/src/generated/'
          'feat_test_001_contracts.g.dart',
        )..writeAsStringSync('// GENERATED. DO NOT EDIT.\n// stale\n');
        addTearDown(() {
          if (output.existsSync()) output.deleteSync();
        });
        final stale = await _runCli(root, check: true);
        expect(stale.exitCode, 1);
        expect(stale.stdout, contains('Checking contracts...'));
        expect(stale.stdout, isNot(contains('STALE:')));
        expect(stale.stderr, contains('STALE:'));
        expect(
          stale.stderr,
          contains('Generated files are stale (1 issue(s)).'),
        );
        expect(
          stale.stderr,
          contains('dart run zuke_cli:zuke generate --root "${root.path}"'),
        );
      },
    );

    test('reports colliding generated binding names', () async {
      final feature = File('${root.path}/specs/features/fixture.feature');
      feature.writeAsStringSync(
        feature.readAsStringSync().replaceFirst('# spec-end', '''
#     - id: checkout.submit
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
# spec-end'''),
      );

      expect(await _run(root), 1);
    });

    test('generated sealed bindings enforce exhaustive switches', () async {
      expect(await _run(root), 0);
      final importPath =
          'packages/contracts/lib/src/generated/'
          'feat_test_001_contracts.g.dart';
      final incomplete = File('${root.path}/incomplete.dart')
        ..writeAsStringSync('''
import '$importPath';

String finderFor(FeatTest001FlutterBinding binding) => switch (binding) {
  FeatTest001SubmitBinding() => 'submit',
};
''');
      final incompleteAnalysis = await Process.run(
        Platform.resolvedExecutable,
        [
          '--suppress-analytics',
          'analyze',
          '--format=machine',
          incomplete.path,
        ],
        workingDirectory: root.path,
      );
      expect(incompleteAnalysis.exitCode, isNot(0));
      expect(
        '${incompleteAnalysis.stdout}${incompleteAnalysis.stderr}',
        contains('NON_EXHAUSTIVE_SWITCH_EXPRESSION'),
      );

      final complete = File('${root.path}/complete.dart')
        ..writeAsStringSync('''
import '$importPath';

String finderFor(FeatTest001FlutterBinding binding) => switch (binding) {
  FeatTest001SubmitBinding() => 'submit',
  FeatTest001DisplayBinding() => 'display',
};
''');
      final completeAnalysis = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'analyze',
        '--format=machine',
        complete.path,
      ], workingDirectory: root.path);
      expect(
        completeAnalysis.exitCode,
        0,
        reason: '${completeAnalysis.stdout}${completeAnalysis.stderr}',
      );
    });

    test('refuses to overwrite a handwritten expected output', () async {
      expect(await _run(root), 0);
      final generated = File(
        '${root.path}/packages/contracts/lib/src/generated/'
        'feat_test_001_contracts.g.dart',
      );
      generated.writeAsStringSync('// handwritten contract\n');

      expect(await _run(root), 1);
      expect(generated.readAsStringSync(), '// handwritten contract\n');
    });

    test('check mode reports stale output without mutating it', () async {
      expect(await _run(root), 0);
      final generated = File(
        '${root.path}/packages/contracts/lib/src/generated/'
        'feat_test_001_contracts.g.dart',
      );
      generated.writeAsStringSync('// GENERATED. DO NOT EDIT.\n// stale\n');

      expect(await _run(root, check: true), 1);
      expect(
        generated.readAsStringSync(),
        '// GENERATED. DO NOT EDIT.\n// stale\n',
      );
    });

    test(
      'creates an index and rejects a changed specification in check mode',
      () async {
        expect(await _run(root), 0);
        final index = File('${root.path}/.zuke/analyzer-index.json');
        expect(index.existsSync(), isTrue);
        expect(jsonDecode(index.readAsStringSync())['kind'], ZukeIndex.kind);

        final feature = File('${root.path}/specs/features/fixture.feature');
        feature.writeAsStringSync('${feature.readAsStringSync()}\n# changed\n');

        expect(await _run(root, check: true), 1);
        expect(index.existsSync(), isTrue);
      },
    );
  });
}

Future<int> _run(Directory root, {bool check = false}) => GenerateCommand(
  (ArgParser()
        ..addOption('root')
        ..addFlag('check')
        ..addOption('output')
        ..addFlag('quiet'))
      .parse(['--root', root.path, if (check) '--check']),
).execute();

void _configureCatalog(
  Directory root, {
  String output = 'lib/src/generated',
  String barrel = 'lib/contracts.dart',
}) {
  final config = File('${root.path}/zuke.yaml');
  config.writeAsStringSync(
    config.readAsStringSync().replaceFirst(
      'contractOutput: packages/contracts/lib/src/generated',
      'contractOutput: $output\n    contractExport: $barrel',
    ),
  );
  final feature = File('${root.path}/specs/features/fixture.feature');
  feature.writeAsStringSync(
    feature.readAsStringSync().replaceFirst(
      '    Scenario:',
      '    @SCN-TEST-001\n    Scenario:',
    ),
  );
}

Future<ProcessResult> _runCli(
  Directory root, {
  bool check = false,
  bool quiet = false,
}) async {
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  late int exitCode;
  await IOOverrides.runZoned(
    () async {
      exitCode = await ZukeCli().run([
        'generate',
        '--root',
        root.path,
        if (check) '--check',
        if (quiet) '--quiet',
      ]);
    },
    stdout: () => TestStdout(stdoutBuffer),
    stderr: () => TestStdout(stderrBuffer),
  );
  return ProcessResult(
    0,
    exitCode,
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}

void _writeWorkspace(Directory root) {
  File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: generator_fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
''');
  File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: generator-fixture
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  flutter:
    language: dart
    framework: flutter
    packages:
      - id: generator-fixture
        path: .
        roots: [lib, test]
    contractOutput: packages/contracts/lib/src/generated
''');
  final features = Directory('${root.path}/specs/features')
    ..createSync(recursive: true);
  File('${features.path}/fixture.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-TEST-001
# targets:
#   - flutter
# bindings:
#   required:
#     - id: calculator.submit
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: calculator.display
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
# spec-end

@FEAT-TEST-001
Feature: Generator fixture
  # rule-spec-begin
  # id: RULE-TEST-001
  # rule-spec-end
  @RULE-TEST-001
  Rule: Fixture rule
    Scenario: Fixture scenario
      Given a fixture
''');
}
