import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'configuration_preflight.dart';

/// Runs an external tool for coverage evaluation.
///
/// Injectable so the Git-probe branches can be exercised deterministically
/// without depending on the checkout that happens to contain the test.
typedef CoverageProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// A coverage failure with a structured, actionable remediation.
///
/// [FormatException] only carries a human message; command results expose a
/// dedicated `remediation` field, so failures that have a specific recovery
/// step throw this instead of the generic fallback text.
final class _CoverageFailure implements Exception {
  const _CoverageFailure(this.message, {required this.remediation});

  final String message;
  final String remediation;

  @override
  String toString() => message;
}

/// Parses and evaluates LCOV as an independent quality gate.
///
/// Coverage is intentionally not converted into Zuke evidence. It remains a
/// product policy gate with its own baseline and changed-line thresholds.
final class CoverageCommand {
  final ArgResults args;
  final CoverageProcessRunner processRunner;
  bool _reported = false;

  CoverageCommand(this.args, {CoverageProcessRunner? processRunner})
    : processRunner = processRunner ?? Process.run;

  Future<int> execute() async {
    try {
      return await _execute();
    } on _CoverageFailure catch (error) {
      return _fail(error.message, remediation: error.remediation);
    } on FormatException catch (error) {
      return _fail(error.message.toString());
    } on Object catch (error) {
      return _fail('Coverage evaluation failed: $error');
    }
  }

