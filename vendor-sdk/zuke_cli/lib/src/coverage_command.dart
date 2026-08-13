import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'configuration_preflight.dart';

/// Parses and evaluates LCOV as an independent quality gate.
///
/// Coverage is intentionally not converted into Zuke evidence. It remains a
/// product policy gate with its own baseline and changed-line thresholds.
final class CoverageCommand {
  final ArgResults args;
  bool _reported = false;

  CoverageCommand(this.args);

  Future<int> execute() async {
    try {
      return await _execute();
    } on FormatException catch (error) {
      return _fail(error.message.toString());
    } on Object catch (error) {
      return _fail('Coverage evaluation failed: $error');
    }
  }

  Future<int> _execute() async {
    final root = Directory(args['root'] as String? ?? Directory.current.path);
    final config = requireCurrentWorkspace(root.path).config.coverageConfig;
    final input =
        args['input'] as String? ??
        config['input']?.toString() ??
        'coverage/lcov.info';
    final inputFile = File(_resolve(root.path, input));
    if (!inputFile.existsSync()) {
      return _fail('Coverage input does not exist: ${inputFile.path}');
    }
    final report = parseLcov(inputFile.readAsStringSync());
    final changed = await _changedLines(
      root.path,
      args['changed-since'] as String? ?? config['changedSince']?.toString(),
      _includedRoots(config),
    );
    final minimum = _number(
      args['minimum'] as String? ?? config['minimumTotal']?.toString(),
      fallback: 100,
    );
    final changedMinimum = _number(
      args['changed-line-minimum'] as String? ??
          config['changedLineMinimum']?.toString(),
      fallback: 100,
    );
    final baselinePath =
        args['baseline'] as String? ?? config['baseline']?.toString();
    final baseline = baselinePath == null || baselinePath.isEmpty
        ? null
        : _readBaseline(root.path, baselinePath);
    final exclusions = _configuredExclusions(config);
    _validateExclusions(
      report,
      root: root.path,
      includedRoots: _includedRoots(config),
      exclusions: exclusions,
    );
    final scopedReport = report.scoped(
      root: root.path,
      includedRoots: _includedRoots(config),
      exclusions: exclusions,
    );
    if (scopedReport.files.isEmpty) {
      return _fail(
        'LCOV contains no files under the configured production roots: '
        '${_includedRoots(config).join(', ')}',
      );
    }
    final payload = scopedReport.toJson(
      changedLines: changed,
      layers: _configuredLayers(config),
      includedRoots: _includedRoots(config),
    );
    final changedPercent = payload['changedLines'] is Map
        ? (payload['changedLines'] as Map)['percent'] as num
        : 100;
    String? failure;
    if (scopedReport.percent + 0.0001 < minimum) {
      failure = 'Coverage is below ${minimum.toStringAsFixed(2)}%.';
    } else if (baseline != null &&
        scopedReport.percent + 0.0001 <
            (baseline['percent'] as num).toDouble()) {
      failure =
          'Coverage regressed from '
          '${(baseline['percent'] as num).toStringAsFixed(2)}% to '
          '${scopedReport.percent.toStringAsFixed(2)}%.';
    } else if (changed.isNotEmpty && changedPercent + 0.0001 < changedMinimum) {
      failure =
          'Changed production lines are below '
          '${changedMinimum.toStringAsFixed(2)}% coverage.';
    }
    final document = <String, Object?>{
      'kind': 'zuke.coverage',
      ...payload,
      'policy': {
        'minimumTotal': minimum,
        'changedLineMinimum': changedMinimum,
        'exclusions': [for (final exclusion in exclusions) exclusion.toJson()],
        if (baseline != null) 'baseline': baseline,
      },
      'status': failure == null ? 'passed' : 'failed',
      'eligible': failure == null,
      if (failure != null)
        'diagnostics': [
          {
            'code': 'ZK-COVERAGE-FAILED',
            'stage': 'coverage',
            'severity': 'error',
            'owner': 'project',
            'message': failure,
            'remediation':
                'Fix the coverage policy or tests and rerun coverage.',
          },
        ],
    };
    final encoded = jsonEncode(document);
    final output = args['output'] as String?;
    if (output != null && output.isNotEmpty) {
      final file = File(_resolve(root.path, output));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$encoded\n');
    }
    if ((args['format'] as String? ?? 'text') == 'json') {
      stdout.writeln(encoded);
    } else {
      stdout.writeln(
        'Line coverage: ${scopedReport.percent.toStringAsFixed(2)}% '
        '(${scopedReport.covered}/${scopedReport.total})',
      );
    }
    _reported = true;
    if (failure != null) {
      if ((args['format'] as String? ?? 'text') != 'json') {
        stderr.writeln(failure);
      }
      return 1;
    }
    return 0;
  }

