import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'init_preset.dart';
import 'path_safety.dart';
import 'vscode_preset.dart';

int runInit(ArgResults cmd) {
  final root = cmd['root'] as String? ?? Directory.current.path;
  final enableHooks = cmd['enable-dart-build-hooks'] as bool? ?? false;
  final dryRun = cmd['dry-run'] as bool? ?? false;
  final packagePath = cmd['package'] as String?;
  if (enableHooks && (packagePath == null || packagePath.isEmpty)) {
    stderr.writeln(
      '--enable-dart-build-hooks requires --package <workspace-relative-path>',
    );
    return 2;
  }
  final file = File('$root/zuke.yaml');
  final editorRequested = cmd['editor'] == 'vscode';
  final existingConfig = file.existsSync();
  if (existingConfig && !editorRequested) {
    stderr.writeln('zuke.yaml already exists');
    return 1;
  }
  final editorUpdates = editorRequested
      ? prepareVscodePreset(root)
      : const <EditorFileUpdate>[];
  if (enableHooks) {
    final adoption = _adoptBuildHook(root, packagePath!, dryRun: true);
    if (adoption != 0) return adoption;
  }
  final preset = switch (cmd['preset']) {
    'flutter' => InitPreset.flutter,
    'dart-frog' => InitPreset.dartFrog,
    'dart' => InitPreset.dart,
    _ => InitPreset.detect(Directory(root)),
  };
  final config = preset.configuration(Directory(root));
  if (dryRun) {
    if (!existingConfig) {
      print('Would create ${file.path}');
      print(config);
    }
    for (final update in editorUpdates) {
      print('Would update ${update.file.path}');
      print(update.contents);
    }
    return 0;
  }
  if (!existingConfig) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(config);
    Directory('$root/specs/features').createSync(recursive: true);
    print('Created ${file.path}');
  }
  for (final update in editorUpdates) {
    update.write();
    print('Updated ${update.file.path}');
  }
  if (enableHooks) {
    return _adoptBuildHook(root, packagePath!);
  }
  return 0;
}

int runAdoptPackage(ArgResults cmd) {
  if (!(cmd['enable-build-hook'] as bool? ?? false)) {
    stderr.writeln('Only --enable-build-hook is currently supported.');
    return 2;
  }
  if (cmd.rest.length != 1) {
    stderr.writeln(
      'Usage: zuke adopt package <workspace-relative-path> --enable-build-hook',
    );
    return 2;
  }
  final root = cmd['root'] as String? ?? Directory.current.path;
  return _adoptBuildHook(
    root,
    cmd.rest.single,
    dryRun: cmd['dry-run'] as bool? ?? false,
  );
}

