import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'path_safety.dart';
import 'tooling/analyzer_sdk.dart';

typedef PluginCompiler = Future<String> Function(Directory directory);
typedef PluginResolver = Future<void> Function(Directory directory);
typedef PluginCacheProgress =
    void Function(int completed, int total, PluginCacheFinding? finding);

/// How many entries a `doctor --fix` repairs at once when the caller does not
/// choose. Past four, the compiles contend for the same cores and stop scaling:
/// 24 entries took 113s at four workers against 361s at one.
final int defaultRepairWorkers = Platform.numberOfProcessors < 4
    ? Platform.numberOfProcessors
    : 4;

/// Ceiling for [PluginCacheDoctor.inspect]'s `repairWorkers`.
const int maxRepairWorkers = 16;

/// One cache entry's outcome, shared by the audit and the prune.
///
/// Both report the same three facts about a path, and both serialise the same
/// way, so the fields and [toJson] live here. What differs is what each adds:
/// an audit finding carries [PluginCacheFinding.needsRepair], and a prune result
/// carries `bytes` and treats a refusal as a failure. `failed` is therefore left
/// to the subclass rather than inherited, because the two do not agree on which
/// statuses count.
base class PluginCacheEntryResult {
  final String path;
  final String status;
  final String message;

  const PluginCacheEntryResult(this.path, this.status, this.message);

  Map<String, Object?> toJson() => {
    'path': path,
    'status': status,
    'message': message,
  };
}

final class PluginCacheFinding extends PluginCacheEntryResult {
  const PluginCacheFinding(super.path, super.status, super.message);

  bool get failed => status == 'failed';

  /// Whether this finding describes something actually wrong with an entry.
  ///
  /// Named rather than derived from a blacklist of statuses so that a status
  /// invented later cannot silently become a failure. `deferred` is excluded on
  /// purpose: it records a limit the user asked for, so treating it as a
  /// failure made `doctor --fix --max-plugin-repairs N` exit non-zero on a run
  /// that did everything it was asked to do.
  static const repairing = {'stale', 'unverified', 'orphaned', 'failed'};

  bool get needsRepair => repairing.contains(status);
}

/// Small, machine-readable inventory of classified audit findings. Third-party
/// and unattributable cache directories are excluded; an explicitly requested
/// missing path may contribute a failed finding even though no entry exists.
final class PluginCacheSummary {
  final int entries;
  final int snapshotBytes;
  final Map<String, int> statuses;

  const PluginCacheSummary(this.entries, this.snapshotBytes, this.statuses);