  Future<int> _execute() async {
    final root = Directory(args['root'] as String? ?? Directory.current.path);
    final workspace = requireCurrentWorkspace(root.path);
    final typed = workspace.config.coverage;
    final config = workspace.config.coverageConfig;
    final input =
        args['input'] as String? ??
        typed.input ??
        config['input']?.toString() ??
        'coverage/lcov.info';
    final inputFile = File(_resolve(root.path, input));
    if (!inputFile.existsSync()) {
      return _fail('Coverage input does not exist: ${inputFile.path}');
    }
    final report = parseLcov(inputFile.readAsStringSync());
    final changedSince =
        args['changed-since'] as String? ??
        typed.changedSince ??
        config['changedSince']?.toString();
    final changed = await _changedLines(
      root.path,
      changedSince,
      _includedRoots(config, typed),
      processRunner,
    );
    final minimum = _number(
      args['minimum'] as String? ??
          typed.minimumTotal?.toString() ??
          config['minimumTotal']?.toString(),
      fallback: 100,
    );
    final changedMinimum = _number(
      args['changed-line-minimum'] as String? ??
          typed.changedLineMinimum?.toString() ??
          config['changedLineMinimum']?.toString(),
      fallback: 100,
    );
    final baselinePath =
        args['baseline'] as String? ??
        typed.baseline ??
        config['baseline']?.toString();
    final writeBaseline =
        args.options.contains('write-baseline') &&
        (args['write-baseline'] as bool? ?? false);
    var baseline = writeBaseline || baselinePath == null || baselinePath.isEmpty
        ? null
        : _readBaseline(root.path, baselinePath);
    final exclusions = _configuredExclusions(config);
    _validateExclusions(
      report,
      root: root.path,
      includedRoots: _includedRoots(config, typed),
      exclusions: exclusions,
    );
    final scopedReport = report.scoped(
      root: root.path,
      includedRoots: _includedRoots(config, typed),
      exclusions: exclusions,
    );
    if (scopedReport.files.isEmpty) {
      return _fail(
        'LCOV contains no files under the configured production roots: '
        '${_includedRoots(config, typed).join(', ')}',
      );
    }
    final payload = scopedReport.toJson(
      changedLines: changed.current,
      layers: _configuredLayers(config, typed),
      includedRoots: _includedRoots(config, typed),
    );
    // Preserve the pre-existing baseline for regression comparison. When a
    // caller explicitly writes a replacement baseline, the newly generated
    // document must not be compared with the same run (rounded percentages
    // could otherwise make a baseline fail against itself).
    final comparisonBaseline = baseline;
    final baselineHunks = comparisonBaseline == null
        ? changed.hunks
        : await _baselineHunks(
            root.path,
            comparisonBaseline,
            baselinePath: baselinePath!,
            changedSince: changedSince,
            fallback: changed.hunks,
            includedRoots: _includedRoots(config, typed),
            processRunner: processRunner,
          );
    Map<String, Object?>? replacementBaseline;
    final lineComparison = comparisonBaseline == null
        ? null
        : _compareBaseline(comparisonBaseline, scopedReport, baselineHunks);
    if (lineComparison != null) {
      payload['baselineComparison'] = lineComparison;
    }
    if (writeBaseline) {
      if (baselinePath == null || baselinePath.isEmpty) {
        return _fail(
          '--write-baseline requires a configured or explicit --baseline path',
        );
      }
      replacementBaseline = buildCoverageBaseline(
        scopedReport,
        root: root.path,
        includedRoots: _includedRoots(config, typed),
        exclusions: exclusions,
        revision: _gitRevision(root.path),
      );
    }
    final changedPercent = payload['changedLines'] is Map
        ? (payload['changedLines'] as Map)['percent'] as num
        : 100;
    String? failure;
    if (scopedReport.percent + 0.0001 < minimum) {
      failure = 'Coverage is below ${minimum.toStringAsFixed(2)}%.';
    } else if (comparisonBaseline != null &&
        scopedReport.percent + 0.0001 <
            (comparisonBaseline['percent'] as num).toDouble()) {
      failure =
          'Coverage regressed from '
          '${(comparisonBaseline['percent'] as num).toStringAsFixed(2)}% to '
          '${scopedReport.percent.toStringAsFixed(2)}%.';
    } else if (lineComparison != null &&
        (lineComparison['lostUnchangedLineCount'] as num? ?? 0) > 0) {
      failure =
          'Coverage lost '
          '${lineComparison['lostUnchangedLineCount']} previously covered '
          'production line(s).';
    } else if (changed.current.isNotEmpty &&
        changedPercent + 0.0001 < changedMinimum) {
      failure =
          'Changed production lines are below '
          '${changedMinimum.toStringAsFixed(2)}% coverage.';
    }
    if (failure == null && replacementBaseline != null) {
      final baselineFile = File(_resolve(root.path, baselinePath!));
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(replacementBaseline)}\n',
      );
    }
    final reportBaseline = replacementBaseline ?? comparisonBaseline;
    final document = <String, Object?>{
      'kind': 'zuke.coverage',
      ...payload,
      'policy': {
        'minimumTotal': minimum,
        'changedLineMinimum': changedMinimum,
        'exclusions': [for (final exclusion in exclusions) exclusion.toJson()],
        if (reportBaseline != null)
          'baseline': {
            for (final entry in reportBaseline.entries)
              if (entry.key != 'sourceLines') entry.key: entry.value,
          },
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

  int _fail(String message, {String? remediation}) {
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
                remediation ??
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

final class _ChangedCoverageLines {
  const _ChangedCoverageLines({required this.current, required this.hunks});

  final Map<String, Set<int>> current;
  final Map<String, List<_CoverageDiffHunk>> hunks;
}

final class _CoverageDiffHunk {
  const _CoverageDiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  bool containsOldLine(int line) =>
      line >= oldStart && line < oldStart + oldCount;
}

Future<_ChangedCoverageLines> _changedLines(
  String root,
  String? base,
  List<String> includedRoots,
  CoverageProcessRunner processRunner,
) async {
  if (base == null || base.isEmpty) {
    return const _ChangedCoverageLines(current: {}, hunks: {});
  }
  final result = await processRunner('git', [
    'diff',
    '--unified=0',
    base,
    '--',
    ...(includedRoots.isEmpty ? const ['lib', 'routes'] : includedRoots),
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw _CoverageFailure(
      'Unable to calculate changed lines from $base.',
      remediation:
          'Ensure the Git revision is fetched and the included roots exist, '
          'then rerun coverage.',
    );
  }
  final current = <String, Set<int>>{};
  final hunks = <String, List<_CoverageDiffHunk>>{};
  String? file;
  for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
    if (line.startsWith('+++ b/')) {
      file = _normalize(line.substring(6));
    } else if (line.startsWith('@@') && file != null) {
      final match = RegExp(
        r'-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?',
      ).firstMatch(line);
      if (match == null) continue;
      final oldStart = int.parse(match.group(1)!);
      final oldCount = int.tryParse(match.group(2) ?? '1') ?? 1;
      final newStart = int.parse(match.group(3)!);
      final newCount = int.tryParse(match.group(4) ?? '1') ?? 1;
      final currentLines = current.putIfAbsent(file, () => <int>{});
      currentLines.addAll([for (var i = 0; i < newCount; i++) newStart + i]);
      hunks
          .putIfAbsent(file, () => <_CoverageDiffHunk>[])
          .add(
            _CoverageDiffHunk(
              oldStart: oldStart,
              oldCount: oldCount,
              newStart: newStart,
              newCount: newCount,
            ),
          );
    }
  }
  return _ChangedCoverageLines(current: current, hunks: hunks);
}

Future<Map<String, List<_CoverageDiffHunk>>> _baselineHunks(
  String root,
  Map<String, Object?> baseline, {
  required String baselinePath,
  required String? changedSince,
  required Map<String, List<_CoverageDiffHunk>> fallback,
  required List<String> includedRoots,
  required CoverageProcessRunner processRunner,
}) async {
  // Snapshots describe the source measured by LCOV, including uncommitted
  // edits. A reachable HEAD can describe different source, so snapshots must
  // take precedence even when the recorded revision is still available.
  final sourceLines = baseline['sourceLines'];
  if (sourceLines is Map &&
      _hasCompleteSourceSnapshots(baseline, sourceLines)) {
    return _snapshotHunks(root, sourceLines);
  }
  final revision = baseline['revision'];
  if (revision is! String || revision.isEmpty || revision == changedSince) {
    return fallback;
  }
  // Baselines created before revision tracking retain the previous comparison
  // behavior. Source archives without Git metadata do as well. Newer
  // baselines carry source snapshots, which let amended or rebased checkouts
  // compare against the recorded source even when Git has pruned the SHA.
  // Without a complete snapshot, silently falling back when the recorded
  // revision is missing would make unrelated lines look like regressions
  // because the fallback diff has a different base, so fail with the missing
  // revision and its baseline path.
  final revisionAvailable = await _gitRevisionAvailable(
    root,
    revision,
    processRunner,
  );
  if (!revisionAvailable) {
    // A source archive has no Git worktree and retains the legacy fallback.
    // In a checkout, distinguish that case from a missing recorded revision
    // so the caller gets an actionable error instead of false line losses.
    if (!await _gitWorktreeAvailable(root, processRunner)) return fallback;
    throw _CoverageFailure(
      'Coverage baseline revision is unavailable: $revision '
      '(baseline: $baselinePath).',
      remediation:
          'Fetch the missing revision, or regenerate the baseline at a '
          'reachable commit with --write-baseline and review the diff.',
    );
  }
  // The revision is known to exist, so a diff failure here is not a reason to
  // silently compare against a different base. Propagate it as a failure
  // instead of producing the false line losses this guard exists to prevent.
  return (await _changedLines(
    root,
    revision,
    includedRoots,
    processRunner,
  )).hunks;
}

Future<bool> _gitWorktreeAvailable(
  String root,
  CoverageProcessRunner processRunner,
) async {
  try {
    final result = await processRunner('git', const [
      'rev-parse',
      '--is-inside-work-tree',
    ], workingDirectory: root);
    return result.exitCode == 0 && result.stdout.toString().trim() == 'true';
  } on Object {
    return false;
  }
}

Future<bool> _gitRevisionAvailable(
  String root,
  String revision,
  CoverageProcessRunner processRunner,
) async {
  try {
    final result = await processRunner('git', [
      'cat-file',
      '-e',
      '$revision^{commit}',
    ], workingDirectory: root);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}

String _resolve(String root, String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)
    ? path
    : '$root${Platform.pathSeparator}$path';

String _normalize(String value) =>
    value.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');

List<String> _includedRoots(
  Map<Object?, Object?> config,
  // Typed view takes precedence; raw map remains for forward-compat keys.
  WorkspaceCoverageConfig typed,
) {
  if (typed.includedRoots.isNotEmpty) return typed.includedRoots;
  final raw = config['includedRoots'];
  if (raw is! List) return const ['lib', 'routes'];
  return [
    for (final value in raw)
      if (value is String && value.isNotEmpty) value,
  ];
}

Map<String, List<String>> _configuredLayers(
  Map<Object?, Object?> config,
  WorkspaceCoverageConfig typed,
) {
  if (typed.layers.isNotEmpty) return typed.layers;
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
  final baseline = <String, Object?>{
    for (final entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  _validateBaselineFiles(baseline['files']);
  _validateBaselineSourceSnapshots(
    baseline['sourceSnapshotVersion'],
    baseline['sourceLines'],
  );
  baseline['percent'] = (decoded['percent'] as num).toDouble();
  return baseline;
}

/// Creates the immutable, reviewable shape used for coverage preservation.
///
/// The percentage remains in the document for compatibility with older
/// baselines, while the file/line sets make a same-percentage regression
/// observable. When [root] is supplied, normalized source lines are included
/// so line preservation remains available after a history rewrite.
Map<String, Object?> buildCoverageBaseline(
  LcovReport report, {
  String? root,
  required List<String> includedRoots,
  List<CoverageExclusion> exclusions = const [],
  String? revision,
}) {
  final sourceLines = root == null ? null : _sourceSnapshots(root, report);
  return {
    'kind': 'zuke.coverage-baseline',
    'schemaVersion': 1,
    if (revision != null && revision.isNotEmpty) 'revision': revision,
    if (sourceLines != null) ...{
      'sourceSnapshotVersion': 1,
      'sourceLines': sourceLines,
    },
    'includedRoots': includedRoots,
    'covered': report.covered,
    'total': report.total,
    'percent': _round(report.percent),
    'exclusions': [for (final exclusion in exclusions) exclusion.toJson()],
    'files': {
      for (final file in report.files)
        _normalize(file.path): {
          'executableLines': file.lines.keys.toList()..sort(),
          'coveredLines': [
            for (final entry in file.lines.entries)
              if (entry.value > 0) entry.key,
          ]..sort(),
        },
    },
  };
}

Map<String, Object?> _compareBaseline(
  Map<String, Object?> baseline,
  LcovReport current,
  Map<String, List<_CoverageDiffHunk>> hunks,
) {
  final rawFiles = baseline['files'];
  if (rawFiles is! Map) {
    return const {
      'mode': 'percentage-only',
      'lostUnchangedLineCount': 0,
      'lostUnchangedLines': <Object?>[],
    };
  }
  final currentCovered = <String, Set<int>>{
    for (final file in current.files)
      _normalize(file.path): {
        for (final entry in file.lines.entries)
          if (entry.value > 0) entry.key,
      },
  };
  final lost = <String, List<int>>{};
  for (final entry in rawFiles.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final file = _normalize(entry.key as String);
    final values = (entry.value as Map)['coveredLines'];
    if (values is! List) continue;
    final previous = values.whereType<int>().toSet();
    final currentLines = currentCovered[file] ?? const <int>{};
    final fileHunks = hunks[file];
    final unchanged = <int>{};
    for (final oldLine in previous) {
      if (fileHunks == null || fileHunks.isEmpty) {
        if (!currentLines.contains(oldLine)) unchanged.add(oldLine);
        continue;
      }
      // A line inside a changed hunk belongs to the changed-line policy. It
      // should not also be reported as an unchanged baseline loss.
      if (fileHunks.any((hunk) => hunk.containsOldLine(oldLine))) continue;
      final mappedLine = _mapOldLine(oldLine, fileHunks);
      if (!currentLines.contains(mappedLine)) unchanged.add(oldLine);
    }
    if (unchanged.isNotEmpty) lost[file] = unchanged.toList()..sort();
  }
  return {
    'mode': 'covered-line-set',
    'lostUnchangedLineCount': lost.values.fold<int>(
      0,
      (sum, lines) => sum + lines.length,
    ),
    'lostUnchangedLines': {
      for (final entry in lost.entries) entry.key: entry.value,
    },
  };
}

Map<String, List<String>> _sourceSnapshots(String root, LcovReport report) {
  final snapshots = <String, List<String>>{};
  for (final file in report.files) {
    final path = _normalize(file.path);
    final source = File(_resolve(root, path));
    // LCOV fixtures and source archives can contain report entries without a
    // corresponding source file. Keep baseline generation compatible with
    // those inputs; a complete snapshot is required before the portable
    // fallback can be used.
    if (!source.existsSync()) continue;
    snapshots[path] = source.readAsLinesSync();
  }
  return snapshots;
}

bool _hasCompleteSourceSnapshots(
  Map<String, Object?> baseline,
  Map<Object?, Object?> snapshots,
) {
  final files = baseline['files'];
  if (files is! Map || files.isEmpty) return false;
  for (final entry in files.entries) {
    if (entry.key is! String || !snapshots.containsKey(entry.key)) {
      return false;
    }
  }
  return true;
}

Map<String, List<_CoverageDiffHunk>> _snapshotHunks(
  String root,
  Map<Object?, Object?> snapshots,
) {
  final hunks = <String, List<_CoverageDiffHunk>>{};
  for (final entry in snapshots.entries) {
    if (entry.key is! String || entry.value is! List) continue;
    final path = _normalize(entry.key as String);
    final source = File(_resolve(root, path));
    if (!source.existsSync()) {
      throw _CoverageFailure(
        'Coverage baseline source snapshot file is unavailable: $path.',
        remediation:
            'Restore the source file or regenerate the coverage baseline.',
      );
    }
    final previous = [
      for (final line in entry.value as List)
        if (line is String) line,
    ];
    final current = source.readAsLinesSync();
    final fileHunks = _lineDiffHunks(previous, current);
    if (fileHunks.isNotEmpty) hunks[path] = fileHunks;
  }
  return hunks;
}

final class _SnapshotOperation {
  const _SnapshotOperation.equal(this.oldIndex, this.newIndex)
    : kind = _SnapshotOperationKind.equal;

  const _SnapshotOperation.insert(this.oldIndex, this.newIndex)
    : kind = _SnapshotOperationKind.insert;

  const _SnapshotOperation.delete(this.oldIndex, this.newIndex)
    : kind = _SnapshotOperationKind.delete;

  final _SnapshotOperationKind kind;
  final int oldIndex;
  final int newIndex;
}

enum _SnapshotOperationKind { equal, insert, delete }

List<_CoverageDiffHunk> _lineDiffHunks(
  List<String> previous,
  List<String> current,
) {
  final max = previous.length + current.length;
  final offset = max + 1;
  final size = max * 2 + 3;
  var frontier = List<int>.filled(size, 0);
  final trace = <List<int>>[];
  var distance = 0;
  for (; distance <= max; distance++) {
    trace.add(List<int>.from(frontier));
    for (var diagonal = -distance; diagonal <= distance; diagonal += 2) {
      final index = diagonal + offset;
      final x =
          diagonal == -distance ||
              (diagonal != distance &&
                  frontier[index - 1] < frontier[index + 1])
          ? frontier[index + 1]
          : frontier[index - 1] + 1;
      var oldIndex = x;
      var newIndex = oldIndex - diagonal;
      while (oldIndex < previous.length &&
          newIndex < current.length &&
          previous[oldIndex] == current[newIndex]) {
        oldIndex++;
        newIndex++;
      }
      frontier[index] = oldIndex;
      if (oldIndex >= previous.length && newIndex >= current.length) {
        return _snapshotHunksFromOperations(
          _backtrackSnapshotOperations(
            trace,
            distance,
            offset,
            previous.length,
            current.length,
          ),
        );
      }
    }
  }
  return const [];
}

List<_SnapshotOperation> _backtrackSnapshotOperations(
  List<List<int>> trace,
  int distance,
  int offset,
  int previousLength,
  int currentLength,
) {
  var oldIndex = previousLength;
  var newIndex = currentLength;
  final reversed = <_SnapshotOperation>[];
  for (var d = distance; d > 0; d--) {
    final frontier = trace[d];
    final diagonal = oldIndex - newIndex;
    final index = diagonal + offset;
    final previousDiagonal =
        diagonal == -d ||
            (diagonal != d && frontier[index - 1] < frontier[index + 1])
        ? diagonal + 1
        : diagonal - 1;
    final previousOldIndex = frontier[previousDiagonal + offset];
    final previousNewIndex = previousOldIndex - previousDiagonal;
    while (oldIndex > previousOldIndex && newIndex > previousNewIndex) {
      reversed.add(_SnapshotOperation.equal(oldIndex - 1, newIndex - 1));
      oldIndex--;
      newIndex--;
    }
    if (oldIndex == previousOldIndex) {
      reversed.add(_SnapshotOperation.insert(oldIndex, newIndex - 1));
      newIndex--;
    } else {
      reversed.add(_SnapshotOperation.delete(oldIndex - 1, newIndex));
      oldIndex--;
    }
  }
  while (oldIndex > 0 && newIndex > 0) {
    reversed.add(_SnapshotOperation.equal(oldIndex - 1, newIndex - 1));
    oldIndex--;
    newIndex--;
  }
  return reversed.reversed.toList(growable: false);
}

List<_CoverageDiffHunk> _snapshotHunksFromOperations(
  List<_SnapshotOperation> operations,
) {
  final hunks = <_CoverageDiffHunk>[];
  int? oldStart;
  int? newStart;
  var oldCount = 0;
  var newCount = 0;

  void flush() {
    if (oldStart == null || newStart == null) return;
    hunks.add(
      _CoverageDiffHunk(
        oldStart: oldStart!,
        oldCount: oldCount,
        newStart: newStart!,
        newCount: newCount,
      ),
    );
    oldStart = null;
    newStart = null;
    oldCount = 0;
    newCount = 0;
  }

  for (final operation in operations) {
    if (operation.kind == _SnapshotOperationKind.equal) {
      flush();
      continue;
    }
    if (operation.kind == _SnapshotOperationKind.insert) {
      // The old side of a pure insertion is the position after the last
      // consumed line. This matches unified diff's `-<line>,0` convention and
      // lets _mapOldLine apply the insertion to lines that follow it.
      oldStart ??= operation.oldIndex;
      newStart ??= operation.newIndex + 1;
      newCount++;
    } else {
      oldStart ??= operation.oldIndex + 1;
      newStart ??= operation.newIndex + 1;
      oldCount++;
    }
  }
  flush();
  return hunks;
}

int _mapOldLine(int oldLine, List<_CoverageDiffHunk> hunks) {
  var delta = 0;
  for (final hunk in hunks) {
    // For a pure insertion, oldStart is the line the insertion follows; the
    // anchor line itself keeps its number. Lines after it receive the delta.
    if (oldLine < hunk.oldStart ||
        (hunk.oldCount == 0 && oldLine == hunk.oldStart)) {
      break;
    }
    delta += hunk.newCount - hunk.oldCount;
  }
  return oldLine + delta;
}

void _validateBaselineFiles(Object? raw) {
  if (raw == null) return;
  if (raw is! Map) {
    throw const FormatException('Coverage baseline files must be a mapping');
  }
  for (final entry in raw.entries) {
    if (entry.key is! String || entry.value is! Map) {
      throw const FormatException(
        'Coverage baseline file entries must be mappings',
      );
    }
    final covered = (entry.value as Map)['coveredLines'];
    if (covered != null &&
        (covered is! List || covered.any((line) => line is! int || line < 1))) {
      throw const FormatException(
        'Coverage baseline coveredLines must contain positive integers',
      );
    }
  }
}

void _validateBaselineSourceSnapshots(Object? version, Object? raw) {
  if (version != null && version != 1) {
    throw const FormatException(
      'Coverage baseline sourceSnapshotVersion must be 1',
    );
  }
  if (raw == null) return;
  if (raw is! Map) {
    throw const FormatException(
      'Coverage baseline sourceLines must be a mapping',
    );
  }
  for (final entry in raw.entries) {
    if (entry.key is! String ||
        entry.value is! List ||
        (entry.value as List).any((line) => line is! String)) {
      throw const FormatException(
        'Coverage baseline sourceLines entries must be string lists',
      );
    }
  }
}

String? _gitRevision(String root) {
  try {
    final result = Process.runSync(
      'git',
      const ['rev-parse', 'HEAD'],
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode == 0) {
      final value = (result.stdout as String).trim();
      if (value.isNotEmpty) return value;
    }
  } on Object {
    // Baselines remain useful in source archives without Git metadata.
  }
  return null;
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
