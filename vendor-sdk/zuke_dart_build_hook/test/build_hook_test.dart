import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart' as hooks;
import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_dart_build_hook/zuke_dart_build_hook.dart';
import 'package:test/test.dart';

/// Helper to set up a minimal package directory and run the build hook.
Future<hooks.BuildOutput> runBuildHook(
  Directory package,
  Map<String, Object?>? userDefines,
) async {
  final packageRoot = package.uri;
  final outputDirectory = packageRoot.resolve('hook-output/');
  Directory.fromUri(outputDirectory).createSync();
  final config = File.fromUri(packageRoot.resolve('input.json'));
  final output = File.fromUri(outputDirectory.resolve('output.json'));
  final builder = hooks.BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'test_pkg',
      outputDirectoryShared: outputDirectory,
      outputFile: output.uri,
      userDefines: userDefines == null
          ? null
          : hooks.PackageUserDefines(
              workspacePubspec: hooks.PackageUserDefinesSource(
                defines: userDefines,
                // The hook runner passes the declaring pubspec, not its folder.
                basePath: packageRoot.resolve('pubspec.yaml'),
              ),
            ),
    )
    ..config.setupBuild(linkingEnabled: false)
    ..setupBuildInput();
  config.writeAsStringSync(jsonEncode(builder.json));

  await build(['--config', config.path]);
  return hooks.BuildOutput(
    jsonDecode(output.readAsStringSync()) as Map<String, Object?>,
  );
}

/// Sets up a workspace with a minimal package and returns the package directory.
Directory setupPackageWithGuard(
  Directory workspace, {
  String packagePath = '.',
}) {
  final package = Directory.fromUri(workspace.uri.resolve('$packagePath/'));
  final libDir = Directory.fromUri(package.uri.resolve('lib/'))
    ..createSync(recursive: true);
  File.fromUri(package.uri.resolve('pubspec.yaml')).writeAsStringSync('''
name: test_pkg
environment:
  sdk: '>=3.10.0 <4.0.0'
''');
  File.fromUri(
    libDir.uri.resolve('main.dart'),
  ).writeAsStringSync('void main() {}\n');
  File.fromUri(workspace.uri.resolve('zuke.yaml')).writeAsStringSync('''
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
        path: $packagePath
        roots: [lib]
''');
  return package;
}

void main() {
  group('Zuke Dart Build Hook', () {
    late Directory tempDir;

    setUp(() {
      // Keep the temporary package outside the workspace package scan.
      tempDir = Directory.systemTemp.createTempSync('zuke-build-hook-');
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
        setupPackageWithGuard(tempDir);
        expect(
          await ZukeCli().run(['generate', '--root', tempDir.path, '--quiet']),
          0,
          reason: 'Fixture generation failed',
        );
        final output = await runBuildHook(tempDir, null);
        expect(output.dependencies, contains(tempDir.uri));
      },
    );

    test('mode warn reports stale state without throwing BuildError', () async {
      setupPackageWithGuard(tempDir);

      await expectLater(runBuildHook(tempDir, {'mode': 'warn'}), completes);
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

    test('reads workspaceRoot as a file path, not a URI', () {
      final pubspec = tempDir.uri.resolve('app/pubspec.yaml');

      expect(
        normalizeBuildHookWorkspaceRoot(
          '../work #100%20/',
          basePath: pubspec,
        ).uri,
        tempDir.uri.resolveUri(Uri(pathSegments: ['work #100%20', ''])),
      );
    });

    test('rejects a workspaceRoot that is not a usable path', () {
      final pubspec = tempDir.uri.resolve('pubspec.yaml');
      for (final value in <Object>[
        true,
        '',
        '  ',
        if (Platform.isWindows) 'C:workspace',
      ]) {
        expect(
          () => normalizeBuildHookWorkspaceRoot(value, basePath: pubspec),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('zuke_dart_build_hook.workspaceRoot'),
            ),
          ),
          reason: '$value',
        );
      }
    });

    test('warn mode reports a malformed workspace configuration', () async {
      setupPackageWithGuard(tempDir);
      File.fromUri(
        tempDir.uri.resolve('zuke.yaml'),
      ).writeAsStringSync('targets: [\n');

      await expectLater(runBuildHook(tempDir, {'mode': 'warn'}), completes);
    });

    for (final form in ['relative', 'absolute']) {
      test('accepts the $form workspaceRoot and declares its inputs', () async {
        const workspaceName = 'guard #100%20 root';
        final workspace = Directory.fromUri(
          tempDir.uri.resolveUri(Uri(pathSegments: [workspaceName, ''])),
        );
        final package = setupPackageWithGuard(workspace, packagePath: 'app');
        final sourceWithReservedCharacters = File.fromUri(
          package.uri.resolveUri(
            Uri(pathSegments: ['lib', 'input #100%20.dart']),
          ),
        )..writeAsStringSync('const input = 0;\n');
        // The default walk would find this package-local guard, which has no
        // index and does not own the package. Only the explicit workspace root
        // can place the package and point to the fresh index.
        setupPackageWithGuard(package, packagePath: 'other');
        expect(
          await ZukeCli().run([
            'generate',
            '--root',
            workspace.path,
            '--quiet',
          ]),
          0,
          reason: 'Fixture generation failed',
        );

        final output = await runBuildHook(package, {
          'mode': 'error',
          'workspaceRoot': form == 'relative'
              ? '../../$workspaceName/'
              : workspace.absolute.path,
        });

        expect(
          output.dependencies,
          containsAll([
            workspace.uri.resolve('zuke.yaml'),
            workspace.uri.resolve('.zuke/analyzer-index.json'),
            workspace.uri.resolve('lib/src/.zuke-generated.json'),
            package.uri.resolve('lib/main.dart'),
            sourceWithReservedCharacters.uri,
          ]),
        );
      });
    }
  });
}
