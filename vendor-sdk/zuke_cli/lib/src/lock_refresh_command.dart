import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:zuke_core/zuke_core.dart' show sha256DigestHex;

import 'configuration_preflight.dart';
import 'cli_parser.dart';
import 'extraction_service.dart';
import 'generate_command.dart';
import 'lock_command.dart';
import 'lock_refresh_roots.dart';
import 'path_safety.dart';
import 'validate_command.dart';

/// Runs the complete lock refresh pipeline in one process.
///
/// Keeping orchestration here means consumers do not need a copy of the
/// framework's generate/test/validate/lock loop.  LockCommand still owns
/// the transactional write and final stale-lock checks; this method only
/// supplies the fresh inputs it requires.
Future<int> runLockRefresh(
  ArgResults cmd, {
  required Future<int> Function(ArgResults cmd) testRunner,
}) async {
  final additionalRoots = cmd['roots'] as List<String>;
  final roots = lockRefreshRoots([
    if (cmd['root'] case final String root) root,
    ...additionalRoots,
    if (cmd['root'] == null && additionalRoots.isEmpty) Directory.current.path,
  ]);
  // Resolve every root and profile before any generation or evidence writes.
  for (final root in roots) {
    final configured = requireCurrentWorkspace(root.path).config.lockProfiles;
    final requested = [
      if (cmd['profile'] case final String profile) profile,
      ...cmd['profiles'] as List<String>,
    ];
    if (requested.any((profile) => !configured.contains(profile))) {
      throw FormatException(
        'Requested profile is not configured at ${root.path}',
      );
    }
  }
  final diffOutput = cmd['diff-output'] as String?;
  if (diffOutput != null && diffOutput.isNotEmpty && roots.length != 1) {
    throw const FormatException(
      'lock --diff-output requires exactly one refreshed workspace root',
    );
  }
  if (diffOutput != null && diffOutput.isNotEmpty) {
    final outputPath = canonicalComparablePath(diffOutput);
    final lockDirectory = canonicalComparablePath(
      p.join(
        roots.single.path,
        requireCurrentWorkspace(roots.single.path).config.lockDirectory ??
            'assurance/locks',
      ),
    );
    if (pathEqualsOrWithin(lockDirectory, outputPath) ||
        FileSystemEntity.typeSync(outputPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const FormatException(
        '--diff-output must be a new file outside the lock directory',
      );
    }
  }
  final before = roots.length == 1
      ? _lockSnapshot(roots.single)
      : <String, String?>{};
  var exitCode = 0;
  try {
    for (final root in roots) {
      final result = await _runLockRefreshRoot(
        cmd,
        root.path,
        testRunner: testRunner,
      );
      if (result != 0) {
        exitCode = result;
        break;
      }
    }
    return exitCode;
  } finally {
    if (diffOutput != null && diffOutput.isNotEmpty) {
      _writeLockDiff(roots.single, before, diffOutput);
    }
  }
}

Map<String, String?> _lockSnapshot(Directory root) {
  final workspace = requireCurrentWorkspace(root.path);
  final directory = workspace.config.lockDirectory ?? 'assurance/locks';
  return {
    for (final profile in workspace.config.lockProfiles)
      profile:
          File(
            '${root.path}${Platform.pathSeparator}$directory${Platform.pathSeparator}$profile.lock.json',
          ).existsSync()
          ? File(
              '${root.path}${Platform.pathSeparator}$directory${Platform.pathSeparator}$profile.lock.json',
            ).readAsStringSync()
          : null,
  };
}

void _writeLockDiff(
  Directory root,
  Map<String, String?> before,
  String output,
) {
  final after = _lockSnapshot(root);
  final changed = <Map<String, Object?>>[];
  for (final profile in {...before.keys, ...after.keys}.toList()..sort()) {
    final previous = before[profile];
    final current = after[profile];
    if (previous == current) continue;
    changed.add({
      'profile': profile,
      'beforeSha256': previous == null
          ? null
          : sha256DigestHex(utf8.encode(previous)),
      'afterSha256': current == null
          ? null
          : sha256DigestHex(utf8.encode(current)),
      'beforePresent': previous != null,
      'afterPresent': current != null,
    });
  }
  final file = File(output);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'kind': 'zuke.lock-diff', 'root': root.path, 'changed': changed})}\n',
  );
}