  int _fail(String message) {
    final json = args['format'] as String? ?? 'text';
    if (!_reported && json == 'json') {
      final payload = jsonEncode({
        'kind': 'zuke.coverage',
        'status': 'failed',
        'eligible': false,
        'diagnostics': [
          {
            'code': 'ZK-COVERAGE-FAILED',
            'stage': 'coverage',
            'severity': 'error',
            'owner': 'project',
            'message': message,
            'remediation':
                'Fix the coverage input or policy and rerun coverage.',
          },
        ],
      });
      final output = args['output'] as String?;
      if (output != null && output.isNotEmpty) {
        final root = args['root'] as String? ?? Directory.current.path;
        final file = File(_resolve(root, output));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('$payload\n');
      }
      stdout.writeln(payload);
    } else {
      stderr.writeln(message);
    }
    return 1;
  }
}

final class LcovReport {
  final List<LcovFile> files;

  const LcovReport(this.files);

  int get total => files.fold(0, (sum, file) => sum + file.total);
  int get covered => files.fold(0, (sum, file) => sum + file.covered);
  double get percent => total == 0 ? 100 : covered * 100 / total;

  /// Restricts LCOV to configured production roots and removes only governed
  /// lines. The original parsed report remains lossless for diagnostics.
  LcovReport scoped({
    required String root,
    required List<String> includedRoots,
    List<CoverageExclusion> exclusions = const [],
  }) {
    final scopedFiles = <LcovFile>[];
    for (final file in files) {
      final path = _relativeCoveragePath(root, file.path);
      if (includedRoots.isNotEmpty &&
          !includedRoots.any((included) => _underRoot(path, included))) {
        continue;
      }
      final copy = LcovFile(path);
      final excluded = <int>{
        for (final exclusion in exclusions)
          if (_normalize(exclusion.path) == path) ...exclusion.lines,
      };
      for (final entry in file.lines.entries) {
        if (!excluded.contains(entry.key)) {
          copy.lines[entry.key] = entry.value;
        }
      }
      scopedFiles.add(copy);
    }
    return LcovReport(scopedFiles);
  }

  Map<String, Object?> toJson({
    Map<String, Set<int>> changedLines = const {},
    Map<String, List<String>> layers = const {},
    List<String> includedRoots = const [],
  }) {
    var changedTotal = 0;
    var changedCovered = 0;
    for (final file in files) {
      final lines = changedLines[_normalize(file.path)];
      if (lines == null) continue;
      for (final line in lines) {
        final hits = file.lines[line];
        if (hits == null) continue;
        changedTotal++;
        if (hits > 0) changedCovered++;
      }
    }
    return {
      'covered': covered,
      'total': total,
      'percent': _round(percent),
      'changedLines': {
        'covered': changedCovered,
        'total': changedTotal,
        'percent': _round(
          changedTotal == 0 ? 100 : changedCovered * 100 / changedTotal,
        ),
      },
      'layers': _layers(layers),
      'includedRoots': includedRoots,
    };
  }

  Map<String, Object?> _layers(Map<String, List<String>> configuredLayers) {
    final layers = <String, List<LcovFile>>{};
    for (final file in files) {
      String? configuredLayer;
      for (final entry in configuredLayers.entries) {
        if (entry.value.any((pattern) => _matches(pattern, file.path))) {
          configuredLayer = entry.key;
          break;
        }
      }
      layers
          .putIfAbsent(configuredLayer ?? _riskLayer(file.path), () => [])
          .add(file);
    }
    return {
      for (final entry in layers.entries) entry.key: _layerJson(entry.value),
    };
  }

