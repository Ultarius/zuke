import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:zuke_cli/src/configuration_preflight.dart';
import 'package:zuke_cli/src/init_preset.dart';

import 'cli_test_helper.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('zuke-init-'));
  tearDown(() => root.deleteSync(recursive: true));

  for (final preset in ['dart', 'flutter', 'dart-frog']) {
    test(
      '$preset initializes a valid managed runner and generated barrel',
      () async {
        final result = await runInProcessCli([
          'init',
          '--root',
          root.path,
          '--preset',
          preset,
        ]);
        expect(result.exitCode, 0, reason: result.stderr);
        final workspace = requireCurrentWorkspace(root.path);
        expect(workspace.config.lockProfiles, [
          'pullRequest',
          'merge',
          'release',
          'nightly',
        ]);
        final config =
            loadYaml(File('${root.path}/zuke.yaml').readAsStringSync()) as Map;
        expect(config['targets']['app']['framework'], preset);
        expect(
          config['targets']['app']['contractExport'],
          'lib/zuke_contracts.dart',
        );
        expect(
          config['execution']['runners'][0]['executable'],
          preset == 'flutter' ? 'flutter' : 'dart',
        );
        expect(Directory('${root.path}/specs/features').existsSync(), isTrue);
        final original = File('${root.path}/zuke.yaml').readAsStringSync();
        final repeated = await runInProcessCli(['init', '--root', root.path]);
        expect(repeated.exitCode, 1);
        expect(File('${root.path}/zuke.yaml').readAsStringSync(), original);
      },
    );
  }

  test('detects framework dependencies and dry-run writes nothing', () async {
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    expect(InitPreset.detect(root), InitPreset.flutter);
    final result = await runInProcessCli([
      'init',
      '--root',
      root.path,
      '--dry-run',
    ]);
    expect(result.exitCode, 0);
    expect(
      InitPreset.detect(root).configuration(root),
      contains('framework: flutter'),
    );
    expect(File('${root.path}/zuke.yaml').existsSync(), isFalse);
    expect(Directory('${root.path}/specs').existsSync(), isFalse);
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\ndependencies:\n  dart_frog: any\n');
    expect(InitPreset.detect(root), InitPreset.dartFrog);
  });
}