Future<int> _runLockRefreshRoot(
  ArgResults cmd,
  String root, {
  required Future<int> Function(ArgResults cmd) testRunner,
}) async {
  if (cmd['check'] as bool? ?? false) {
    throw const FormatException(
      'lock --refresh and lock --check are mutually exclusive',
    );
  }
  final output = cmd['output'] as String?;
  if (output != null && output.isNotEmpty) {
    throw const FormatException(
      'lock --refresh cannot be combined with --output',
    );
  }
  final requestedProfile = cmd['profile'] as String?;
  final requestedProfiles = cmd['profiles'] as List<String>;
  final allProfiles = cmd['all-profiles'] as bool? ?? false;
  if ((allProfiles &&
          (requestedProfile != null || requestedProfiles.isNotEmpty)) ||
      (requestedProfile != null && requestedProfiles.isNotEmpty)) {
    throw const FormatException(
      'lock --all-profiles and --profile are mutually exclusive',
    );
  }
  final workspace = requireCurrentWorkspace(root);
  final configuredProfiles = workspace.config.lockProfiles;
  final profiles = requestedProfiles.isNotEmpty
      ? requestedProfiles.toSet().toList()
      : requestedProfile == null
      ? (configuredProfiles.isEmpty
            ? const ['pullRequest', 'merge', 'release', 'nightly']
            : configuredProfiles)
      : [requestedProfile];

  final generated = await GenerateCommand(
    buildGenerateArgs(root: root),
  ).execute();
  if (generated != 0) return generated;
  final generationCheck = await GenerateCommand(
    buildGenerateArgs(root: root, check: true, quiet: true),
  ).execute();
  if (generationCheck != 0) return generationCheck;

  final retest = boolFlag(cmd, 'retest');
  // A profile with no published evidence is stale by definition, so it needs
  // no probe: that saves one full discovery/extraction/validation per profile
  // on the first refresh of a workspace.
  final publishedProfiles = {
    for (final record in ExtractionService().publishedEvidence(workspace))
      record.profile,
  };
  for (final profile in profiles) {
    // Evidence that already satisfies this profile does not need to be
    // produced again. Without this check a prose-only edit re-ran the full
    // suite once per configured profile.
    //
    // The probe is the production validator rather than a second, hand-rolled
    // digest comparison: it has to agree with the validation that runs after
    // the tests, and duplicating that logic is exactly how the two drift apart.
    if (!retest && publishedProfiles.contains(profile)) {
      // A genuinely silent probe: `--quiet` still reports findings, and the
      // pipeline validates again after the tests, so echoing them here would
      // print every finding twice.
      final current = await ValidateCommand(
        buildValidateArgs(
          root: root,
          profile: profile,
          requireEvidence: true,
          silent: true,
        ),
      ).execute();
      if (current == 0) {
        stdout.writeln(
          'Evidence for profile $profile is current; skipping test execution. '
          'Use --retest to execute it again.',
        );
        continue;
      }
    }
    stdout.writeln('Refreshing Zuke evidence for profile $profile...');
    final tested = await testRunner(
      buildTestArgs(
        root: root,
        profile: profile,
        runnerMode: cmd['runner-mode'] as String?,
      ),
    );
    if (tested != 0) return tested;
    final validated = await ValidateCommand(
      buildValidateArgs(root: root, profile: profile),
    ).execute();
    if (validated != 0) return validated;
  }

  return LockCommand(
    buildLockArgs(
      root: root,
      profile: requestedProfile,
      profiles: requestedProfiles.isNotEmpty ? profiles : const [],
      allProfiles: requestedProfiles.isEmpty && requestedProfile == null,
      update: true,
    ),
  ).execute();
}