  Map<String, Object?> _layerJson(List<LcovFile> files) {
    final covered = files.fold(0, (sum, file) => sum + file.covered);
    final total = files.fold(0, (sum, file) => sum + file.total);
    return {
      'covered': covered,
      'total': total,
      'percent': _round(total == 0 ? 100 : covered * 100 / total),
    };
  }
}

final class CoverageExclusion {
  const CoverageExclusion({
    required this.path,
    required this.lines,
    required this.justification,
    required this.approvedBy,
  });

  final String path;
  final Set<int> lines;
  final String justification;
  final String approvedBy;

  Map<String, Object?> toJson() => {
    'path': path,
    'lines': lines.toList()..sort(),
    'justification': justification,
    'approvedBy': approvedBy,
  };
}

final class LcovFile {
  final String path;
  final Map<int, int> lines = {};

  LcovFile(this.path);

  int get total => lines.length;
  int get covered => lines.values.where((hits) => hits > 0).length;
}

LcovReport parseLcov(String contents) {
  final files = <LcovFile>[];
  LcovFile? current;
  for (final line in contents.split(RegExp(r'\r?\n'))) {
    if (line.startsWith('SF:')) {
      current = LcovFile(line.substring(3));
      files.add(current);
    } else if (line.startsWith('DA:')) {
      if (current == null) {
        throw const FormatException('LCOV DA record has no SF record');
      }
      final parts = line.substring(3).split(',');
      if (parts.length < 2) {
        throw const FormatException('Malformed LCOV DA record');
      }
      final lineNumber = int.tryParse(parts[0]);
      final hits = int.tryParse(parts[1]);
      if (lineNumber == null || hits == null || lineNumber < 1 || hits < 0) {
        throw const FormatException('Malformed LCOV line or hit count');
      }
      current.lines[lineNumber] = hits;
    }
  }
  if (files.isEmpty) {
    throw const FormatException('LCOV contains no source files');
  }
  return LcovReport(files);
}

Future<Map<String, Set<int>>> _changedLines(
  String root,
  String? base,
  List<String> includedRoots,
) async {
  if (base == null || base.isEmpty) return {};
  final result = await Process.run('git', [
    'diff',
    '--unified=0',
    base,
    '--',
    ...(includedRoots.isEmpty ? const ['lib', 'routes'] : includedRoots),
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw FormatException('Unable to calculate changed lines from $base');
  }
  final changed = <String, Set<int>>{};
  String? file;
  for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
    if (line.startsWith('+++ b/')) {
      file = _normalize(line.substring(6));
    } else if (line.startsWith('@@') && file != null) {
      final match = RegExp(r'\+(\d+)(?:,(\d+))?').firstMatch(line);
      if (match == null) continue;
      final start = int.parse(match.group(1)!);
      final count = int.tryParse(match.group(2) ?? '1') ?? 1;
      changed.putIfAbsent(file, () => <int>{}).addAll([
        for (var i = 0; i < count; i++) start + i,
      ]);
    }
  }
  return changed;
}

String _resolve(String root, String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)
    ? path
    : '$root${Platform.pathSeparator}$path';

String _normalize(String value) =>
    value.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');

List<String> _includedRoots(Map<Object?, Object?> config) {
  final raw = config['includedRoots'];
  if (raw is! List) return const ['lib', 'routes'];
  return [
    for (final value in raw)
      if (value is String && value.isNotEmpty) value,
  ];
}

Map<String, List<String>> _configuredLayers(Map<Object?, Object?> config) {
  final raw = config['layers'];
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is List)
        entry.key as String: [
          for (final pattern in entry.value as List)
            if (pattern is String && pattern.isNotEmpty) pattern,
        ],
  };
}

