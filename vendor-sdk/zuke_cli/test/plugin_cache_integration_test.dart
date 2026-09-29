/// Slow coverage for the repair worker pool against the real analysis-server
/// plugin, a 13 MB AOT built from the analyzer SDK that takes about fifteen
/// seconds to compile per entry.
///
/// The pool's concurrency does not depend on the size of what it compiles, and
/// `plugin_cache_test.dart` covers the pool with real subprocesses, real locks
/// and real receipts against a trivial program. What is left is the toolchain
/// itself: whether concurrent compiles of the genuine plugin interfere, and
/// whether each entry ends up with its own snapshot rather than a neighbour's.
///
/// Tagged so it does not add half a minute to every pull request. Run it with
/// `dart test --tags integration`, which the nightly workflow does.
///
/// The properties asserted here are the ones a bad batch repair would break. A
/// one-off run against a real 143-entry cache reported 23 entries as failed that
/// were, on the very next audit, perfectly current; that was never reproduced and
/// no cause was found. So: every entry repaired, every receipt validating on a
/// second pass, and no two entries sharing a snapshot.
@Tags(['integration'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zuke_cli/src/plugin_cache.dart';
import 'package:zuke_cli/src/tooling/analyzer_sdk.dart';

import 'support/temporary_directory.dart';

void main() {
  late Directory root;
  late Directory cache;
  late String pluginRoot;

  setUpAll(() {
    pluginRoot = _findZukeAnalyzer();
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-plugin-integration-');
    cache = Directory(p.join(root.path, 'cache'))..createSync();
  });
  tearDown(() => deleteTemporaryDirectory(root));

  test(
    'two real plugin entries compile concurrently and each keeps its own snapshot',
    () async {
      final alpha = await _pluginEntry(cache, pluginRoot, 'alpha');
      final beta = await _pluginEntry(cache, pluginRoot, 'beta');
      final doctor = PluginCacheDoctor(
        cacheRoot: cache,
        localZukeRoots: {pluginRoot},
      );

      final repaired = await doctor.inspect(fix: true, repairWorkers: 2);
      expect(
        repaired.where((f) => f.status == 'failed').map((f) => f.message),
        isEmpty,
        reason: 'a concurrent plugin compile must not fail an entry',
      );
      expect(repaired.where((f) => f.status == 'repaired'), hasLength(2));

      // The strong assertion: every receipt has to validate on a second pass.
      // An entry reported repaired that then disagrees with itself is exactly
      // the symptom the unexplained failures had.
      final reaudited = await doctor.inspect();
      expect(
        reaudited.where((f) => f.status != 'current').map((f) => f.status),
        isEmpty,
      );

      expect(
        {
          for (final entry in [alpha, beta])
            sha256
                .convert(
                  File(
                    p.join(entry.path, 'bin', 'plugin.aot'),
                  ).readAsBytesSync(),
                )
                .toString(),
        },
        hasLength(2),
        reason:
            'a pool bug copying one snapshot over another would collapse these',
      );
      for (final entry in [alpha, beta]) {
        expect(
          File(p.join(entry.path, 'bin', 'depfile.txt')).existsSync(),
          isTrue,
          reason: 'each entry writes its own depfile, not a shared one',
        );
      }
    },
  );
}

/// The repository's `zuke_analyzer`, found by walking up from the working
/// directory. The runner starts the suite at the repository root while
/// `dart run` starts at the package, so a fixed number of `parent` hops is
/// wrong for one of them.
String _findZukeAnalyzer() {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = p.normalize(
      p.join(directory.path, 'vendor-sdk', 'zuke_analyzer'),
    );
    if (File(p.join(candidate, 'pubspec.yaml')).existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      fail(
        'could not find vendor-sdk/zuke_analyzer above '
        '${Directory.current.path}',
      );
    }
    directory = parent;
  }
}

Future<Directory> _pluginEntry(
  Directory cache,
  String pluginRoot,
  String name,
) async {
  final entry = Directory(p.join(cache.path, name))..createSync();
  File(p.join(entry.path, 'pubspec.yaml')).writeAsStringSync(
    'name: plugin_entrypoint\nversion: 0.0.1\nenvironment:\n  sdk: ^3.6.0\n'
    'dependencies:\n  analysis_server_plugin: ^0.3.8\n'
    '  zuke_analyzer:\n    path: $pluginRoot\n',
  );
  File(p.join(entry.path, 'bin', 'plugin.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_pluginEntrypoint);
  File(p.join(entry.path, 'bin', 'plugin.aot'))
    ..createSync(recursive: true)
    ..writeAsStringSync('built from older sources');
  final resolved = await Process.run(resolveDartExecutable(), [
    '--suppress-analytics',
    'pub',
    'get',
  ], workingDirectory: entry.path);
  if (resolved.exitCode != 0) {
    fail('pub get failed for $name: ${resolved.stderr}');
  }
  return entry;
}

/// The entry point the Dart analysis server's plugin manager generates for a
/// locally resolved analyzer plugin.
const _pluginEntrypoint = '''
import 'dart:isolate';

import 'package:analysis_server_plugin/src/plugin_server.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/src/channel/isolate_channel.dart';
import 'package:zuke_analyzer/main.dart' as zuke_analyzer;

Future<void> main(List<String> args, SendPort sendPort) async {
  var pluginServer = PluginServer.new2(
    resourceProvider: PhysicalResourceProvider.INSTANCE,
    plugins: {
      'zuke_analyzer': zuke_analyzer.plugin,
    },
  );
  await pluginServer.initialize();
  var channel = PluginIsolateChannel(sendPort);
  pluginServer.start(channel);
}
''';
