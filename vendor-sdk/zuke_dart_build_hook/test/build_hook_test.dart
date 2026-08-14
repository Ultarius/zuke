import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart' as hooks;
import 'package:zuke_dart_build_hook/zuke_dart_build_hook.dart';
import 'package:test/test.dart';

/// Helper to set up a minimal package directory and run the build hook.
Future<void> runBuildHook(
  String packageDir,
  Map<String, Object?>? userDefines,
) async {
  final outputDirectory = Directory('$packageDir/hook-output')..createSync();
  final config = File('$packageDir/input.json');
  final output = File('${outputDirectory.path}/output.json');
  final builder = hooks.BuildInputBuilder()
    ..setupShared(
      packageRoot: Directory(packageDir).uri,
      packageName: 'test_pkg',
      outputDirectoryShared: outputDirectory.uri,
      outputFile: output.uri,
      userDefines: userDefines == null
          ? null
          : hooks.PackageUserDefines(
              workspacePubspec: hooks.PackageUserDefinesSource(
                defines: userDefines,
                basePath: Directory(packageDir).uri,
              ),
            ),
    )
    ..config.setupBuild(linkingEnabled: false)
    ..setupBuildInput();
  config.writeAsStringSync(jsonEncode(builder.json));

  await build(['--config', config.path]);
}

/// Sets up a minimal package with a zuke.yaml and returns the dir path.
String setupPackageWithGuard(Directory tempDir) {
  final libDir = Directory('${tempDir.path}/lib')..createSync();
  File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_pkg
environment:
  sdk: '>=3.10.0 <3.11.0'
''');
  File('${libDir.path}/main.dart').writeAsStringSync('void main() {}\n');
  File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: test
  root: .
specifications: {}
targets: {}
''');
  return tempDir.path;
}

void main() {
  group('Zuke Dart Build Hook', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory(
        'test/temp_hook_${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'build consumes a hooks protocol input and declares its package root',
      () async {
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_pkg
environment:
  sdk: '>=3.10.0 <3.11.0'
''');
        final lib = Directory('${tempDir.path}/lib')..createSync();
        File('${lib.path}/main.dart').writeAsStringSync('void main() {}\n');
        File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: test
  root: .
specifications:
  features: []
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: test_pkg
        path: .
        roots: [lib]
        ''');
        final generated = await Process.run(
          Platform.resolvedExecutable,
          <String>['run', 'zuke_cli:zuke', 'generate', '--root', tempDir.path],
        );
        expect(
          generated.exitCode,
          0,
          reason:
              'Fixture generation failed: ${generated.stdout}\n${generated.stderr}',
        );
        final outputDirectory = Directory('${tempDir.path}/hook-output')
          ..createSync();
        final config = File('${tempDir.path}/input.json');
        final output = File('${outputDirectory.path}/output.json');
        final input = hooks.BuildInputBuilder()
          ..setupShared(
            packageRoot: tempDir.uri,
            packageName: 'test_pkg',
            outputDirectoryShared: outputDirectory.uri,
            outputFile: output.uri,
          )
          ..config.setupBuild(linkingEnabled: false)
          ..setupBuildInput();
        config.writeAsStringSync(jsonEncode(input.json));

        await build(['--config', config.path]);

        final outputJson = jsonDecode(output.readAsStringSync()) as Map;
        expect(
          outputJson['dependencies'],
          contains(
            '${tempDir.path.replaceAll('/', Platform.pathSeparator)}${Platform.pathSeparator}',
          ),
        );
      },
    );

    test('mode warn reports stale state without throwing BuildError', () async {
      setupPackageWithGuard(tempDir);

      await expectLater(
        runBuildHook(tempDir.path, {'mode': 'warn'}),
        completes,
      );
    });

    test('normalizes explicit and default build-hook modes', () {
      expect(normalizeBuildHookMode(null), 'error');
      expect(normalizeBuildHookMode('error'), 'error');
      expect(normalizeBuildHookMode('WARN'), 'warn');
    });

    test('rejects an invalid build-hook mode', () {
      expect(
        () => normalizeBuildHookMode('quiet'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('zuke_dart_build_hook.mode'),
          ),
        ),
      );
      expect(() => normalizeBuildHookMode(true), throwsArgumentError);
    });

    test('custom workspaceRoot directs directory walk', () async {
      final guardDir = Directory('${tempDir.path}/guard-root')..createSync();
      final libDir = Directory('${tempDir.path}/lib')..createSync();
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_pkg
environment:
  sdk: '>=3.10.0 <3.11.0'
''');
      File('${libDir.path}/main.dart').writeAsStringSync('void main() {}\n');
      File('${guardDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: test
  root: .
specifications: {}
targets: {}
''');

      await expectLater(
        runBuildHook(tempDir.path, {
          'mode': 'warn',
          'workspaceRoot': 'guard-root',
        }),
        completes,
      );

      await expectLater(
        runBuildHook(tempDir.path, {
          'mode': 'warn',
          'workspaceRoot': guardDir.absolute.path,
        }),
        completes,
      );
    });
  });
}
