/// Supported application-facing build-hook entrypoint.
import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/inspection.dart';
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
    late final String mode;
    try {
      mode = normalizeBuildHookMode(rawMode);
    } on ArgumentError catch (error) {
      throw hooks.BuildError(message: 'ZUKE-HOOK-CONFIG-001: ${error.message}');
    }

    final rawWorkspaceRoot = input.userDefines['workspaceRoot'];
    if (rawWorkspaceRoot != null && rawWorkspaceRoot is! String) {
      throw hooks.BuildError(
        message:
            'ZUKE-HOOK-CONFIG-001: hooks.user_defines.'
            'zuke_dart_build_hook.workspaceRoot must be a path string.',
      );
    }
    final customRoot = input.userDefines.path('workspaceRoot');

    final errors = await _validatePackage(packageRoot);
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
  if (value is! String) {
    throw ArgumentError.value(
      value,
      'mode',
      'hooks.user_defines.zuke_dart_build_hook.mode must be "warn" or "error"',
    );
  }
  final mode = value.toLowerCase();
  if (mode == 'warn' || mode == 'error') return mode;
  throw ArgumentError.value(
    value,
    'mode',
    'hooks.user_defines.zuke_dart_build_hook.mode must be "warn" or "error"',
  );
}

Future<List<String>> _validatePackage(String packageRoot) async => [
  ...(await DartExtractor().extract(packageRoot)).errors,
];

_WorkspaceInputs _workspaceInputs(String packageRoot, {Uri? customRoot}) {
  if (customRoot != null) {
    return _checkDirectory(
      Directory(_normalizedDirectoryPath(customRoot.toString())),
    );
  }
  var directory = Directory(packageRoot).absolute;
  while (true) {
    final config = File('${directory.path}${Platform.pathSeparator}zuke.yaml');
    if (config.existsSync()) {
      return _checkDirectory(directory);
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return const _WorkspaceInputs();
    directory = parent;
  }
}

_WorkspaceInputs _checkDirectory(Directory directory) {
  directory = Directory(_normalizedDirectoryPath(directory.path));
  final config = File('${directory.path}${Platform.pathSeparator}zuke.yaml');
  final indexFile = File(
    '${directory.path}${Platform.pathSeparator}.zuke${Platform.pathSeparator}analyzer-index.json',
  );
  try {
    final index = ZukeIndex.read(indexFile);
    final freshnessIssues = index.freshnessIssues(root: directory.path);
    if (freshnessIssues.isNotEmpty) {
      return _WorkspaceInputs.error(
        'ZUKE-INDEX-STALE: '
        '${freshnessIssues.map((issue) => issue.message).join('; ')}\n'
        '  Path: ${indexFile.path}\n'
        '  Fix: ${_regenerationMessage(directory.path)}',
      );
    }
    return _WorkspaceInputs(
      dependencies: [
        config.uri,
        indexFile.uri,
        File(
          '${directory.path}${Platform.pathSeparator}'
          '${index.generatedManifestPath.replaceAll('/', Platform.pathSeparator)}',
        ).uri,
        ...index.inputs.map(
          (entry) => File(
            '${directory.path}${Platform.pathSeparator}'
            '${entry.path.replaceAll('/', Platform.pathSeparator)}',
          ).uri,
        ),
      ],
    );
  } on FormatException catch (error) {
    return _WorkspaceInputs.error(
      'ZUKE-INDEX-STALE: Analyzer index is malformed (${error.message})\n'
      '  Path: ${indexFile.path}\n'
      '  Fix: ${_regenerationMessage(directory.path)}',
    );
  } on FileSystemException {
    return _WorkspaceInputs.error(
      'ZUKE-INDEX-STALE: Analyzer index is missing or unreadable\n'
      '  Path: ${indexFile.path}\n'
      '  Fix: ${_regenerationMessage(directory.path)}',
    );
  }
}

String _regenerationMessage(String root) =>
    'Run `dart run zuke_cli:zuke generate '
    '--root "${_normalizedDirectoryPath(root)}"`.';

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
  factory _WorkspaceInputs.error(String message) =>
      _WorkspaceInputs(errors: [message]);
}
