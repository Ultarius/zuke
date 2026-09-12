import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:zuke_cli/src/vscode_preset.dart';
import 'cli_test_helper.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('zuke-editor-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('preserves aliases referenced by tasks or launch configurations', () {
    final taskFile = File('${root.path}/.vscode/tasks.json')
      ..parent.createSync(recursive: true);
    const label = 'Zuke: Refresh All Profile Locks';
    taskFile.writeAsStringSync(
      jsonEncode({
        'tasks': [
          {
            'label': label,
            'type': 'process',
            'command': 'dart',
            'args': ['run', 'zuke_cli:zuke', 'lock', '--refresh'],
          },
          {
            'label': 'Build',
            'dependsOn': [label],
          },
        ],
      }),
    );
    File('${root.path}/.vscode/launch.json').writeAsStringSync(
      jsonEncode({
        'configurations': [
          {'name': 'App', 'type': 'dart', 'preLaunchTask': label},
        ],
      }),
    );
    for (final update in prepareVscodePreset(root.path)) {
      update.write();
    }
    final tasks =
        (jsonDecode(taskFile.readAsStringSync()) as Map)['tasks'] as List;
    expect(
      tasks.where((task) => (task as Map)['label'] == label),
      hasLength(1),
    );
    final launch =
        jsonDecode(File('${root.path}/.vscode/launch.json').readAsStringSync())
            as Map;
    expect((launch['configurations'] as List).single['name'], 'App');
  });

  test(
    'init emits package commands and can update an existing workspace',
    () async {
      final result = await runInProcessCli([
        'init',
        '--root',
        root.path,
        '--preset',
        'flutter',
        '--editor',
        'vscode',
      ]);
      expect(result.exitCode, 0, reason: result.stderr);
      final config = File('${root.path}/zuke.yaml').readAsStringSync();
      final launch =
          jsonDecode(
                File('${root.path}/.vscode/launch.json').readAsStringSync(),
              )
              as Map;
      expect(launch['configurations'] ?? [], isEmpty);
      final repeated = await runInProcessCli([
        'init',
        '--root',
        root.path,
        '--editor',
        'vscode',
      ]);
      expect(repeated.exitCode, 0, reason: repeated.stderr);
      expect(File('${root.path}/zuke.yaml').readAsStringSync(), config);
      expect(
        jsonDecode(File('${root.path}/.vscode/launch.json').readAsStringSync()),
        launch,
      );
    },
  );

  test('preserves JSONC comments, user entries, URLs and trailing commas', () {
    final file = File('${root.path}/.vscode/tasks.json')
      ..parent.createSync(recursive: true);
    const user = '{"label":"Mine","command":"https://example.invalid/*x*/,}",}';
    file.writeAsStringSync('''{
      // Keep my commands.
      "tasks": [$user, /* Keep this comment. */],
      "version": "2.0.0",
    }''');
    for (final update in prepareVscodePreset(root.path)) {
      update.write();
    }
    final once = file.readAsStringSync();
    expect(once, contains(user));
    expect(once, contains('// Keep my commands.'));
    expect(once, contains('/* Keep this comment. */'));
    for (final update in prepareVscodePreset(root.path)) {
      update.write();
    }
    expect(file.readAsStringSync(), once);
  });

  test('generates the complete Zuke task preset and scope input', () {
    for (final update in prepareVscodePreset(root.path)) {
      update.write();
    }
    final decoded =
        jsonDecode(File('${root.path}/.vscode/tasks.json').readAsStringSync())
            as Map;
    final tasks = (decoded['tasks'] as List).cast<Map>();
    expect(
      tasks.map((task) => task['label']),
      containsAll([
        'Zuke: Refresh Profile Locks',
        'Zuke: Verify Profile Locks (No Mutation)',
        'Zuke: Validate Pull Request',
        'Zuke: Generate Contracts',
        'Zuke: Check Version Alignment',
        'Zuke: Doctor Check',
        'Zuke: Doctor Test Host Compatibility',
      ]),
    );
    expect(
      tasks.map((task) => task['label']),
      isNot(contains('Zuke: Refresh All Profile Locks')),
    );
    expect(
      tasks.map((task) => task['label']),
      isNot(contains('Zuke: Refresh Selected Profile Lock')),
    );
    final refresh = tasks.singleWhere(
      (task) => task['label'] == 'Zuke: Refresh Profile Locks',
    );
    // Explicit scope flag fragment; never `--profile all`.
    expect(refresh['args'], contains(r'${input:zukeLockScope}'));
    expect(
      (refresh['args'] as List).join(' '),
      isNot(contains('--profile all')),
    );
    final input = (decoded['inputs'] as List).cast<Map>().singleWhere(
      (input) => input['id'] == 'zukeLockScope',
    );
    expect(input['type'], 'pickString');
    expect(input['options'], contains('--all-profiles'));
    expect(input['options'], contains('--profile=pullRequest'));
    expect(input['default'], '--all-profiles');
  });

  test('migrates legacy refresh aliases and profile input', () {
    final file = File('${root.path}/.vscode/tasks.json')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync('''{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Zuke: Refresh All Profile Locks",
      "type": "process",
      "command": "dart",
      "args": ["--suppress-analytics", "run", "zuke_cli:zuke", "lock", "--refresh", "--root", "\${workspaceFolder}", "--runner-mode", "auto"],
      "problemMatcher": []
    },
    {
      "label": "Mine",
      "type": "shell",
      "command": "echo hi",
      "problemMatcher": []
    }
  ],
  "inputs": [
    {"id": "zukeProfile", "type": "promptString", "description": "old", "default": "pullRequest"}
  ]
}''');
    for (final update in prepareVscodePreset(root.path)) {
      update.write();
    }
    final decoded = jsonDecode(file.readAsStringSync()) as Map;
    final labels = (decoded['tasks'] as List).cast<Map>().map(
      (task) => task['label'],
    );
    expect(labels, contains('Zuke: Refresh Profile Locks'));
    expect(labels, contains('Mine'));
    expect(labels, isNot(contains('Zuke: Refresh All Profile Locks')));
    final inputs = (decoded['inputs'] as List).cast<Map>();
    expect(inputs.map((input) => input['id']), contains('zukeLockScope'));
    expect(inputs.map((input) => input['id']), isNot(contains('zukeProfile')));
  });

  test('populates the scope picker from configured lock profiles', () {
    File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
lock:
  directory: assurance/locks
  profiles: [pullRequest, custom]
''');
    for (final update in prepareVscodePreset(root.path)) {
      update.write();
    }
    final decoded =
        jsonDecode(File('${root.path}/.vscode/tasks.json').readAsStringSync())
            as Map;
    final input = (decoded['inputs'] as List).cast<Map>().singleWhere(
      (input) => input['id'] == 'zukeLockScope',
    );
    expect(input['options'], contains('--all-profiles'));
    expect(input['options'], contains('--profile=custom'));
  });

  test('invalid second file and dry-run leave all files untouched', () async {
    final launch = File('${root.path}/.vscode/launch.json')
      ..parent.createSync(recursive: true);
    launch.writeAsStringSync('{"configurations": false}');
    final failed = await runInProcessCli([
      'init',
      '--root',
      root.path,
      '--editor',
      'vscode',
    ]);
    expect(failed.exitCode, isNot(0));
    expect(File('${root.path}/zuke.yaml').existsSync(), isFalse);
    expect(File('${root.path}/.vscode/tasks.json').existsSync(), isFalse);
    expect(launch.readAsStringSync(), '{"configurations": false}');
    launch.writeAsStringSync('{}');
    final dry = await runInProcessCli([
      'init',
      '--root',
      root.path,
      '--editor',
      'vscode',
      '--dry-run',
    ]);
    expect(dry.exitCode, 0);
    expect(File('${root.path}/zuke.yaml').existsSync(), isFalse);
    expect(File('${root.path}/.vscode/tasks.json').existsSync(), isFalse);
    expect(launch.readAsStringSync(), '{}');
  });

  test(
    'ambiguous preset names are rejected without altering user configuration',
    () {
      final file = File('${root.path}/.vscode/tasks.json')
        ..parent.createSync(recursive: true);
      const original = '''{"tasks": [
      {"label": "Zuke: Refresh All Profile Locks", "command": "first"},
      {"label": "Zuke: Refresh All Profile Locks", "command": "second"}
    ]}''';
      file.writeAsStringSync(original);
      expect(() => prepareVscodePreset(root.path), throwsFormatException);
      expect(file.readAsStringSync(), original);
    },
  );
}
