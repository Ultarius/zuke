import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// A preflighted editor update. Preparing all files precedes any writes.
final class EditorFileUpdate {
  const EditorFileUpdate(this.file, this.contents);
  final File file;
  final String contents;

  void write() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }
}

/// Pub-compatible commands; only exact preset names are owned by Zuke.
///
/// Lock tasks are intentionally two: `Zuke: Refresh Profile Locks` (mutating,
/// parameterized by scope) and `Zuke: Verify Profile Locks (No Mutation)`
/// (read-only). Legacy per-alias refresh entries are pruned only when they
/// match the recognized generated shape; user-owned entries are preserved.
/// The scope picker is populated from the workspace's configured
/// `lock.profiles` (falling back to the onboarding default
/// `[pullRequest, merge, release, nightly]` when unreadable). `All profiles`
/// maps to an explicit `--all-profiles` flag: passing `"all"` to `--profile`
/// is not supported, so the task carries the flag fragment directly.
List<EditorFileUpdate> prepareVscodePreset(String root) {
  final tasks = File('$root/.vscode/tasks.json');
  final launch = File('$root/.vscode/launch.json');
  final existingLaunch = launch.existsSync()
      ? launch.readAsStringSync()
      : '{"version":"0.2.0"}';
  var taskContents = tasks.existsSync()
      ? tasks.readAsStringSync()
      : '{"version":"2.0.0"}';
  // Prune superseded refresh aliases before merging the consolidated task.
  // Only recognized generated entries are removed; anything else is kept.
  for (final label in _legacyRefreshLabels) {
    // Preserve referenced aliases: changing a fixed all-profile dependency
    // into an interactive picker would change the caller's behavior.
    if (!_referencesTask(jsonDecode(_json(taskContents)), label) &&
        !_referencesTask(jsonDecode(_json(existingLaunch)), label)) {
      taskContents = _removeGeneratedTask(taskContents, label);
    }
  }
  final profiles = _configuredLockProfiles(root);
  final scopeOptions = _lockScopeOptions(profiles);
  for (final entry in _vscodeTasks(scopeOptions)) {
    taskContents = _merge(taskContents, 'tasks', 'label', entry);
  }
  taskContents = _merge(taskContents, 'inputs', 'id', {
    'id': 'zukeLockScope',
    'type': 'pickString',
    'description':
        'Select profile scope to refresh (All profiles or one configured profile)',
    'options': scopeOptions,
    'default': '--all-profiles',
  });
  // The legacy free-text profile input is orphaned once no task references
  // it. Remove it only when it still matches the generated shape.
  if (!taskContents.contains(r'${input:zukeProfile}')) {
    taskContents = _removeGeneratedInput(taskContents);
  }
  var launchContents = existingLaunch;
  launchContents = _removeGeneratedLaunch(launchContents);
  return [
    EditorFileUpdate(tasks, taskContents),
    EditorFileUpdate(launch, launchContents),
  ];
}

bool _referencesTask(Object? value, String label) {
  if (value is List) return value.any((item) => _referencesTask(item, label));
  if (value is! Map) return false;
  for (final entry in value.entries) {
    if (const {
      'dependsOn',
      'preLaunchTask',
      'postDebugTask',
    }.contains(entry.key)) {
      if (entry.value == label ||
          (entry.value is List && (entry.value as List).contains(label))) {
        return true;
      }
    }
    if (_referencesTask(entry.value, label)) return true;
  }
  return false;
}

/// Legacy refresh aliases superseded by `Zuke: Refresh Profile Locks`.
const _legacyRefreshLabels = {
  'Zuke: Refresh All Profile Locks',
  'Zuke: Refresh Selected Profile Lock',
  'Zuke: Refresh Selected Project Locks',
};

/// Legacy launch entry superseded by `Zuke: Refresh Profile Locks`.
const _legacyLaunchNames = {
  'Zuke: Refresh All Profile Locks',
  'Zuke: Refresh Profile Locks',
};

/// Onboarding default used only when the workspace has no readable
/// `lock.profiles`. Parsing itself never invents this default.
const _fallbackLockProfiles = ['pullRequest', 'merge', 'release', 'nightly'];

