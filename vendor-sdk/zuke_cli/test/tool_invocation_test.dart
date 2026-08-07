import 'dart:io';

import 'package:zuke_cli/src/tool_invocation.dart';
import 'package:zuke_test_support/zuke_test_support.dart';
import 'package:test/test.dart';

void main() {
  group('TestDartCommand & resolveTestDartCommand', () {
    test('resolves Dart command executable', () {
      final cmd = resolveTestDartCommand();
      expect(cmd.executable, isNotEmpty);
    });

    test('formats arguments cleanly', () {
      final cmd = TestDartCommand('dart');
      final args = cmd.arguments(['script.dart', '--flag']);
      expect(args, contains('run'));
      expect(args, contains('script.dart'));
      expect(args, contains('--flag'));
    });

    test('runs simple dart command', () async {
      final cmd = resolveTestDartCommand();
      final result = await cmd.run(['--version']);
      expect(result.exitCode, 0);
    });

    test('prepareToolInvocation prepares dart and flutter commands', () {
      final dartExeInv = prepareToolInvocation('dart.exe', ['foo.dart'], {});
      expect(dartExeInv.arguments, contains('--suppress-analytics'));
      expect(dartExeInv.arguments, contains('run'));
    });

    test('keeps the official Flutter launcher on POSIX', () {
      if (Platform.isWindows) return;
      final invocation = prepareToolInvocation('flutter', ['test'], {});
      expect(invocation.executable, 'flutter');
      expect(invocation.arguments, ['--suppress-analytics', 'test']);
      expect(invocation.environment['FLUTTER_SUPPRESS_ANALYTICS'], 'true');
    });

    test('explicit directSnapshot uses the cached tool on every platform', () {
      final root = Directory.systemTemp.createTempSync('runner-mode-sdk-');
      addTearDown(() => root.deleteSync(recursive: true));
      final dartName = Platform.isWindows ? 'dart.exe' : 'dart';
      Directory(
        '${root.path}/bin/cache/dart-sdk/bin',
      ).createSync(recursive: true);
      Directory(
        '${root.path}/packages/flutter_tools/.dart_tool',
      ).createSync(recursive: true);
      File(
        '${root.path}/bin/cache/dart-sdk/bin/$dartName',
      ).writeAsStringSync('x');
      File(
        '${root.path}/bin/cache/flutter_tools.snapshot',
      ).writeAsStringSync('x');
      File(
        '${root.path}/packages/flutter_tools/.dart_tool/package_config.json',
      ).writeAsStringSync('{}');
      final invocation = prepareToolInvocation(
        'flutter',
        ['test'],
        {'FLUTTER_ROOT': root.path},
        runnerMode: ToolRunnerMode.directSnapshot,
      );
      expect(invocation.arguments, contains('test'));
      expect(
        invocation.arguments,
        contains(endsWith('flutter_tools.snapshot')),
      );
    });

    test('directSnapshot rejects non-Flutter executables', () {
      expect(
        () => prepareToolInvocation(
          'dart',
          const [],
          const {},
          runnerMode: ToolRunnerMode.directSnapshot,
        ),
        throwsA(
          isA<ToolInvocationException>().having(
            (e) => e.diagnosticCode,
            'diagnosticCode',
            'ZUKE-FLUTTER-RUNNER-MODE-INVALID',
          ),
        ),
      );
    });
  });

  group('FlutterToolchainResolver hermetic', () {
    Directory? sdkDirectory;

    String sdkRoot() => sdkDirectory!.resolveSymbolicLinksSync();
    String path(Iterable<String> parts) =>
        <String>[sdkRoot(), ...parts].join(Platform.pathSeparator);
    File file(Iterable<String> parts) => File(path(parts));
    Directory directory(Iterable<String> parts) => Directory(path(parts));
    File flutterLauncher() => file(['bin', 'flutter.bat']);

    setUp(() {
      sdkDirectory = Directory.systemTemp.createTempSync('flutter_sdk_');
      directory([
        'bin',
        'cache',
        'dart-sdk',
        'bin',
      ]).createSync(recursive: true);
      directory([
        'packages',
        'flutter_tools',
        '.dart_tool',
      ]).createSync(recursive: true);
      final dartExeName = Platform.isWindows ? 'dart.exe' : 'dart';
      file([
        'bin',
        'cache',
        'dart-sdk',
        'bin',
        dartExeName,
      ]).writeAsStringSync('mock');
      file([
        'bin',
        'cache',
        'flutter_tools.snapshot',
      ]).writeAsStringSync('mock');
      file([
        'packages',
        'flutter_tools',
        '.dart_tool',
        'package_config.json',
      ]).writeAsStringSync('{}');
      flutterLauncher().writeAsStringSync('mock');
    });

    tearDown(() async {
      await deleteTemporaryDirectory(sdkDirectory!);
    });

    test('resolves using FLUTTER_ROOT env var', () {
      final result = const FlutterToolchainResolver().resolve(
        'flutter',
        ['test', '--no-pub'],
        {'FLUTTER_ROOT': '  ${sdkDirectory!.path}  '},
      );
      final dartExeName = Platform.isWindows ? 'dart.exe' : 'dart';
      expect(result.executable, contains(dartExeName));
      expect(
        result.arguments,
        contains(
          '--packages=${path(['packages', 'flutter_tools', '.dart_tool', 'package_config.json'])}',
        ),
      );
      expect(
        result.arguments,
        contains(path(['bin', 'cache', 'flutter_tools.snapshot'])),
      );
      expect(result.arguments, contains('--suppress-analytics'));
      expect(result.arguments, contains('test'));
      expect(result.arguments, contains('--no-pub'));
      expect(result.environment['FLUTTER_ROOT'], sdkRoot());
      expect(result.environment['FLUTTER_SUPPRESS_ANALYTICS'], 'true');
      expect(result.environment.containsKey('CI'), isFalse);
    });

    test('normalizes a relative FLUTTER_ROOT to an absolute path', () {
      final relativeRoot = _relativePath(
        Directory.current.absolute.path,
        sdkDirectory!.absolute.path,
      );
      final result = const FlutterToolchainResolver().resolve(
        'flutter',
        ['test'],
        {'FLUTTER_ROOT': relativeRoot},
      );
      expect(result.environment['FLUTTER_ROOT'], sdkRoot());
    });

    test('resolves from an absolute flutter.bat path', () {
      final result = const FlutterToolchainResolver().resolve(
        flutterLauncher().absolute.path,
        ['test'],
        const {},
      );
      expect(result.environment['FLUTTER_ROOT'], sdkRoot());
    });

    test('explicit executable wins over a stale FLUTTER_ROOT', () {
      final result = const FlutterToolchainResolver().resolve(
        flutterLauncher().absolute.path,
        ['test'],
        {
          'FLUTTER_ROOT': path(['missing']),
        },
      );
      expect(result.environment['FLUTTER_ROOT'], sdkRoot());
    });

    test('resolves from an injected PATH lookup', () {
      final result = FlutterToolchainResolver(
        executableLookup: () => flutterLauncher().absolute.path,
      ).resolve('flutter', ['test'], const {});
      expect(result.environment['FLUTTER_ROOT'], sdkRoot());
    });

    test('rejects an invalid explicit FLUTTER_ROOT', () {
      final missing = path(['missing']);
      expect(
        () => const FlutterToolchainResolver().resolve(
          'flutter',
          ['test'],
          {'FLUTTER_ROOT': missing},
        ),
        throwsA(
          isA<ToolInvocationException>()
              .having(
                (error) => error.diagnosticCode,
                'diagnosticCode',
                'ZUKE-FLUTTER-NOT-FOUND',
              )
              .having((error) => error.message, 'message', contains(missing)),
        ),
      );
    });

    test('does not add duplicate --suppress-analytics if already present', () {
      final result = const FlutterToolchainResolver().resolve(
        'flutter',
        ['--suppress-analytics', 'test'],
        {'FLUTTER_ROOT': sdkRoot()},
      );
      final occurrences = result.arguments
          .where((a) => a == '--suppress-analytics')
          .length;
      expect(occurrences, 1);
    });

    test('throws on missing cached Dart executable', () {
      final dartExeName = Platform.isWindows ? 'dart.exe' : 'dart';
      file(['bin', 'cache', 'dart-sdk', 'bin', dartExeName]).deleteSync();
      expect(
        () => const FlutterToolchainResolver().resolve(
          'flutter',
          ['test'],
          {'FLUTTER_ROOT': sdkRoot()},
        ),
        throwsA(
          isA<ToolInvocationException>()
              .having(
                (error) => error.diagnosticCode,
                'diagnosticCode',
                'ZUKE-FLUTTER-CACHE-INCOMPLETE',
              )
              .having(
                (error) => error.message,
                'message',
                contains(dartExeName),
              ),
        ),
      );
    });

    test('throws on missing snapshot', () {
      file(['bin', 'cache', 'flutter_tools.snapshot']).deleteSync();
      expect(
        () => const FlutterToolchainResolver().resolve(
          'flutter',
          ['test'],
          {'FLUTTER_ROOT': sdkRoot()},
        ),
        throwsA(
          isA<ToolInvocationException>().having(
            (error) => error.diagnosticCode,
            'diagnosticCode',
            'ZUKE-FLUTTER-CACHE-INCOMPLETE',
          ),
        ),
      );
    });

    test('throws on missing package_config.json', () {
      file([
        'packages',
        'flutter_tools',
        '.dart_tool',
        'package_config.json',
      ]).deleteSync();
      expect(
        () => const FlutterToolchainResolver().resolve(
          'flutter',
          ['test'],
          {'FLUTTER_ROOT': sdkRoot()},
        ),
        throwsA(
          isA<ToolInvocationException>().having(
            (error) => error.diagnosticCode,
            'diagnosticCode',
            'ZUKE-FLUTTER-CACHE-INCOMPLETE',
          ),
        ),
      );
    });

    test('rejects an SDK cache whose lockfile cannot be opened for write', () {
      final lockfile = path(['bin', 'cache', 'lockfile']);
      expect(
        () => FlutterToolchainResolver(
          cacheAccessProbe: (path) {
            expect(path, lockfile);
            throw FileSystemException('Access denied', path);
          },
        ).resolve('flutter', ['test'], {'FLUTTER_ROOT': sdkRoot()}),
        throwsA(
          isA<ToolInvocationException>()
              .having(
                (error) => error.diagnosticCode,
                'diagnosticCode',
                'ZUKE-FLUTTER-CACHE-UNWRITABLE',
              )
              .having(
                (error) => error.message,
                'message',
                allOf(contains(lockfile), contains('writable')),
              ),
        ),
      );
    });

    test('throws on FLUTTER_TOOL_ARGS', () {
      expect(
        () => const FlutterToolchainResolver().resolve(
          'flutter',
          ['test'],
          {'FLUTTER_ROOT': sdkRoot(), 'FLUTTER_TOOL_ARGS': '--verbose'},
        ),
        throwsA(
          isA<ToolInvocationException>()
              .having(
                (error) => error.diagnosticCode,
                'diagnosticCode',
                'ZUKE-FLUTTER-TOOL-ARGS-UNSUPPORTED',
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('flutter.bat')),
              ),
        ),
      );
    });

    test('never adds CI but inherits it naturally', () {
      final result = const FlutterToolchainResolver().resolve(
        'flutter',
        ['test'],
        {'FLUTTER_ROOT': sdkRoot(), 'CI': 'true', 'SOME_VAR': 'value'},
      );
      expect(result.environment['CI'], 'true');
      expect(result.environment['SOME_VAR'], 'value');
    });

    test('does not set CI when not in input', () {
      final result = const FlutterToolchainResolver().resolve(
        'flutter',
        ['test'],
        {'FLUTTER_ROOT': sdkRoot()},
      );
      expect(result.environment.containsKey('CI'), isFalse);
    });
  });

  test('recognizes supported Flutter command names consistently', () {
    expect(isFlutterTool('flutter'), isTrue);
    expect(isFlutterTool(r'C:\flutter\bin\flutter.bat'), isTrue);
    expect(isFlutterTool(r'C:\flutter\bin\flutter.cmd'), isTrue);
    expect(isFlutterTool('dart'), isFalse);
  });
}

String _relativePath(String from, String to) {
  List<String> parts(String value) => value
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();

  final fromParts = parts(from);
  final toParts = parts(to);
  var common = 0;
  while (common < fromParts.length &&
      common < toParts.length &&
      fromParts[common].toLowerCase() == toParts[common].toLowerCase()) {
    common++;
  }
  if (common == 0) return to;
  return <String>[
    ...List.filled(fromParts.length - common, '..'),
    ...toParts.skip(common),
  ].join(Platform.pathSeparator);
}
