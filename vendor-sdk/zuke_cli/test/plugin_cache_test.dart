import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zuke_cli/src/plugin_cache.dart';

import 'support/temporary_directory.dart';

void main() {
  late Directory root;
  late Directory cache;
  late Directory package;
  late Directory dependency;
  late Directory entry;
  late File source;
  late int compilations;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-cache-test-');
    cache = Directory('${root.path}/cache')..createSync();
    package = Directory('${root.path}/plugin')..createSync();
    dependency = Directory('${root.path}/cli')..createSync();
    for (final dir in [package, dependency]) {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      File('${dir.path}/lib/source.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('const value = 1;');
    }
    source = File('${dependency.path}/lib/source.dart');
    entry = Directory('${cache.path}/entry')..createSync();
    File('${entry.path}/pubspec.yaml').writeAsStringSync(
      'dependencies:\n  zuke_analyzer:\n    path: ${jsonEncode(package.path)}\n  another_plugin: any\n',
    );
    File('${entry.path}/pubspec.lock').writeAsStringSync(
      'packages:\n  zuke_analyzer:\n    source: path\n  zuke_cli:\n    source: path\n',
    );
    File('${entry.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'zuke_analyzer', 'rootUri': package.uri.toString()},
            {'name': 'zuke_cli', 'rootUri': dependency.uri.toString()},
          ],
        }),
      );
    File('${entry.path}/bin/plugin.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    File(
      '${entry.path}/bin/plugin.aot',
    ).writeAsStringSync('old compiled plugin');
    compilations = 0;
  });
  tearDown(() => deleteTemporaryDirectory(root));

  PluginCacheDoctor doctor({
    PluginCompiler? compiler,
    Set<String>? roots,
    PluginCompiler? buildVerifier,
  }) => PluginCacheDoctor(
    cacheRoot: cache,
    localZukeRoots:
        roots ??
        {Platform.isWindows ? package.path.toLowerCase() : package.path},
    resolver: (_) async {},
    buildVerifier: buildVerifier ?? (directory) async => 'verified',
    compiler:
        compiler ??
        (directory) async {
          compilations++;
          final file = File('${directory.path}/bin/plugin.aot')
            ..writeAsStringSync('compiled ${source.readAsStringSync()}');
          return sha256.convert(file.readAsBytesSync()).toString();
        },
  );

  test(
    'unknown provenance is not blessed; repair preserves other plugins',
    () async {
      final spec = File('${entry.path}/pubspec.yaml').readAsStringSync();
      expect((await doctor().inspect()).single.status, 'unverified');
      expect(compilations, 0);
      expect((await doctor().inspect(fix: true)).single.status, 'repaired');
      expect(compilations, 1);
      expect((await doctor().inspect()).single.status, 'current');
      expect(File('${entry.path}/pubspec.yaml').readAsStringSync(), spec);
      await doctor().inspect(fix: true);
      expect(compilations, 1);
    },
  );

  test(
    'dependency content changes with preserved timestamps are stale',
    () async {
      await doctor().inspect(fix: true);
      final modified = source.lastModifiedSync();
      source.writeAsStringSync('const value = 2;');
      source.setLastModifiedSync(modified);
      expect((await doctor().inspect()).single.status, 'stale');
    },
  );

  test(
    'touch alone does not invalidate; source additions and deletions do',
    () async {
      await doctor().inspect(fix: true);
      source.setLastModifiedSync(DateTime.now().add(const Duration(days: 1)));
      expect((await doctor().inspect()).single.status, 'current');
      final extra = File('${dependency.path}/lib/new.dart')
        ..writeAsStringSync('');
      expect((await doctor().inspect()).single.status, 'stale');
      await doctor().inspect(fix: true);
      extra.deleteSync();
      expect((await doctor().inspect()).single.status, 'stale');
    },
  );

  test('external snapshot replacement invalidates the receipt', () async {
    await doctor().inspect(fix: true);
    File(
      '${entry.path}/bin/plugin.aot',
    ).writeAsStringSync('different snapshot');
    expect((await doctor().inspect()).single.status, 'stale');
  });

  test('unrelated clones are neither audited nor rebuilt', () async {
    expect(await doctor(roots: {'unrelated'}).inspect(fix: true), isEmpty);
    expect(compilations, 0);
  });

  test(
    'a broken entry from another clone is not this workspace finding',
    () async {
      // Ownership comes from where the entry's packages resolve, so a corrupt
      // lock in someone else's checkout must not be reported here. Deciding
      // ownership from the lock instead made this workspace fail on a file it
      // does not own.
      File('${entry.path}/pubspec.lock').writeAsStringSync('not: [valid: yaml');
      final result = await doctor(roots: {'unrelated'}).inspect(fix: true);
      expect(result, isEmpty, reason: 'another clone is not ours to report');
      expect(compilations, 0);
    },
  );

  test('a dependency named entry does not displace the synthetic pubspec', () async {
    // A path dependency called `entry` once wrote the same digest key as the
    // cache entry's own pubspec.yaml, dropping it from the digest. The receipt
    // then stayed valid after the pubspec changed.
    final named = Directory('${root.path}/entry-pkg')..createSync();
    File('${named.path}/pubspec.yaml').writeAsStringSync('name: entry\n');
    File('${named.path}/lib/source.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('const value = 1;');
    File('${entry.path}/pubspec.yaml').writeAsStringSync(
      'dependencies:\n  zuke_analyzer:\n    path: ${jsonEncode(package.path)}\n'
      '  zuke_cli:\n    path: ${jsonEncode(dependency.path)}\n'
      '  entry:\n    path: ${jsonEncode(named.path)}\n',
    );
    File('${entry.path}/pubspec.lock').writeAsStringSync(
      'packages:\n  zuke_analyzer:\n    source: path\n'
      '  zuke_cli:\n    source: path\n  entry:\n    source: path\n',
    );
    File('${entry.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'zuke_analyzer', 'rootUri': package.uri.toString()},
          {'name': 'zuke_cli', 'rootUri': dependency.uri.toString()},
          {'name': 'entry', 'rootUri': named.uri.toString()},
        ],
      }),
    );
    expect((await doctor().inspect(fix: true)).single.status, 'repaired');
    expect((await doctor().inspect()).single.status, 'current');

    // The pubspec is one of the inputs, so changing it must invalidate.
    File('${entry.path}/pubspec.yaml').writeAsStringSync(
      'dependencies:\n  zuke_analyzer:\n    path: ${jsonEncode(package.path)}\n'
      '  zuke_cli:\n    path: ${jsonEncode(dependency.path)}\n'
      '  entry:\n    path: ${jsonEncode(named.path)}\n'
      '  # changed\n',
    );
    expect(
      (await doctor().inspect()).single.status,
      'stale',
      reason: 'a changed pubspec must not stay blessed',
    );
  });

  test('repairing through an alias is not undone by the real path', () async {
    // The digest used to hash the caller's spelling of the cache root, so a
    // receipt written through an alias looked stale when the same entry was
    // next reached by its real path -- repairing the same snapshot forever.
    final alias = p.join(root.path, 'alias-cache');
    expect(_linkDirectory(alias, cache), isTrue, reason: 'link not created');
    addTearDown(() => _removeLink(alias));
    final throughAlias = PluginCacheDoctor(
      cacheRoot: Directory(alias),
      localZukeRoots: {package.path},
      resolver: (_) async {},
      compiler: (directory) async {
        final file = File(p.join(directory.path, 'bin', 'plugin.aot'))
          ..writeAsStringSync('compiled ${source.readAsStringSync()}');
        return sha256.convert(file.readAsBytesSync()).toString();
      },
    );
    expect((await throughAlias.inspect(fix: true)).single.status, 'repaired');
    expect(
      (await throughAlias.inspect()).single.status,
      'current',
      reason: 'the same spelling twice must stay current',
    );
    expect(
      (await doctor().inspect()).single.status,
      'current',
      reason: 'and reaching it by its real path must agree',
    );
  });

  test(
    'a read-only audit points at the command that shows the build error',
    () async {
      // The analysis server reports a plugin that will not compile as a bare AOT
      // error with no command attached. A read-only audit cannot know why an
      // entry is stale, so it has to name the way to find out.
      final result = await doctor().inspect();
      expect(result.single.status, 'unverified');
      expect(result.single.message, contains('--check-build'));
    },
  );

  test(
    'check-build reports the compiler error instead of rebuilding',
    () async {
      // The reason a read-only audit is silent about: it never compiles. This
      // compiles to a throwaway output, so the operator sees the actual error
      // without the live snapshot being replaced by the diagnostic.
      final result = await doctor(
        buildVerifier: (_) async => throw StateError('undefined name Foo'),
      ).inspect(checkBuild: true);

      expect(result.single.status, 'failed');
      expect(result.single.message, contains('does not build'));
      expect(result.single.message, contains('undefined name Foo'));
      expect(
        File('${entry.path}/bin/plugin.aot').readAsStringSync(),
        'old compiled plugin',
        reason: 'verifying must never replace the snapshot it diagnosed',
      );
    },
  );

  test('check-build verifies one plugin root, not every cache entry', () async {
    // A workspace accumulates dozens of synthetic packages for the same local
    // clone. Verifying each one compiled the same sources 100+ times, which
    // measured at over twenty minutes.
    // A second synthetic package for the same local clone: the shape a real
    // workspace accumulates. It has to be a *complete* entry -- the audit skips
    // any directory without a pubspec and a package configuration, and a bare
    // directory would make this pass without ever being considered.
    final second = Directory('${cache.path}/entry-two')..createSync();
    File('${second.path}/pubspec.yaml').writeAsStringSync(
      'dependencies:\n  zuke_analyzer:\n    path: ${jsonEncode(package.path)}\n',
    );
    File('${second.path}/pubspec.lock').writeAsStringSync(
      'packages:\n  zuke_analyzer:\n    source: path\n  zuke_cli:\n    source: path\n',
    );
    File('${second.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'zuke_analyzer', 'rootUri': package.uri.toString()},
            {'name': 'zuke_cli', 'rootUri': dependency.uri.toString()},
          ],
        }),
      );
    File('${second.path}/bin/plugin.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    File('${second.path}/bin/plugin.aot')
      ..createSync(recursive: true)
      ..writeAsStringSync('old compiled plugin');
    var verifications = 0;
    final result = await doctor(
      buildVerifier: (_) async {
        verifications++;
        return 'verified';
      },
    ).inspect(checkBuild: true);

    // Two entries, two fingerprints, so each is compiled. What is shared is the
    // work, never the reporting.
    expect(verifications, 2, reason: 'each distinct fingerprint is built once');
    expect(
      _pathsWithStatus(result, 'stale'),
      containsAll(<String>[p.normalize(entry.path), p.normalize(second.path)]),
      reason: 'every entry gets its own finding, even when shared',
    );
    expect(second.existsSync(), isTrue);
  });

  test('identical entries share one build but are all reported', () async {
    // The performance case that made fingerprinting necessary: a workspace
    // accumulates many byte-identical synthetic packages.
    final twin = Directory('${cache.path}/twin')..createSync();
    _copyTree(entry, twin);
    var verifications = 0;
    final result = await doctor(
      buildVerifier: (_) async {
        verifications++;
        return 'verified';
      },
    ).inspect(checkBuild: true);
    expect(verifications, 1, reason: 'identical sources compile once');
    expect(
      _pathsWithStatus(result, 'stale'),
      containsAll(<String>[p.normalize(entry.path), p.normalize(twin.path)]),
      reason: 'sharing a verdict must not hide an entry',
    );
  });

  test(
    'entries differing only in analyzer version are built separately',
    () async {
      // The bug this replaces: keying on the plugin root reused one verdict for
      // every entry, so entries resolving a different analyzer never got their
      // own build. A real cache held 81 entries on one analyzer and 49 on
      // another, all sharing one plugin root.
      final older = Directory('${cache.path}/older-analyzer')..createSync();
      _copyTree(entry, older);
      File(
        p.join(older.path, '.dart_tool', 'package_config.json'),
      ).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'zuke_analyzer', 'rootUri': package.uri.toString()},
            {'name': 'zuke_cli', 'rootUri': dependency.uri.toString()},
            {'name': 'analyzer', 'rootUri': 'file:///pub/analyzer-12.1.0'},
          ],
        }),
      );
      final built = <String>[];
      final result = await doctor(
        buildVerifier: (directory) async {
          built.add(p.basename(directory.path));
          if (p.basename(directory.path) == 'older-analyzer') {
            throw StateError('incompatible analyzer version');
          }
          return 'verified';
        },
      ).inspect(checkBuild: true);

      expect(
        built,
        containsAll(<String>['entry', 'older-analyzer']),
        reason: 'a different analyzer must get its own build',
      );
      final byPath = {for (final f in result) p.normalize(f.path): f.status};
      expect(byPath[p.normalize(entry.path)], 'stale');
      expect(
        byPath[p.normalize(older.path)],
        'failed',
        reason: 'the divergent entry reports its own failure',
      );
    },
  );

  test('failed compilation never creates a receipt', () async {
    final result = await doctor(
      compiler: (_) async => throw StateError('compile failed'),
    ).inspect(fix: true);
    expect(result.single.status, 'failed');
    expect(
      File('${entry.path}/.zuke-plugin-receipt.json').existsSync(),
      isFalse,
    );
    expect(
      File('${entry.path}/bin/plugin.aot').readAsStringSync(),
      'old compiled plugin',
    );
  });

  test(
    'sources changing during compilation cannot receive a receipt',
    () async {
      final result = await doctor(
        compiler: (_) async {
          source.writeAsStringSync('changed during compilation');
          return 'unused';
        },
      ).inspect(fix: true);
      expect(result.single.status, 'failed');
      expect(
        File('${entry.path}/.zuke-plugin-receipt.json').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'real AOT compilation replaces an existing snapshot and writes a depfile',
    () async {
      final real = PluginCacheDoctor(
        cacheRoot: cache,
        localZukeRoots: {package.path},
        resolver: (_) async {},
      );
      final result = await real.inspect(fix: true);
      expect(result.single.status, 'repaired', reason: result.single.message);
      expect(File('${entry.path}/bin/depfile.txt').existsSync(), isTrue);
      expect((await real.inspect()).single.status, 'current');
      expect(
        File('${entry.path}/bin/plugin.zuke-repair.aot').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'missing local dependency is reported without deleting the entry',
    () async {
      // Remove one file, not the fixture tree: the public package must remain
      // untouched when a dependency checkout becomes unavailable.
      File('${dependency.path}/pubspec.yaml').deleteSync();
      expect((await doctor().inspect(fix: true)).single.status, 'orphaned');
      expect(entry.existsSync(), isTrue);
      expect(compilations, 0);
    },
  );

  test(
    'a cache root reached through an alias is audited, not refused',
    () async {
      // The shape a Windows runner produces when the temp directory is handed
      // out under an 8.3 alias: the caller's spelling of the cache root and the
      // root's real spelling differ, but nothing about the entry is unsafe.
      final alias = p.join(root.path, 'alias-cache');
      expect(_linkDirectory(alias, cache), isTrue, reason: 'link not created');
      addTearDown(() => _removeLink(alias));
      final aliased = PluginCacheDoctor(
        cacheRoot: Directory(alias),
        localZukeRoots: {
          Platform.isWindows ? package.path.toLowerCase() : package.path,
        },
        resolver: (_) async {},
      );
      final result = await aliased.inspect(fix: true);
      expect(result.single.status, 'repaired', reason: result.single.message);
    },
  );

  test('a cache entry that is itself a link is still refused', () async {
    // The counterpart to the alias case: normalizing the spelling must not
    // turn into ignoring a genuine link inside the cache.
    // A complete entry, living outside the cache, linked into it.
    final elsewhere = Directory('${root.path}/elsewhere/entry')
      ..createSync(recursive: true);
    _copyTree(entry, elsewhere);
    final linked = p.join(cache.path, 'linked-entry');
    expect(
      _linkDirectory(linked, elsewhere),
      isTrue,
      reason: 'link not created',
    );
    addTearDown(() => _removeLink(linked));
    final result = await doctor().inspect(fix: true);
    expect(
      result.map((finding) => finding.status),
      contains('failed'),
      reason: 'a linked entry must not be repaired in place',
    );
    expect(
      result
          .where((finding) => finding.status == 'failed')
          .map((finding) => finding.message)
          .join(),
      contains('is a link'),
    );
  });

  test(
    'a link belonging to another plugin does not fail a Zuke audit',
    () async {
      // The plugin cache is shared with every other Dart plugin, so a link that
      // is not ours is none of our business and must not fail `doctor --fix`.
      final foreign = Directory('${root.path}/foreign-plugin')
        ..createSync(recursive: true);
      File(p.join(foreign.path, 'pubspec.yaml')).writeAsStringSync(
        'name: some_other_plugin\ndependencies:\n  analyzer: any\n',
      );
      final linked = p.join(cache.path, 'foreign-link');
      expect(
        _linkDirectory(linked, foreign),
        isTrue,
        reason: 'link not created',
      );
      addTearDown(() => _removeLink(linked));
      final result = await doctor().inspect(fix: true);
      expect(
        result.map((finding) => finding.path),
        isNot(contains(p.normalize(linked))),
        reason: 'a foreign plugin must not appear in a Zuke audit',
      );
      expect(result.single.status, 'repaired');
    },
  );

  test('a Zuke entry with a corrupt lock is reported, not dropped', () async {
    // Ownership is established from the pubspec, so a later parse failure is a
    // real problem to report. Previously the entry vanished from the audit.
    File('${entry.path}/pubspec.lock').writeAsStringSync('not: [valid: yaml');
    final result = await doctor().inspect();
    expect(result, hasLength(1), reason: 'the entry must not disappear');
    expect(result.single.status, 'failed');
    expect(result.single.message, contains('audit'));
  });

  test('an entry whose lock names a missing package is reported', () async {
    // The other way metadata breaks: the lock is valid but refers to a package
    // the config does not define.
    File('${entry.path}/pubspec.lock').writeAsStringSync(
      'packages:\n  zuke_analyzer:\n    source: path\n'
      '  zuke_cli:\n    source: path\n  ghost:\n    source: path\n',
    );
    final result = await doctor().inspect();
    expect(result, hasLength(1), reason: 'the entry must not disappear');
    expect(result.single.status, 'failed');
    expect(result.single.message, contains('ghost'));
  });
}

/// Creates a link at [link] pointing at [target], returning false when the
/// platform refuses. A directory junction is used on Windows because creating
/// one needs no elevation.
/// Cache paths come from `listSync` and the fixture builds its own with a
/// forward slash, so both sides are normalized before comparing.
Set<String> _pathsWithStatus(
  List<PluginCacheFinding> findings,
  String status,
) => findings
    .where((finding) => finding.status == status)
    .map((finding) => p.normalize(finding.path))
    .toSet();

void _copyTree(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: from.path);
    if (entity is Directory) {
      Directory(p.join(to.path, relative)).createSync(recursive: true);
    } else if (entity is File) {
      File(p.join(to.path, relative))
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

bool _linkDirectory(String link, Directory target) {
  // mklink rejects a path containing a forward slash, and the fixture builds
  // some of its paths with one.
  final from = p.normalize(link);
  final to = p.normalize(target.path);
  final result = Platform.isWindows
      ? Process.runSync('cmd', ['/c', 'mklink', '/J', from, to])
      // Not `cmd /c ln`: cmd does not exist off Windows, and the Unix suite
      // runs this test too.
      : Process.runSync('ln', ['-s', to, from]);
  return result.exitCode == 0;
}

void _removeLink(String link) {
  final from = p.normalize(link);
  if (Platform.isWindows) {
    // rmdir removes a junction without touching its target.
    Process.runSync('cmd', ['/c', 'rmdir', from]);
  } else {
    // A symlink is a Link, and deleting it as a Directory would follow it.
    Link(from).deleteSync();
  }
}
