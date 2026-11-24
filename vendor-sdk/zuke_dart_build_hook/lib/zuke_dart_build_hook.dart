/// Supported application-facing build-hook entrypoint.
library;

import 'dart:io';

import 'package:zuke_cli/tooling.dart';
import 'package:hooks/hooks.dart' as hooks;

/// Official hooks protocol entry point. The hook only declares the package
/// inputs it observes; it emits no generated repository files and cannot
/// claim workspace-level assurance.
Future<void> build(List<String> args) async {
  await hooks.build(args, (input, output) async {
    final packageRoot = _normalizedDirectoryPath(
      input.packageRoot.toFilePath(),
    );
    // Hooks filters user-defines to this package before exposing them.  The
    // pubspec nesting is therefore `hooks.user_defines
    // .zuke_dart_build_hook.mode`, but a hook reads just `mode` here.
    final rawMode = input.userDefines['mode'];
    final rawWorkspaceRoot = input.userDefines['workspaceRoot'];
    late final String mode;
    late final Directory? customRoot;
    try {
      mode = normalizeBuildHookMode(rawMode);
      customRoot = rawWorkspaceRoot == null
          ? null
          : normalizeBuildHookWorkspaceRoot(
              rawWorkspaceRoot,
              basePath: _userDefinesBasePath(input),
            );
    } on ArgumentError catch (error) {
      throw hooks.BuildError(message: 'ZUKE-HOOK-CONFIG-001: ${error.message}');
    }

    final errors = await _validatePackage(
      packageRoot,
      workspaceRoot: customRoot?.path,
    );
    final workspaceInputs = _workspaceInputs(
      packageRoot,
      customRoot: customRoot,
    );
    errors.addAll(workspaceInputs.errors);

    if (errors.isNotEmpty) {
      final msg = errors.join('\n');
      if (mode == 'warn') {
        stderr.writeln('WARNING: $msg');
      } else {
        throw hooks.BuildError(message: msg);
      }
    }
    output.dependencies.add(input.packageRoot);
    output.dependencies.addAll(workspaceInputs.dependencies);
  });
}

/// Normalizes the package-filtered `mode` user-define.
///
/// Omission intentionally defaults to strict build-time validation.
String normalizeBuildHookMode(Object? value) {
  if (value == null) return 'error';
  if (value is String) {
    final mode = value.toLowerCase();
    if (mode == 'warn' || mode == 'error') return mode;
  }
  throw ArgumentError.value(
    value,
    'mode',
    'hooks.user_defines.zuke_dart_build_hook.mode must be "warn" or "error"',
  );
}

/// Resolves the `workspaceRoot` user-define against [basePath], the pubspec
/// that declares it.
///
/// The value is a file path, so `#` and `%` are ordinary folder-name characters.
/// A value this platform cannot represent as a path throws [ArgumentError].
Directory normalizeBuildHookWorkspaceRoot(
  Object value, {
  required Uri basePath,
}) {
  if (value is String && value.trim().isNotEmpty) {
    try {
      return Directory.fromUri(basePath.resolveUri(Uri.directory(value)));
      // ignore: avoid_catching_errors
    } on ArgumentError {
      // Reported below with the setting's name.
      // ignore: avoid_catching_errors
    } on UnsupportedError {
      // Reported below with the setting's name.
    }
  }
  throw ArgumentError.value(
    value,
    'workspaceRoot',
    'hooks.user_defines.zuke_dart_build_hook.workspaceRoot must be a valid '
        'path string',
  );
}

/// The pubspec that declared the user-defines.
///
/// Read directly because `userDefines.path` parses its value as a URI, which
/// truncates a path at `#` and decodes `%`.
Uri _userDefinesBasePath(hooks.BuildInput input) {
  final userDefines = input.json['user_defines'] as Map<String, Object?>;
  final pubspec = userDefines['workspace_pubspec'] as Map<String, Object?>;
  return Uri.file(pubspec['base_path'] as String);
}

Future<List<String>> _validatePackage(
  String packageRoot, {
  String? workspaceRoot,
}) async {
  late final ResolvedPlacement placement;
  try {
    placement = resolvePlacement(
      packageRoot,
      explicitWorkspaceRoot: workspaceRoot,
    );
  } on PlacementFailure catch (error) {
    return ['${error.code}: ${error.message}'];
  }
  return (await DartExtractor().extract(
    packageRoot,
    roots: placement.package.roots,
    target: placement.target.id,
  )).errors;
}

_WorkspaceInputs _workspaceInputs(String packageRoot, {Directory? customRoot}) {
  var directory = customRoot ?? Directory(packageRoot).absolute;
  while (true) {
    final config = File.fromUri(directory.uri.resolve('zuke.yaml'));
    if (customRoot != null || config.existsSync()) {
      return _checkWorkspace(config);
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return const _WorkspaceInputs();
    directory = parent;
  }
}

_WorkspaceInputs _checkWorkspace(File config) {
  final directory = config.parent;
  final workspaceUri = directory.uri;
  final indexFile = File.fromUri(
    workspaceUri.resolve('.zuke/analyzer-index.json'),
  );
  Uri workspaceInput(String path) => workspaceUri.resolveUri(Uri.file(path));
  _WorkspaceInputs staleIndex(String message) => _WorkspaceInputs(
    errors: [
      'ZUKE-INDEX-STALE: $message\n'
          '  Path: ${indexFile.path}\n'
          '  Fix: Run `dart run zuke_cli:zuke generate --root "${directory.path}"`.',
    ],
  );

  try {
    final index = ZukeIndex.read(indexFile);
    final freshnessIssues = index.freshnessIssues(root: directory.path);
    if (freshnessIssues.isNotEmpty) {
      return staleIndex(
        freshnessIssues.map((issue) => issue.message).join('; '),
      );
    }
    return _WorkspaceInputs(
      dependencies: [
        config.uri,
        indexFile.uri,
        workspaceInput(index.generatedManifestPath),
        for (final entry in index.inputs) workspaceInput(entry.path),
      ],
    );
  } on FormatException catch (error) {
    return staleIndex('Analyzer index is malformed (${error.message})');
  } on FileSystemException {
    return staleIndex('Analyzer index is missing or unreadable');
  }
}

String _normalizedDirectoryPath(String value) {
  var path = Directory(value).absolute.path;
  final isDriveRoot = RegExp(r'^[A-Za-z]:[\\/]$').hasMatch(path);
  if (path.length > 1 && !isDriveRoot) {
    path = path.replaceFirst(RegExp(r'[\\/]+$'), '');
  }
  return path;
}

class _WorkspaceInputs {
  final List<Uri> dependencies;
  final List<String> errors;
  const _WorkspaceInputs({
    this.dependencies = const [],
    this.errors = const [],
  });
}