/// Reads configured `lock.profiles` from `$root/zuke.yaml`.
/// Returns the onboarding fallback when the file is absent or unreadable so
/// editor scaffolding never fails closed on a missing workspace.
List<String> _configuredLockProfiles(String root) {
  try {
    final file = File('$root/zuke.yaml');
    if (!file.existsSync()) return _fallbackLockProfiles;
    final document = loadYaml(file.readAsStringSync());
    if (document is! Map) return _fallbackLockProfiles;
    final lock = document['lock'];
    if (lock is! Map) return _fallbackLockProfiles;
    final profiles = lock['profiles'];
    if (profiles is! List) return _fallbackLockProfiles;
    final names = [
      for (final profile in profiles)
        if (profile is String && profile.trim().isNotEmpty) profile,
    ];
    return names.isEmpty ? _fallbackLockProfiles : names;
  } on Object {
    return _fallbackLockProfiles;
  }
}

/// Scope flag fragments for the refresh picker. `All profiles` is an
/// explicit `--all-profiles` flag, never `--profile all`.
List<String> _lockScopeOptions(List<String> profiles) => [
  '--all-profiles',
  for (final profile in profiles) '--profile=$profile',
];

Map<String, Object?> _task({
  required String label,
  required List<String> arguments,
  bool presentation = true,
}) => {
  'label': label,
  'type': 'process',
  'command': 'dart',
  'args': arguments,
  'options': {'cwd': r'${workspaceFolder}'},
  if (presentation)
    'presentation': {'group': 'zuke', 'panel': 'dedicated', 'reveal': 'always'},
  'problemMatcher': <String>[],
};

const _zukeRoot = r'${workspaceFolder}';

/// Consolidated lock tasks plus the unchanged gate/generate/doctor entries.
/// The refresh entry carries one scope flag fragment from the
/// `zukeLockScope` picker (`--all-profiles` or `--profile=<name>`).
List<Map<String, Object?>> _vscodeTasks(List<String> scopeOptions) => [
  _task(
    label: 'Zuke: Refresh Profile Locks',
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'lock',
      '--refresh',
      '--root',
      _zukeRoot,
      '--runner-mode',
      'auto',
      r'${input:zukeLockScope}',
    ],
  ),
  _task(
    label: 'Zuke: Verify Profile Locks (No Mutation)',
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'lock',
      '--all-profiles',
      '--check',
      '--root',
      _zukeRoot,
    ],
  ),
  _task(
    label: 'Zuke: Validate Pull Request',
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'gate',
      '--profile',
      'pullRequest',
      '--root',
      _zukeRoot,
      '--format',
      'json',
    ],
  ),
  _task(
    label: 'Zuke: Generate Contracts',
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'generate',
      '--root',
      _zukeRoot,
    ],
  ),
  _task(
    label: 'Zuke: Check Version Alignment',
    presentation: false,
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'doctor',
      '--root',
      _zukeRoot,
      '--check-alignment',
    ],
  ),
  _task(
    label: 'Zuke: Doctor Check',
    presentation: false,
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'doctor',
      '--root',
      _zukeRoot,
    ],
  ),
  _task(
    label: 'Zuke: Doctor Test Host Compatibility',
    presentation: false,
    arguments: [
      '--suppress-analytics',
      'run',
      'zuke_cli:zuke',
      'doctor',
      'test-host',
      '--root',
      _zukeRoot,
      '--format',
      'json',
    ],
  ),
];

/// Removes a legacy generated task entry when it matches the recognized
/// shape (a `zuke_cli:zuke lock --refresh` process task). User-owned entries
/// with the same label but a different command are preserved. Throws on
/// ambiguous duplicates like [_merge] does.
String _removeGeneratedTask(String source, String label) {
  final masked = _json(source);
  final decoded = jsonDecode(masked);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Editor configuration must be a JSON object');
  }
  final tasks = decoded['tasks'];
  if (tasks == null) return source;
  if (tasks is! List) {
    throw const FormatException('Editor tasks must be an array');
  }
  final matches = <int>[];
  for (var index = 0; index < tasks.length; index++) {
    final task = tasks[index];
    if (task is Map && task['label'] == label) matches.add(index);
  }
  if (matches.length > 1) {
    throw FormatException('Duplicate Zuke editor entry: $label');
  }
  if (matches.isEmpty) return source;
  final task = tasks[matches.single] as Map;
  if (!_isGeneratedRefreshTask(task)) return source;
  return _removeArrayEntry(source, 'tasks', 'label', label);
}