  factory PluginCacheSummary.fromFindings(
    Iterable<PluginCacheFinding> findings,
  ) {
    final counts = <String, int>{};
    var entries = 0;
    var bytes = 0;
    for (final finding in findings) {
      entries++;
      counts.update(finding.status, (count) => count + 1, ifAbsent: () => 1);
      // The cache can contain links. Never follow one merely to count bytes.
      if (FileSystemEntity.typeSync(finding.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      final snapshot = _snapshotFile(finding.path);
      try {
        if (FileSystemEntity.typeSync(snapshot.path, followLinks: false) ==
            FileSystemEntityType.file) {
          bytes += snapshot.lengthSync();
        }
      } on FileSystemException {
        // A concurrent analysis server may replace the snapshot during an
        // inventory. The diagnostic status remains useful without its size.
      }
    }
    return PluginCacheSummary(entries, bytes, counts);
  }

  int get attention =>
      entries -
      (statuses['current'] ?? 0) -
      (statuses['repaired'] ?? 0) -
      (statuses['deferred'] ?? 0);

  Map<String, Object> toJson() => {
    'entries': entries,
    'snapshotBytes': snapshotBytes,
    'statuses': statuses,
  };
}

final class PluginCachePruneResult extends PluginCacheEntryResult {
  final int bytes;

  const PluginCachePruneResult(
    super.path,
    super.status,
    this.bytes,
    super.message,
  );

  bool get failed => status == 'refused' || status == 'failed';

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'bytes': bytes};
}

/// Generate's one-line advisory. Detailed entry paths remain in `doctor`.
void printPluginCacheSummary(
  Iterable<PluginCacheFinding> findings, {
  void Function(String line)? sink,
}) {
  final summary = PluginCacheSummary.fromFindings(findings);
  if (summary.attention == 0) return;
  (sink ?? stdout.writeln)(
    'ZUKE-PLUGIN-CACHE: ${summary.attention} of ${summary.entries} '
    'local analyzer cache entries need attention '
    '(${formatPluginCacheMiB(summary.snapshotBytes)} in snapshots). '
    'Run zuke doctor for details.',
  );
}

String formatPluginCacheMiB(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

File _snapshotFile(String directory) =>
    File(p.join(directory, 'bin', 'plugin.aot'));

/// Audits only synthetic packages resolving the workspace's local Zuke clone.
/// A receipt is created only after compilation, never by assuming an existing
/// AOT was built from the sources currently on disk.
final class PluginCacheDoctor {
  final Directory cacheRoot;
  final Set<String> localZukeRoots;
  final PluginCompiler compiler;
  final PluginResolver resolver;

  /// Compiles [directory] to a throwaway output, purely to observe whether it
  /// builds. Never writes the live snapshot.
  final PluginCompiler buildVerifier;

  PluginCacheDoctor({
    required this.cacheRoot,
    required Set<String> localZukeRoots,
    PluginCompiler? compiler,
    PluginResolver? resolver,
    PluginCompiler? buildVerifier,
  }) : localZukeRoots = localZukeRoots.map(_canonical).toSet(),
       compiler = compiler ?? _compile,
       resolver = resolver ?? _resolve,
       buildVerifier = buildVerifier ?? _verifyBuild;

  static PluginCacheDoctor forWorkspace(String root) {
    final roots = <String>{};
    var directory = Directory(root).absolute;
    while (true) {
      final options = File(p.join(directory.path, 'analysis_options.yaml'));
      if (options.existsSync()) {
        final yaml = loadYaml(options.readAsStringSync());
        final plugins = yaml is Map ? yaml['plugins'] : null;
        final plugin = plugins is Map ? plugins['zuke_analyzer'] : null;
        if (plugin is Map && plugin['path'] is String) {
          roots.add(
            _canonical(p.join(directory.path, plugin['path'] as String)),
          );
        }
      }
      final config = File(
        p.join(directory.path, '.dart_tool', 'package_config.json'),
      );
      if (config.existsSync()) {
        final packages = _packageRoots(config);
        for (final name in ['zuke_analyzer', 'zuke_cli']) {
          final package = packages[name];
          if (package != null) roots.add(_canonical(package));
        }
        break;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    final home = Platform.isWindows
        ? Platform.environment['LOCALAPPDATA']
        : Platform.environment['HOME'];
    if (home == null) {
      throw const FileSystemException('Cannot locate Dart plugin cache');
    }
    return PluginCacheDoctor(
      cacheRoot: Directory(p.join(home, '.dartServer', '.plugin_manager')),
      localZukeRoots: roots,
    );
  }

  Future<List<PluginCacheFinding>> inspect({
    bool fix = false,
    bool checkBuild = false,
    int? maxRepairs,
    Set<String>? onlyEntries,
    Set<String>? contextRoots,
    int? repairWorkers,
    PluginCacheProgress? onProgress,
  }) async {
    if (maxRepairs != null && maxRepairs < 0) {
      throw ArgumentError.value(
        maxRepairs,
        'maxRepairs',
        'must be non-negative',
      );
    }
    // Repair runs one `dart compile` per worker, so the bound is about memory
    // and CPU contention rather than a correctness limit. Measured on a 16-core
    // host, 4 workers repaired 24 entries in 113s against 361s for one.
    final workers = repairWorkers ?? defaultRepairWorkers;
    if (workers < 1 || workers > maxRepairWorkers) {
      throw ArgumentError.value(
        repairWorkers,
        'repairWorkers',
        'must be between 1 and $maxRepairWorkers',
      );
    }
    if (localZukeRoots.isEmpty || !cacheRoot.existsSync()) return const [];
    final findings = <PluginCacheFinding>[];
    final repairs = <Directory>[];
    final requested = onlyEntries?.map(_canonical).toSet();
    // Dart 3.12 names a new-style synthetic package with MD5(context root
    // path). This filter is advisory only: a future SDK may change the naming
    // scheme, in which case generate simply finds no entry and doctor remains
    // the complete audit.
    final contextKeys = contextRoots?.map(pluginCacheKeyForContextRoot).toSet();
    final matched = <String>{};
    // Share hashes only during the sequential audit. Repair workers use their
    // own fresh hashes to detect sources changing during compilation.
    final hashes = <String, String>{};
    final verifiedBuilds = <String, _BuildVerdict>{};
    final entries = cacheRoot.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      // Windows reports a directory junction as a Link, not a Directory, so
      // testing for Directory alone would skip it and leave the user with a
      // cache entry that is never audited, repaired, or explained.
      if (entity is! Directory && entity is! Link) continue;
      if (contextKeys != null &&
          !contextKeys.contains(p.basename(entity.path))) {
        continue;
      }
      if (fix &&
          requested != null &&
          !requested.contains(_canonical(entity.path))) {
        continue;
      }
      var selected = false;
      try {
        // A link is never written through: repairing one would act on a
        // directory the cache does not own. Reading the pubspec is safe and is
        // what establishes ownership below.
        //
        // The cache is shared with other plugins, so a link is only reported
        // once it is known to be one of ours: without this a third-party
        // plugin's link fails `zuke doctor` for a workspace it has nothing to
        // do with. Windows reports a directory junction as a Link rather than
        // a Directory, so without this branch such entries would be skipped by
        // the Directory-only test, never audited, repaired, or explained.
        if (entity is! Directory) {
          if (!_declaresZuke(entity.path)) continue;
          matched.add(_canonical(entity.path));
          findings.add(
            PluginCacheFinding(
              entity.path,
              'failed',
              'Cache entry is a link and cannot be audited or repaired safely. '
                  'Replace it with a real directory.',
            ),
          );
          continue;
        }
        if (!_declaresZuke(entity.path)) continue;
        final config = File(
          p.join(entity.path, '.dart_tool', 'package_config.json'),
        );
        if (!config.existsSync()) continue; // no compiled plugin to audit
        // Which clone an entry belongs to is decided by where its packages
        // resolve, not by its lock file. The lock is the thing that can be
        // corrupt, so reading ownership from it first would either report
        // another clone's breakage as this workspace's or drop this clone's.
        final Map<String, String> packages;
        try {
          packages = _packageRoots(config);
        } on Object {
          // Unreadable configuration cannot be attributed to any clone, and
          // guessing would make another checkout's entry our problem.
          continue;
        }
        if (!_ownsResolvedPackages(packages)) continue;
        // Ours, and attributable, so a later parse failure is a real finding
        // rather than an entry that quietly disappears from the audit.
        selected = true;
        matched.add(_canonical(entity.path));
        final local = _localPackages(entity, packages);
        if (!_safeEntry(entity)) {
          throw const FileSystemException(
            'Linked cache entry cannot be repaired safely',
          );
        }

        final snapshot = _snapshotFile(entity.path);
        final receipt = File(p.join(entity.path, '.zuke-plugin-receipt.json'));
        String digest;
        try {
          digest = _sourceDigest(entity, local, hashes);
        } on FileSystemException catch (error) {
          findings.add(
            PluginCacheFinding(
              entity.path,
              'orphaned',
              'Local plugin sources are unavailable: $error. Entry left untouched.',
            ),
          );
          continue;
        }
        final saved = _readReceipt(receipt);
        final current =
            snapshot.existsSync() &&
            saved != null &&
            saved['sourceDigest'] == digest &&
            saved['snapshotDigest'] == _hash(snapshot, hashes);
        if (current) {
          findings.add(
            PluginCacheFinding(
              entity.path,
              'current',
              'Plugin content verified.',
            ),
          );
          continue;
        }
        if (!fix) {
          // A read-only audit can report that an entry is stale but never why,
          // and the analysis server reports the reason as a bare AOT compile
          // error with no command attached. Compiling to a throwaway output
          // turns that into a finding the user can act on, without touching the
          // snapshot the editor is using.
          if (checkBuild) {
            // Share one compile across entries whose sources are identical, but
            // never across entries that merely point at the same plugin root.
            // Synthetic packages for one clone can resolve different analyzer
            // versions, and those builds genuinely differ -- a real cache held
            // 81 entries on one analyzer, 49 on another and 1 on a third, all
            // sharing a single plugin root. Keyed on the root, the first
            // verdict was reused for all of them and the entry most likely to
            // fail to build was the one silently skipped. Keyed on the source
            // fingerprint the same cache costs three compiles, not 131.
            final fingerprint = _buildFingerprint(entity, local, hashes);
            final shared = verifiedBuilds[fingerprint];
            if (shared != null) {
              // Still reported: the entry is stale or unbuildable whatever we
              // decided about its twin, and the user needs to see its own path.
              findings.add(
                PluginCacheFinding(entity.path, shared.status, shared.message),
              );
              continue;
            }
            _BuildVerdict verdict;
            try {
              await buildVerifier(entity);
              verdict = const _BuildVerdict(
                'stale',
                'Snapshot is out of date but still compiles.',
              );
            } on Object catch (error) {
              verdict = _BuildVerdict(
                'failed',
                'The plugin does not build, so rebuilding cannot fix it: $error',
              );
            }
            verifiedBuilds[fingerprint] = verdict;
            findings.add(
              PluginCacheFinding(entity.path, verdict.status, verdict.message),
            );
            continue;
          }
          findings.add(
            PluginCacheFinding(
              entity.path,
              saved == null ? 'unverified' : 'stale',
              // Naming the likely cause matters most here. A read-only audit
              // cannot know why the snapshot is unusable, but the overwhelmingly
              // common reason is that it will not build -- and the analysis server
              // reports that as a raw AOT compile error, with nothing pointing at
              // a command that would show it in context.
              saved == null
                  ? 'Existing AOT has no trusted content receipt. Run '
                        '`zuke doctor --check-build` to compile it here and see '
                        'why, or `--fix` to rebuild it.'
                  : 'Plugin sources or compiled snapshot changed. Run '
                        '`zuke doctor --check-build` to compile it here and see '
                        'why, or `--fix` to rebuild it.',
            ),
          );
          continue;
        }
        repairs.add(entity);
      } on Object catch (error) {
        if (!selected) continue;
        findings.add(
          PluginCacheFinding(
            entity.path,
            'failed',
            'Could not ${fix ? 'repair' : 'audit'} plugin cache: $error',
          ),
        );
      }
    }
    if (fix) {
      final inScope = requested == null
          ? repairs
          : repairs
                .where((entry) => requested.contains(_canonical(entry.path)))
                .toList();
      final selected = maxRepairs == null
          ? inScope
          : inScope.take(maxRepairs).toList();
      final selectedPaths = selected.map((entry) => entry.path).toSet();
      // Per entry, because these are the ones the user still has to deal with
      // and --plugin-cache-entry accepts them straight back. An entry excluded
      // with --plugin-cache-entry is not deferred, it is out of scope, and
      // reporting it turned a one-entry request into hundreds of findings about
      // entries the user never named. A plain `zuke doctor` still reports those
      // as stale.
      for (final entry in inScope.where(
        (entry) => !selectedPaths.contains(entry.path),
      )) {
        findings.add(
          PluginCacheFinding(
            entry.path,
            'deferred',
            'Repair deferred by --max-plugin-repairs. Pass this entry to '
                '--plugin-cache-entry, or run doctor --fix again, to repair it.',
          ),
        );
      }
      for (final missing
          in requested?.difference(matched) ?? const <String>{}) {
        findings.add(
          PluginCacheFinding(
            missing,
            'failed',
            'Requested entry is not a cache entry for this local Zuke clone.',
          ),
        );
      }
      onProgress?.call(0, selected.length, null);
      var next = 0;
      var completed = 0;
      Future<void> worker() async {
        while (next < selected.length) {
          final entity = selected[next++];
          final finding = await _repair(entity);
          findings.add(finding);
          onProgress?.call(++completed, selected.length, finding);
        }
      }

      await Future.wait([
        for (var i = 0; i < workers && i < selected.length; i++) worker(),
      ]);
    }
    findings.sort((a, b) => a.path.compareTo(b.path));
    return findings;
  }

  Future<PluginCacheFinding> _repair(Directory entity) async {
    // Each worker owns its entry and hash maps. A lock also serializes other
    // doctor invocations; the analysis server does not honor it, so the final
    // snapshot hash still detects concurrent writes.
    final config = File(
      p.join(entity.path, '.dart_tool', 'package_config.json'),
    );
    final snapshot = _snapshotFile(entity.path);
    final receipt = File(p.join(entity.path, '.zuke-plugin-receipt.json'));
    final lock = File(p.join(entity.path, '.zuke-plugin-repair.lock'));
    RandomAccessFile? handle;
    late PluginCacheFinding finding;
    try {
      handle = lock.openSync(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      if (!_safeEntry(entity)) {
        throw const FileSystemException('Cache entry changed');
      }
      await resolver(entity);
      final resolvedLocal = _localPackages(entity, _packageRoots(config));
      final before = _sourceDigest(entity, resolvedLocal, {});
      final compiledDigest = await compiler(entity);
      final after = _sourceDigest(entity, resolvedLocal, {});
      if (before != after) {
        throw const FileSystemException(
          'Sources changed during compilation; retry doctor --fix',
        );
      }
      if (!snapshot.existsSync()) {
        throw const FileSystemException('Compiler produced no plugin.aot');
      }
      if (_hash(snapshot, {}) != compiledDigest) {
        throw const FileSystemException(
          'Snapshot changed during repair; retry after stopping analysis',
        );
      }
      receipt.writeAsStringSync(
        jsonEncode({'sourceDigest': after, 'snapshotDigest': compiledDigest}),
        flush: true,
      );
      finding = PluginCacheFinding(
        entity.path,
        'repaired',
        'Plugin rebuilt and content verified. Restart the analysis server / reload the window.',
      );
    } on Object catch (error) {
      finding = PluginCacheFinding(
        entity.path,
        'failed',
        'Could not repair plugin cache: $error',
      );
    } finally {
      try {
        handle?.closeSync();
      } on Object catch (error) {
        // Never downgrade a repair that already wrote its receipt: the next
        // audit reads that entry as `current`, so reporting a failure here would
        // make the same entry fail once and pass forever after. A close failure
        // only matters when the repair itself did not get far enough to record
        // anything, and that case already reported above.
        if (finding.status == 'repaired') {
          log(
            'released the repair lock for ${entity.path} with an error after a '
            'successful repair: $error',
            name: 'zuke.plugin_cache',
          );
        }
      }
    }
    return finding;
  }

  /// Removes only explicitly named, Zuke-only synthetic packages. No age or
  /// build fingerprint can establish that another context root is unused.
  /// Callers must stop the analysis server before applying a plan.
  List<PluginCachePruneResult> pruneSelected(
    Set<String> paths, {
    required String currentContextRoot,
    bool dryRun = true,
  }) {
    final results = <PluginCachePruneResult>[];
    final protectedKey = pluginCacheKeyForContextRoot(currentContextRoot);
    for (final requested in paths.toList()..sort()) {
      final directory = Directory(p.absolute(requested));
      final path = directory.path;
      try {
        if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(p.basename(path)) ||
            p.basename(path) == protectedKey ||
            FileSystemEntity.typeSync(path, followLinks: false) !=
                FileSystemEntityType.directory ||
            !_isDirectCacheEntry(directory)) {
          results.add(
            PluginCachePruneResult(
              path,
              'refused',
              0,
              'Not an eligible, direct cache entry, or it belongs to the current context root.',
            ),
          );
          continue;
        }
        // One walk answers the link question and sizes the entry. `_safeEntry`
        // takes the link answer rather than walking again to rediscover it.
        final scan = _scanEntry(directory);
        if (!_safeEntry(directory, hasLink: scan.hasLink)) {
          results.add(
            PluginCachePruneResult(
              path,
              'refused',
              0,
              'Not an eligible, direct cache entry, or it belongs to the current context root.',
            ),
          );
          continue;
        }
        final dependencies = _zukeDependenciesOf(path);
        if (dependencies == null ||
            !dependencies.containsKey('zuke_analyzer')) {
          results.add(
            PluginCachePruneResult(
              path,
              'refused',
              0,
              'Synthetic package does not declare zuke_analyzer.',
            ),
          );
          continue;
        }
        if (dependencies.keys.any(
          (name) => name != 'zuke_analyzer' && name != 'analysis_server_plugin',
        )) {
          results.add(
            PluginCachePruneResult(
              path,
              'refused',
              0,
              'Synthetic package also contains another plugin or dependency.',
            ),
          );
          continue;
        }
        final config = File(p.join(path, '.dart_tool', 'package_config.json'));
        if (!config.existsSync() ||
            !_ownsResolvedPackages(_packageRoots(config))) {
          results.add(
            PluginCachePruneResult(
              path,
              'refused',
              0,
              'Entry does not resolve to this local Zuke clone.',
            ),
          );
          continue;
        }
        final bytes = scan.bytes;
        if (!dryRun) {
          // Re-check immediately before a recursive delete. Never traverse links
          // or leave this cache root.
          if (!_safeEntry(directory)) {
            throw const FileSystemException('Cache entry changed before prune');
          }
          directory.deleteSync(recursive: true);
        }
        results.add(
          PluginCachePruneResult(
            path,
            dryRun ? 'ready' : 'pruned',
            bytes,
            dryRun
                ? 'Would remove this entry after the analysis server stops.'
                : 'Entry removed. Restart the analysis server before analysis.',
          ),
        );
      } on Object catch (error) {
        results.add(
          PluginCachePruneResult(
            path,
            'failed',
            0,
            'Could not inspect or prune cache entry: $error',
          ),
        );
      }
    }
    return results;
  }

  bool _ownsResolvedPackages(Map<String, String> packages) =>
      packages.entries.any(
        (candidate) =>
            (candidate.key == 'zuke_cli' || candidate.key == 'zuke_analyzer') &&
            localZukeRoots.contains(_canonical(candidate.value)),
      );

  /// One recursive pass over an entry, answering both questions the prune needs:
  /// whether it contains a link, and how large it is.
  ///
  /// The link check and the size count used to be two separate walks, so pruning
  /// walked a 13 MB entry three times over. One pass covers both; the walk is
  /// repeated only immediately before a delete, which is a safety requirement
  /// rather than a duplicate.
  static _CacheEntryScan _scanEntry(Directory directory) {
    var hasLink = false;
    var bytes = 0;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        hasLink = true;
        continue;
      }
      if (entity is File) bytes += entity.lengthSync();
    }
    return _CacheEntryScan(hasLink: hasLink, bytes: bytes);
  }

  bool _isDirectCacheEntry(Directory directory) {
    // Compare canonical spellings rather than the literal one the caller passed
    // in. Windows hands callers an 8.3 alias for a path whose ancestor resolves
    // to its long form, and a junctioned cache root is the same shape. Testing
    // the caller's spelling for equality with the resolved one then rejects a
    // perfectly ordinary entry and reports every cached plugin as unrepairable.
    final base = _canonical(cacheRoot.path);
    final resolved = _canonical(directory.path);
    final isDirectChildOfCache = p.equals(p.dirname(resolved), base);
    // Checked separately because canonicalizing both sides of an equality test
    // would hide a link that points at a sibling entry inside the cache.
    final entryItselfIsALink =
        FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.link;
    return isDirectChildOfCache && !entryItselfIsALink;
  }

  bool _safeEntry(Directory directory, {bool? hasLink}) =>
      _isDirectCacheEntry(directory) &&
      !(hasLink ??
          directory
              .listSync(recursive: true, followLinks: false)
              .any((entity) => entity is Link));

  /// The plugin root whose sources decide whether [entity] builds.
  ///
  /// Whether the cache entry at [path] is a Zuke plugin entry. This is the
  /// ownership test: the plugin cache is shared with every other Dart plugin,
  /// so entries belonging to someone else are none of our business.
  static bool _declaresZuke(String path) {
    final dependencies = _zukeDependenciesOf(path);
    return dependencies != null && dependencies.containsKey('zuke_analyzer');
  }

  /// The entry's declared dependencies, or null when the pubspec is missing,
  /// unparseable, or has no dependency map.
  ///
  /// Parsed once and reused: the prune check reads this to prove the entry holds
  /// nothing but Zuke, having already asked whether it declares Zuke at all.
  static Map<Object?, Object?>? _zukeDependenciesOf(String path) {
    final spec = File(p.join(path, 'pubspec.yaml'));
    if (!spec.existsSync()) return null;
    final Object? yaml;
    try {
      yaml = loadYaml(spec.readAsStringSync());
    } on YamlException {
      // An unreadable pubspec means the entry cannot be shown to be ours.
      return null;
    }
    if (yaml is! Map) return null;
    final dependencies = yaml['dependencies'];
    return dependencies is Map ? dependencies : null;
  }

  static Map<String, String> _localPackages(
    Directory directory,
    Map<String, String> packages,
  ) {
    final lock = loadYaml(
      File(p.join(directory.path, 'pubspec.lock')).readAsStringSync(),
    );
    if (lock is! Map || lock['packages'] is! Map) {
      throw const FormatException('Invalid plugin pubspec.lock');
    }
    return {
      for (final entry in (lock['packages'] as Map).entries)
        if (entry.value is Map && entry.value['source'] == 'path')
          entry.key as String:
              packages[entry.key] ??
              (throw FormatException(
                'Missing package configuration for ${entry.key}',
              )),
    };
  }

  /// Every file whose content decides whether [directory] builds, paired with a
  /// logical key that does not contain the entry's own directory.
  ///
  /// The absolute path is kept for the receipt digest, which must change if a
  /// file moves. The logical key is what makes two byte-identical synthetic
  /// packages recognisable as the same build: it is stable across cache
  /// directories but still distinguishes `zuke_analyzer/lib/src/x.dart` from
  /// `zuke_cli/lib/src/x.dart`, which a bare basename would not.
  ///
  /// The two namespaces are prefixed with `@`, which a pub package name cannot
  /// contain. Without that, a path dependency named `entry` would write the same
  /// key as the synthetic pubspec and silently drop it from the digest, so a
  /// changed pubspec would not invalidate the receipt.
  static Map<String, String> _buildInputs(
    Directory directory,
    Map<String, String> local,
  ) {
    final files = <String, String>{
      for (final name in [
        'pubspec.yaml',
        'pubspec.lock',
        '.dart_tool/package_config.json',
        'bin/plugin.dart',
      ])
        '@synthetic/$name': p.join(directory.path, name),
    };
    for (final dependency in local.entries) {
      final root = dependency.value;
      final prefix = '@pkg/${dependency.key}';
      files['$prefix/pubspec.yaml'] = p.join(root, 'pubspec.yaml');
      final overrides = File(p.join(root, 'pubspec_overrides.yaml'));
      if (overrides.existsSync()) {
        files['$prefix/pubspec_overrides.yaml'] = overrides.path;
      }
      final lib = Directory(p.join(root, 'lib'));
      if (!lib.existsSync()) {
        throw FileSystemException('Missing local library', lib.path);
      }
      for (final source in lib.listSync(recursive: true, followLinks: false)) {
        if (source is Link) {
          throw FileSystemException(
            'Linked source cannot be verified',
            source.path,
          );
        }
        if (source is File) {
          files['$prefix/${p.relative(source.path, from: root)}'] = source.path;
        }
      }
    }
    return files;
  }

  /// A path-independent fingerprint of everything that decides whether a cache
  /// entry builds, keyed on content alone.
  ///
  /// The receipt's [sourceDigest] cannot serve as a build key: it is keyed on
  /// absolute paths, so the many byte-identical synthetic packages a workspace
  /// accumulates would never match each other. This one deliberately drops the
  /// entry's own directory while keeping the content that does vary between
  /// entries -- notably `.dart_tool/package_config.json`, which records which
  /// analyzer version an entry resolves.
  static String _buildFingerprint(
    Directory directory,
    Map<String, String> local,
    Map<String, String> hashes,
  ) {
    final inputs = _buildInputs(directory, local);
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'sdk': resolveDartExecutable(),
              'sdkVersion': File(
                p.join(resolveAnalyzerSdkPath()!, 'version'),
              ).readAsStringSync(),
              'contents': {
                for (final key in inputs.keys.toList()..sort())
                  key: _hash(File(inputs[key]!), hashes),
              },
            }),
          ),
        )
        .toString();
  }

  static String _sourceDigest(
    Directory directory,
    Map<String, String> local,
    Map<String, String> hashes,
  ) {
    final inputs = _buildInputs(directory, local);
    // Keyed on the canonical path, not the spelling the caller used. A cache
    // root reached through an 8.3 alias or a junction resolves to the same
    // files, and hashing the spelling made a receipt written one way look stale
    // the next time the entry was reached the other way -- so alternating
    // between spellings repaired the same snapshot forever.
    final canonical = {
      for (final input in inputs.entries) _canonical(input.value): input.value,
    };
    final ordered = canonical.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'sdk': resolveDartExecutable(),
              'sdkVersion': File(
                p.join(resolveAnalyzerSdkPath()!, 'version'),
              ).readAsStringSync(),
              'files': {
                for (final path in ordered)
                  path: _hash(File(canonical[path]!), hashes),
              },
            }),
          ),
        )
        .toString();
  }

  static String _hash(File file, Map<String, String> hashes) =>
      hashes.putIfAbsent(
        file.path,
        () => sha256.convert(file.readAsBytesSync()).toString(),
      );

  static Map<Object?, Object?>? _readReceipt(File file) {
    try {
      if (!file.existsSync()) return null;
      final value = jsonDecode(file.readAsStringSync());
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> _resolve(Directory directory) async {
    final result = await Process.run(resolveDartExecutable(), [
      '--suppress-analytics',
      'pub',
      'get',
    ], workingDirectory: directory.path);
    if (result.exitCode != 0) {
      throw ProcessException(
        resolveDartExecutable(),
        const ['pub', 'get'],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
  }

  /// Compiles the entry to a temporary snapshot and discards it.
  ///
  /// Separate from [_compile] so verifying buildability can never touch the
  /// snapshot the editor has already loaded: a diagnostic that replaced the
  /// snapshot it was diagnosing would be worse than no diagnostic.
  static Future<String> _verifyBuild(Directory directory) async {
    final temporary = File(
      p.join(directory.path, 'bin', 'plugin.zuke-verify.aot'),
    );
    try {
      final result = await Process.run(resolveDartExecutable(), [
        '--suppress-analytics',
        'compile',
        'aot-snapshot',
        '--output',
        temporary.path,
        'bin/plugin.dart',
      ], workingDirectory: directory.path);
      if (result.exitCode != 0) {
        throw ProcessException(
          resolveDartExecutable(),
          const ['compile', 'aot-snapshot'],
          '${result.stdout}\n${result.stderr}'.trim(),
          result.exitCode,
        );
      }
      return temporary.existsSync() ? temporary.path : '';
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  static Future<String> _compile(Directory directory) async {
    final temporary = File(
      p.join(directory.path, 'bin', 'plugin.zuke-repair.aot'),
    );
    final result = await Process.run(resolveDartExecutable(), [
      '--suppress-analytics',
      'compile',
      'aot-snapshot',
      '--output',
      temporary.path,
      '--depfile',
      p.join(directory.path, 'bin', 'depfile.txt'),
      p.join(directory.path, 'bin', 'plugin.dart'),
    ], workingDirectory: directory.path);
    if (result.exitCode != 0) {
      if (temporary.existsSync()) temporary.deleteSync();
      throw ProcessException(
        resolveDartExecutable(),
        const [],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    final digest = _hash(temporary, {});
    final installed = _snapshotFile(directory.path);
    if (installed.existsSync() && _hash(installed, {}) == digest) {
      temporary.deleteSync();
      return digest;
    }
    temporary.renameSync(installed.path);
    return digest;
  }
}

Map<String, String> _packageRoots(File config) {
  final document = jsonDecode(config.readAsStringSync());
  if (document is! Map || document['packages'] is! List) {
    throw const FormatException('Invalid package configuration');
  }
  return {
    for (final package in document['packages'] as List)
      if (package is Map &&
          package['name'] is String &&
          package['rootUri'] is String)
        package['name'] as String: config.absolute.uri
            .resolve(package['rootUri'] as String)
            .toFilePath(),
  };
}

/// The result of compiling one cache entry's sources, reusable for any other
/// entry whose source fingerprint matches.
class _BuildVerdict {
  const _BuildVerdict(this.status, this.message);
  final String status;
  final String message;
}

/// What a single pruning walk observed about a cache entry.
final class _CacheEntryScan {
  const _CacheEntryScan({required this.hasLink, required this.bytes});

  final bool hasLink;
  final int bytes;
}

String _canonical(String path) {
  final comparable = canonicalComparablePath(path);
  return p.normalize(
    Platform.isWindows ? comparable.toLowerCase() : comparable,
  );
}

/// Dart 3.12's synthetic-package cache key for an analysis context root.
/// The path spelling must match what the analysis server sees exactly.
String pluginCacheKeyForContextRoot(String contextRoot) =>
    md5.convert(contextRoot.codeUnits).toString();

Future<List<PluginCacheFinding>> auditPluginCache(
  String root, {
  bool fix = false,
  bool checkBuild = false,
  int? maxRepairs,
  Set<String>? onlyEntries,
  Set<String>? contextRoots,
  PluginCacheProgress? onProgress,
}) async {
  try {
    return await PluginCacheDoctor.forWorkspace(root).inspect(
      fix: fix,
      checkBuild: checkBuild,
      maxRepairs: maxRepairs,
      onlyEntries: onlyEntries,
      contextRoots: contextRoots,
      onProgress: onProgress,
    );
  } on Object catch (error) {
    return [
      PluginCacheFinding(root, 'failed', 'Plugin cache audit failed: $error'),
    ];
  }
}

/// Prints plugin-cache findings that are not already current.
///
/// [sink] defaults to stderr, which is right for `zuke doctor`: the findings are
/// diagnostics about the machine. `zuke generate` passes stdout instead, because
/// the audit there is advisory and generate already reserves stderr for its own
/// failures -- writing to stderr would interleave advice with errors for anything
/// reading the two separately.
void printPluginCacheFindings(
  Iterable<PluginCacheFinding> findings, {
  void Function(String line)? sink,
}) {
  final emit = sink ?? stderr.writeln;
  // Only statuses a rebuild can actually resolve get the hint. A plugin that
  // does not compile, or an entry deliberately left untouched, would be sent
  // straight back to the command that already failed to help.
  var advisedRepair = false;
  var deferred = 0;
  for (final finding in findings.where((f) => f.status != 'current')) {
    // A workspace accumulates many entries and they share one remedy, so it is
    // stated once at the end rather than repeated on every line.
    emit(
      'ZUKE-PLUGIN-CACHE [${finding.status}]: ${finding.path}: ${finding.message}',
    );
    if (finding.status == 'deferred') {
      deferred += 1;
      continue;
    }
    if (finding.needsRepair &&
        (finding.status == 'stale' || finding.status == 'unverified')) {
      advisedRepair = true;
    }
  }
  if (advisedRepair) emit(' Run zuke doctor --fix to rebuild these entries.');
  // Counted rather than restated per entry: the reader asked for this limit, so
  // telling them to run the command again is the whole remedy, and repeating it
  // once per deferred entry buried it.
  if (deferred > 0) {
    emit(
      ' $deferred plugin cache '
      '${deferred == 1 ? 'entry was' : 'entries were'} left for a later run.',
    );
  }
}