List<CoverageExclusion> _configuredExclusions(Map<Object?, Object?> config) {
  final raw = config['exclusions'];
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('Coverage exclusions must be a list');
  }
  final exclusions = <CoverageExclusion>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const FormatException('Each coverage exclusion must be a mapping');
    }
    final path = item['path'];
    final lines = item['lines'];
    final justification = item['justification'];
    final approvedBy = item['approvedBy'];
    if (path is! String ||
        path.trim().isEmpty ||
        lines is! List ||
        lines.isEmpty ||
        lines.any((line) => line is! int || line < 1) ||
        justification is! String ||
        justification.trim().isEmpty ||
        approvedBy is! String ||
        approvedBy.trim().isEmpty) {
      throw const FormatException(
        'Coverage exclusions require path, positive lines, justification, and approvedBy',
      );
    }
    exclusions.add(
      CoverageExclusion(
        path: _normalize(path),
        lines: lines.cast<int>().toSet(),
        justification: justification,
        approvedBy: approvedBy,
      ),
    );
  }
  return exclusions;
}

void _validateExclusions(
  LcovReport report, {
  required String root,
  required List<String> includedRoots,
  required List<CoverageExclusion> exclusions,
}) {
  final files = {
    for (final file in report.files)
      _relativeCoveragePath(root, file.path): file,
  };
  for (final exclusion in exclusions) {
    final normalizedPath = _normalize(exclusion.path);
    if (!includedRoots.any(
      (included) => _underRoot(normalizedPath, included),
    )) {
      throw FormatException(
        'Coverage exclusion is outside configured production roots: '
        '${exclusion.path}',
      );
    }
    final file = files[normalizedPath];
    if (file == null) {
      throw FormatException(
        'Coverage exclusion path is absent from LCOV: ${exclusion.path}',
      );
    }
    final missingLines = exclusion.lines
        .where((line) => !file.lines.containsKey(line))
        .toList(growable: false);
    if (missingLines.isNotEmpty) {
      throw FormatException(
        'Coverage exclusion lines are absent from LCOV for '
        '${exclusion.path}: ${missingLines.join(', ')}',
      );
    }
  }
}

Map<String, Object?> _readBaseline(String root, String path) {
  final file = File(_resolve(root, path));
  if (!file.existsSync()) {
    throw FormatException('Coverage baseline does not exist: ${file.path}');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map || decoded['percent'] is! num) {
    throw const FormatException(
      'Coverage baseline must contain numeric percent',
    );
  }
  return {'percent': (decoded['percent'] as num).toDouble()};
}

bool _matches(String pattern, String path) {
  final normalizedPattern = _normalize(pattern);
  final normalizedPath = _normalize(path);
  final expression = RegExp.escape(
    normalizedPattern,
  ).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*');
  return RegExp('^$expression\$').hasMatch(normalizedPath);
}

double _round(num value) => double.parse(value.toStringAsFixed(2));

double _number(String? value, {required double fallback}) {
  if (value == null || value.trim().isEmpty) return fallback;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed < 0 || parsed > 100) {
    throw FormatException(
      'Coverage policy value must be between 0 and 100: $value',
    );
  }
  return parsed;
}

String _relativeCoveragePath(String root, String path) {
  final normalizedPath = _normalize(path);
  final normalizedRoot = _normalize(root).replaceFirst(RegExp(r'/$'), '');
  if (normalizedPath == normalizedRoot) return '';
  final prefix = '$normalizedRoot/';
  if (normalizedPath.startsWith(prefix)) {
    return normalizedPath.substring(prefix.length);
  }
  return normalizedPath;
}

bool _underRoot(String path, String root) {
  final normalizedRoot = _normalize(root).replaceFirst(RegExp(r'/$'), '');
  return path == normalizedRoot || path.startsWith('$normalizedRoot/');
}

String _riskLayer(String path) {
  final normalized = _normalize(path);
  if (normalized.contains('/middleware/') ||
      normalized.startsWith('lib/src/middleware/')) {
    return 'security/middleware';
  }
  if (normalized.startsWith('routes/') || normalized.contains('/routes/')) {
    return 'routes';
  }
  if (normalized.contains('socket') ||
      normalized.contains('/game/') ||
      normalized.contains('game/')) {
    return 'WebSocket/game state';
  }
  if (normalized.contains('outbox') ||
      normalized.contains('unit_of_work') ||
      normalized.contains('unitofwork')) {
    return 'outbox/UoW';
  }
  if (normalized.contains('/data/') || normalized.startsWith('lib/src/data/')) {
    return 'repositories';
  }
  if (normalized.contains('/domain/') || normalized.contains('/application/')) {
    return 'domain/application';
  }
  return 'glue';
}