/// Removes the legacy free-text profile input when it still matches the
/// generated shape. Callers must ensure no task references it anymore.
String _removeGeneratedInput(String source) {
  final masked = _json(source);
  final decoded = jsonDecode(masked);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Editor configuration must be a JSON object');
  }
  final inputs = decoded['inputs'];
  if (inputs == null) return source;
  if (inputs is! List) {
    throw const FormatException('Editor inputs must be an array');
  }
  var found = false;
  for (final input in inputs) {
    if (input is! Map || input['id'] != 'zukeProfile') continue;
    found = true;
    if (input['type'] != 'promptString') return source;
  }
  if (!found) return source;
  return _removeArrayEntry(source, 'inputs', 'id', 'zukeProfile');
}

/// Removes a legacy generated launch entry by name when it matches the
/// recognized refresh shape.
String _removeGeneratedLaunch(String source) {
  for (final name in _legacyLaunchNames) {
    final masked = _json(source);
    final decoded = jsonDecode(masked);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Editor configuration must be a JSON object');
    }
    final configurations = decoded['configurations'];
    if (configurations == null) continue;
    if (configurations is! List) {
      throw const FormatException('Editor configurations must be an array');
    }
    var generated = false;
    var count = 0;
    for (final entry in configurations) {
      if (entry is Map && entry['name'] == name) {
        count++;
        if (_isGeneratedRefreshLaunch(entry)) generated = true;
      }
    }
    if (count > 1) {
      throw FormatException('Duplicate Zuke editor entry: $name');
    }
    if (generated) {
      source = _removeArrayEntry(source, 'configurations', 'name', name);
    }
  }
  return source;
}

bool _isGeneratedRefreshTask(Map task) {
  if (task['type'] != 'process' || task['command'] != 'dart') return false;
  final args = task['args'];
  if (args is! List) return false;
  final commandIndex = args.indexOf('zuke_cli:zuke');
  return commandIndex > 0 &&
      args[commandIndex - 1] == 'run' &&
      commandIndex + 1 < args.length &&
      args[commandIndex + 1] == 'lock' &&
      args.contains('--refresh');
}

bool _isGeneratedRefreshLaunch(Map entry) {
  final command = entry['command'];
  if (entry['type'] != 'node-terminal' || command is! String) return false;
  return RegExp(
    r'^dart (?:--suppress-analytics )?run zuke_cli:zuke lock --refresh(?: |$)',
  ).hasMatch(command);
}

/// Removes one array entry by identity key, preserving comments and the
/// surrounding formatting. Only the matched entry and one adjacent comma
/// are removed.
String _removeArrayEntry(
  String source,
  String arrayKey,
  String identityKey,
  String identity,
) {
  final masked = _json(source);
  final decoded = jsonDecode(masked);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Editor configuration must be a JSON object');
  }
  final array = decoded[arrayKey];
  if (array is! List) return source;
  // Locate spans with the same scanner [_merge] uses.
  final rootStart = _skip(masked, 0);
  final rootEnd = _end(masked, rootStart) - 1;
  var cursor = rootStart + 1;
  _Span? arraySpan;
  while ((cursor = _skip(masked, cursor)) < rootEnd) {
    if (masked[cursor] == ',') {
      cursor++;
      continue;
    }
    final keyEnd = _end(masked, cursor);
    final key = jsonDecode(masked.substring(cursor, keyEnd));
    final valueStart = _skip(masked, _skip(masked, keyEnd) + 1);
    var valueEnd = _end(masked, valueStart);
    if (!['"', '[', '{'].contains(masked[valueStart])) {
      while (valueEnd < rootEnd && masked[valueEnd] != ',') {
        valueEnd++;
      }
    }
    if (key == arrayKey) arraySpan = _Span(valueStart, valueEnd);
    cursor = valueEnd;
  }
  if (arraySpan == null) return source;
  final spans = <_Span>[];
  cursor = arraySpan.start + 1;
  while ((cursor = _skip(masked, cursor)) < arraySpan.end - 1) {
    if (masked[cursor] == ',') {
      cursor++;
      continue;
    }
    final end = _end(masked, cursor);
    final value = jsonDecode(masked.substring(cursor, end));
    if (value is Map && value[identityKey] == identity) {
      spans.add(_Span(cursor, end));
    }
    cursor = end;
  }
  if (spans.isEmpty) return source;
  final span = spans.single;
  // Extend over one adjacent comma to keep the array valid.
  var start = span.start;
  var end = span.end;
  var before = start - 1;
  while (before >= arraySpan.start && RegExp(r'\s').hasMatch(masked[before])) {
    before--;
  }
  if (before >= arraySpan.start && masked[before] == ',') {
    start = before;
  } else {
    var after = end;
    while (after < arraySpan.end && RegExp(r'\s').hasMatch(masked[after])) {
      after++;
    }
    if (after < arraySpan.end && masked[after] == ',') end = after + 1;
  }
  return source.replaceRange(start, end, '');
}