int _adoptBuildHook(
  String rootPath,
  String relativePackagePath, {
  bool dryRun = false,
}) {
  if (relativePackagePath.isEmpty ||
      File(relativePackagePath).isAbsolute ||
      relativePackagePath.replaceAll('\\', '/').split('/').contains('..')) {
    stderr.writeln('Package path must be workspace-relative and confined.');
    return 2;
  }
  final root = Directory(rootPath).absolute;
  final package = Directory(
    root.uri
        .resolve('${relativePackagePath.replaceAll('\\', '/')}/')
        .toFilePath(),
  ).absolute;
  if (!pathEqualsOrWithin(root.path, package.path)) {
    stderr.writeln('Package path escapes the workspace.');
    return 2;
  }
  final pubspec = File('${package.path}${Platform.pathSeparator}pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('No pubspec.yaml found at ${package.path}');
    return 2;
  }

  final hook = File(
    '${package.path}${Platform.pathSeparator}hook${Platform.pathSeparator}build.dart',
  );
  const shim =
      '''import 'package:zuke_dart_build_hook/zuke_dart_build_hook.dart'
    as zuke;

Future<void> main(List<String> arguments) => zuke.build(arguments);
''';
  if (hook.existsSync() && hook.readAsStringSync() != shim) {
    stderr.writeln('Refusing to replace existing hook at ${hook.path}');
    return 1;
  }

  var pubspecText = pubspec.readAsStringSync();
  try {
    final parsed = loadYaml(pubspecText);
    if (parsed is! YamlMap) {
      stderr.writeln('pubspec.yaml must contain a YAML mapping.');
      return 1;
    }
    final editor = YamlEditor(pubspecText);
    final dependencies = parsed['dependencies'];
    if (dependencies != null && dependencies is! YamlMap) {
      stderr.writeln(
        'Refusing to modify non-mapping dependencies: in ${pubspec.path}',
      );
      return 1;
    }
    if (dependencies is! YamlMap ||
        dependencies['zuke_dart_build_hook'] == null) {
      final hookPackage = Directory(
        '${root.path}${Platform.pathSeparator}vendor-sdk${Platform.pathSeparator}zuke_dart_build_hook',
      );
      if (!hookPackage.existsSync()) {
        stderr.writeln(
          'Zuke build-hook package is missing from this workspace.',
        );
        return 1;
      }
      final dependency = {
        'path': _relativePath(package.path, hookPackage.path),
      };
      if (dependencies == null) {
        editor.update(['dependencies'], {'zuke_dart_build_hook': dependency});
      } else {
        editor.update(['dependencies', 'zuke_dart_build_hook'], dependency);
      }
    }
    final hooks = parsed['hooks'];
    if (hooks != null && hooks is! YamlMap) {
      stderr.writeln(
        'Refusing to modify non-mapping hooks: in ${pubspec.path}',
      );
      return 1;
    }
    if (_isFlowMap(hooks)) {
      stderr.writeln('Refusing to modify flow-style hooks: in ${pubspec.path}');
      return 1;
    }
    final userDefines = hooks is YamlMap ? hooks['user_defines'] : null;
    if (userDefines != null && userDefines is! YamlMap) {
      stderr.writeln(
        'Refusing to modify non-mapping hooks.user_defines: in ${pubspec.path}',
      );
      return 1;
    }
    if (_isFlowMap(userDefines)) {
      stderr.writeln(
        'Refusing to modify flow-style hooks.user_defines: in ${pubspec.path}',
      );
      return 1;
    }
    final hookDefines = userDefines is YamlMap
        ? userDefines['zuke_dart_build_hook']
        : null;
    if (hookDefines != null && hookDefines is! YamlMap) {
      stderr.writeln(
        'Refusing to modify non-mapping hooks.user_defines.zuke_dart_build_hook in ${pubspec.path}',
      );
      return 1;
    }
    if (_isFlowMap(hookDefines)) {
      stderr.writeln(
        'Refusing to modify flow-style Zuke hook user-defines in ${pubspec.path}',
      );
      return 1;
    }

    if (hookDefines == null) {
      if (hooks == null) {
        editor.update(
          ['hooks'],
          {
            'user_defines': {
              'zuke_dart_build_hook': {'mode': 'warn'},
            },
          },
        );
      } else if (userDefines == null) {
        editor.update(
          ['hooks', 'user_defines'],
          {
            'zuke_dart_build_hook': {'mode': 'warn'},
          },
        );
      } else {
        editor.update(
          ['hooks', 'user_defines', 'zuke_dart_build_hook'],
          {'mode': 'warn'},
        );
      }
    } else if (hookDefines['mode'] == null) {
      editor.update([
        'hooks',
        'user_defines',
        'zuke_dart_build_hook',
        'mode',
      ], 'warn');
    }
    pubspecText = editor.toString();
  } on YamlException catch (error) {
    stderr.writeln('Unable to parse ${pubspec.path}: $error');
    return 1;
  }

  if (dryRun) {
    if (!hook.existsSync()) print('Would create ${hook.path}');
    if (pubspecText != pubspec.readAsStringSync()) {
      print('Would update ${pubspec.path}');
    }
    return 0;
  }
  hook.parent.createSync(recursive: true);
  if (!hook.existsSync()) hook.writeAsStringSync(shim);
  pubspec.writeAsStringSync(pubspecText);
  print(
    'Enabled Zuke build hook for ${relativePackagePath.replaceAll('\\', '/')}',
  );
  return 0;
}

bool _isFlowMap(Object? value) =>
    value is YamlMap && value.span.text.trimLeft().startsWith('{');

String _relativePath(String fromPath, String toPath) {
  final from = Directory(
    fromPath,
  ).absolute.path.replaceAll('\\', '/').split('/');
  final to = Directory(toPath).absolute.path.replaceAll('\\', '/').split('/');
  var shared = 0;
  while (shared < from.length &&
      shared < to.length &&
      from[shared].toLowerCase() == to[shared].toLowerCase()) {
    shared++;
  }
  return [
    ...List.filled(from.length - shared, '..'),
    ...to.skip(shared),
  ].join('/');
}
