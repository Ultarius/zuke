import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/editor.dart';
import 'package:zuke_cli/src/analyze_command.dart';
import 'package:zuke_cli/src/cli_parser.dart';
import 'package:zuke_cli/src/doctor_command.dart';
import 'package:zuke_cli/src/plugin_cache.dart';

import 'cli_test_helper.dart';
import 'helpers/schema3_workspace.dart';
import 'support/temporary_directory.dart';

void main() {
  test('doctor accepts a bounded repair count only with --fix', () async {
    final parser = buildZukeArgParser();
    final bounded = parser.parse([
      'doctor',
      '--fix',
      '--max-plugin-repairs',
      '10',
      '--plugin-cache-entry',
      'cache/entry-one',
      '--plugin-cache-entry',
      'cache/entry-two',
    ]).command!;
    expect(bounded['max-plugin-repairs'], '10');
    expect(bounded['plugin-cache-entry'], [
      'cache/entry-one',
      'cache/entry-two',
    ]);
    final invalid = parser.parse([
      'doctor',
      '--fix',
      '--max-plugin-repairs',
      'many',
    ]).command!;
    expect(await runDoctor(invalid), 64);
    final withoutFix = parser.parse([
      'doctor',
      '--max-plugin-repairs',
      '10',
    ]).command!;
    expect(await runDoctor(withoutFix), 64);
    final entryWithoutFix = parser.parse([
      'doctor',
      '--plugin-cache-entry',
      'cache/entry-one',
    ]).command!;
    expect(await runDoctor(entryWithoutFix), 64);
  });

  test(
    'analyze repairs before forwarding arguments and preserves exit status',
    () async {
      final command = buildZukeArgParser().parse([
        'analyze',
        '--root',
        'workspace with spaces',
        '--',
        '--fatal-infos',
        'lib',
      ]).command!;
      final events = <String>[];
      final result = await runAnalyze(
        command,
        doctor: (args) async {
          expect(args['fix'], isTrue);
          expect(args['root'], 'workspace with spaces');
          events.add('repair');
          return 0;
        },
        analyze: (root, arguments) async {
          expect(root, 'workspace with spaces');
          expect(arguments, ['--fatal-infos', 'lib']);
          events.add('analyze');
          return 3;
        },
      );
      expect(events, ['repair', 'analyze']);
      expect(result, 3);
    },
  );

  test('analyze stops when repair fails', () async {
    final command = buildZukeArgParser().parse(['analyze']).command!;
    final result = await runAnalyze(
      command,
      doctor: (_) async => 2,
      analyze: (_, _) async =>
          fail('Analysis must not start after failed repair'),
    );
    expect(result, 2);
  });

  test(
    'doctor --fix regenerates incompatible and unversioned indexes with JSON output',
    () async {
      final root = Directory.systemTemp.createTempSync('zuke-editor-doctor-');
      addTearDown(() => deleteTemporaryDirectory(root));
      writeSchema3Workspace(
        root,
        name: 'doctor',
        target: 'app',
        packageId: 'app',
        framework: 'dart',
        roots: ['lib'],
        contractOutput: 'lib/src/generated',
      );
      Directory('${root.path}/specs/features').createSync(recursive: true);
      // The plugin audit is stubbed, never the real one. The default audit walks
      // ancestor directories for a plugin declaration, and this fixture has no
      // Dart package boundary to stop that walk, so without the seam a
      // `doctor --fix` here could reach the real `~/.dartServer/.plugin_manager`
      // and recompile a real machine's plugin cache.
      for (final header in <Map<String, Object?>>[
        {'contractVersion': zukeIndexContract + 1},
        {},
      ]) {
        final index = File('${root.path}/.zuke/analyzer-index.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(header));
        final stdout = StringBuffer();
        final stderr = StringBuffer();
        late int exitCode;
        await IOOverrides.runZoned(
          () async {
            exitCode = await runDoctor(
              buildZukeArgParser().parse([
                'doctor',
                '--root',
                root.path,
                '--fix',
                '--format',
                'json',
              ]).command!,
              pluginAudit: (String auditedRoot, bool fix) async {
                expect(auditedRoot, root.path);
                expect(fix, isTrue);
                return const <PluginCacheFinding>[];
              },
            );
          },
          stdout: () => TestStdout(stdout),
          stderr: () => TestStdout(stderr),
        );
        expect(exitCode, 0, reason: '$stdout\n$stderr');
        final summary = jsonDecode(stdout.toString()) as Map;
        expect(summary['pluginCache'], isEmpty);
        expect(ZukeIndexHeader.read(index).contractVersion, zukeIndexContract);
      }
    },
  );
}
