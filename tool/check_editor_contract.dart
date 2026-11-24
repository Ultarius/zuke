import 'dart:convert';
import 'dart:io';

/// PR guard against updating the schema golden without a contract/plugin bump.
/// The unit test separately compares that golden to all serializer keys.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Usage: check_editor_contract.dart <base-ref>');
  }
  const path = 'vendor-sdk/zuke_cli/test/goldens/index_contract.json';
  final current =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final safeRoot = Directory.current.absolute.path.replaceAll('\\', '/');
  final git = ['-c', 'safe.directory=$safeRoot'];
  final result = Process.runSync('git', [
    ...git,
    'show',
    '${args.single}:$path',
  ]);
  if (result.exitCode != 0) {
    // Bootstrap only: absence is allowed; a missing base ref is not.
    final tree = Process.runSync('git', [
      ...git,
      'ls-tree',
      args.single,
      '--',
      path,
    ]);
    if (tree.exitCode != 0 || (tree.stdout as String).trim().isNotEmpty) {
      throw StateError('Cannot read base contract: ${result.stderr}');
    }
    final oldPlugin = Process.runSync('git', [
      ...git,
      'show',
      '${args.single}:vendor-sdk/zuke_analyzer/pubspec.yaml',
    ]);
    if (oldPlugin.exitCode != 0) {
      throw StateError('Cannot read base plugin version: ${oldPlugin.stderr}');
    }
    final previousVersion = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(oldPlugin.stdout as String)?.group(1);
    if (previousVersion == null ||
        !_versionIncreased(
          previousVersion,
          current['pluginVersion'] as String,
        )) {
      throw StateError(
        'First index contract requires a zuke_analyzer version bump.',
      );
    }
    return;
  }
  final previous = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  validateContractTransition(previous, current);
}

void validateContractTransition(
  Map<String, dynamic> previous,
  Map<String, dynamic> current,
) {
  final changed =
      jsonEncode(current['serializers']) != jsonEncode(previous['serializers']);
  final version = current['contractVersion'] as int;
  final oldVersion = previous['contractVersion'] as int;
  if (version < oldVersion || (changed && version <= oldVersion)) {
    throw StateError(
      'Index serializer keys changed without increasing zukeIndexContract.',
    );
  }
  if (version != oldVersion &&
      !_versionIncreased(
        previous['pluginVersion'] as String,
        current['pluginVersion'] as String,
      )) {
    throw StateError(
      'Contract changes also require a zuke_analyzer version bump.',
    );
  }
}

bool _versionIncreased(String previous, String current) {
  List<int> parts(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) {
      throw FormatException('Expected stable semantic version: $version');
    }
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final before = parts(previous);
  final after = parts(current);
  for (var i = 0; i < 3; i++) {
    if (after[i] != before[i]) return after[i] > before[i];
  }
  return false;
}