final class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}

// Mask JSONC comments and trailing commas without changing offsets. String
// tokens win over comment/comma patterns, preserving URLs and quoted syntax.
String _json(String source) {
  final tokens = RegExp(r'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/');
  final masked = source.replaceAllMapped(tokens, (match) {
    final token = match[0]!;
    return token.startsWith('"')
        ? token
        : token.replaceAll(RegExp(r'[^\r\n]'), ' ');
  });
  return masked.replaceAllMapped(
    RegExp(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])'),
    (match) => match[0] == ',' ? ' ' : match[0]!,
  );
}

int _skip(String source, int offset) {
  while (offset < source.length && RegExp(r'\s').hasMatch(source[offset])) {
    offset++;
  }
  return offset;
}

int _end(String source, int start) {
  var depth = 0;
  var quoted = false;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (char == r'\') {
        i++;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == '[' || char == '{') {
      depth++;
    } else if (char == ']' || char == '}') {
      if (--depth == 0) return i + 1;
    }
    if (!quoted && depth == 0) return i + 1;
  }
  throw const FormatException('Unterminated editor JSON value');
}

String _merge(
  String source,
  String arrayKey,
  String identityKey,
  Map<String, Object?> entry,
) {
  final masked = _json(source);
  final decoded = jsonDecode(masked);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Editor configuration must be a JSON object');
  }
  final encoded = const JsonEncoder.withIndent('  ').convert(entry);
  final rootStart = _skip(masked, 0);
  final rootEnd = _end(masked, rootStart) - 1;
  var cursor = rootStart + 1;
  _Span? array;
  while ((cursor = _skip(masked, cursor)) < rootEnd) {
    if (masked[cursor] == ',') {
      cursor++;
      continue;
    }
    final keyEnd = _end(masked, cursor);
    final key = jsonDecode(masked.substring(cursor, keyEnd));
    final valueStart = _skip(masked, _skip(masked, keyEnd) + 1);
    // Decode the value through the next root member rather than relying on
    // scalar token lengths; nested containers and strings have explicit ends.
    var valueEnd = _end(masked, valueStart);
    if (!['"', '[', '{'].contains(masked[valueStart])) {
      while (valueEnd < rootEnd && masked[valueEnd] != ',') {
        valueEnd++;
      }
    }
    if (key == arrayKey) {
      if (array != null) {
        throw FormatException('Duplicate editor property: $arrayKey');
      }
      array = _Span(valueStart, valueEnd);
    }
    cursor = valueEnd;
  }
  if (array == null) {
    final before = _json(source.substring(0, rootEnd)).trimRight();
    final hasTrailingComma = source
        .substring(0, rootEnd)
        .trimRight()
        .endsWith(',');
    final comma = decoded.isEmpty || hasTrailingComma || before.endsWith(',')
        ? ''
        : ',';
    return source.replaceRange(
      rootEnd,
      rootEnd,
      '$comma\n  "$arrayKey": [$encoded]\n',
    );
  }
  if (decoded[arrayKey] is! List) {
    throw FormatException('Editor $arrayKey must be an array');
  }
  final matches = <_Span>[];
  cursor = array.start + 1;
  while ((cursor = _skip(masked, cursor)) < array.end - 1) {
    if (masked[cursor] == ',') {
      cursor++;
      continue;
    }
    final end = _end(masked, cursor);
    final value = jsonDecode(masked.substring(cursor, end));
    if (value is! Map<String, Object?>) {
      throw FormatException('Editor $arrayKey entries must be objects');
    }
    if (value[identityKey] == entry[identityKey]) {
      matches.add(_Span(cursor, end));
    }
    cursor = end;
  }
  if (matches.length > 1) {
    throw FormatException('Duplicate Zuke editor entry: ${entry[identityKey]}');
  }
  if (matches.isNotEmpty) {
    return source.replaceRange(
      matches.single.start,
      matches.single.end,
      encoded,
    );
  }
  // Insert at the beginning, preserving existing trailing commas and comments.
  final comma = (decoded[arrayKey] as List).isEmpty ? '' : ',';
  return source.replaceRange(
    array.start + 1,
    array.start + 1,
    '\n$encoded$comma\n',
  );
}
