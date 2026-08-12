import 'dart:convert';
import 'dart:io';

const _threshold = 80.0;
const _behaviorLineThreshold = 200;

void main(List<String> arguments) {
  final options = _Options.parse(arguments);
  try {
    final report = CoverageChecker(
      options.root,
      package: options.package,
    ).check();
    if (options.output != null) {
      final output = File(options.output!);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
      );
    }
    if (options.json) {
      print(jsonEncode(report.toJson()));
    } else {
      report.writeText();
    }
    exit(report.passed ? 0 : 1);
  } on FormatException catch (error) {
    stderr.writeln('ZUKE-COV-002: ${error.message}');
    exit(2);
  }
}

class _Options {
  final String root;
  final bool json;
  final String? output;
  final String? package;

  const _Options({
    required this.root,
    required this.json,
    this.output,
    this.package,
  });

  static _Options parse(List<String> arguments) {
    String? value(String name) {
      final index = arguments.indexOf(name);
      return index >= 0 && index + 1 < arguments.length
          ? arguments[index + 1]
          : null;
    }

    final format = value('--format');
    if (format != null && format != 'json' && format != 'text') {
      throw FormatException('Unsupported --format value: $format');
    }
    return _Options(
      root: value('--root') ?? Directory.current.path,
      json: arguments.contains('--format=json') || format == 'json',
      output: value('--output'),
      package: value('--package'),
    );
  }
}

class CoverageChecker {
  final Directory root;
  final String? package;

  CoverageChecker(String rootPath, {this.package})
    : root = Directory(rootPath).absolute;

  CoverageReport check() {
    final packages = _discoverPackages();
    if (package != null && !packages.containsKey(package)) {
      throw FormatException('Unknown coverage package: $package');
    }
    final selected = package == null
        ? packages
        : {package!: packages[package!]!};
    final expected = <String, Set<String>>{};
    final behaviorLines = <String, int>{};
    for (final package in selected.values) {
      final sources = _sourceInventory(package);
      expected[package.name] = sources;
      behaviorLines[package.name] = _behaviorLineCount(package.root);
    }
    final behaviorBearing = behaviorLines.entries
        .where((entry) => entry.value > _behaviorLineThreshold)
        .map((entry) => entry.key)
        .toSet();
    final hits = <String, Map<String, Map<int, int>>>{};
    final inputs = <File>[];
    for (final package in selected.values) {
      final coverage = Directory(
        '${package.root.path}${Platform.pathSeparator}coverage',
      );
      if (!coverage.existsSync()) continue;
      inputs.addAll(
        coverage
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.json') ||
                  file.path.endsWith('lcov.info'),
            ),
      );
    }
    if (inputs.isEmpty) {
      return CoverageReport.empty(
        behaviorLines: behaviorLines,
        behaviorBearing: behaviorBearing,
      );
    }
    for (final input in inputs) {
      final owner = _ownerForCoverageFile(selected, input);
      if (owner == null) continue;
      if (input.path.endsWith('lcov.info')) {
        _readLcov(input, owner, selected, expected, hits);
      } else {
        _readVmJson(input, owner, selected, expected, hits);
      }
    }
    return CoverageReport.fromHits(
      behaviorLines: behaviorLines,
      behaviorBearing: behaviorBearing,
      expected: expected,
      hits: hits,
    );
  }

  Map<String, _Package> _discoverPackages() {
    final candidates = <Directory>[
      ..._directoriesUnder('vendor-sdk'),
      ..._directoriesUnder(
        'examples${Platform.pathSeparator}calculator-product${Platform.pathSeparator}apps',
      ),
      ..._directoriesUnder(
        'examples${Platform.pathSeparator}calculator-product${Platform.pathSeparator}packages',
      ),
      ..._directoriesUnder('examples'),
    ];
    final packages = <String, _Package>{};
    for (final candidate in candidates) {
      final pubspec = File(
        '${candidate.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (!pubspec.existsSync()) continue;
      final match = RegExp(
        r'^name:\s*(.+)$',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync());
      if (match == null) continue;
      final name = match.group(1)!.trim();
      packages[name] = _Package(name, candidate.absolute);
    }
    return packages;
  }

  Iterable<Directory> _directoriesUnder(String relativePath) {
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$relativePath',
    );
    if (!directory.existsSync()) return const <Directory>[];
    return directory.listSync().whereType<Directory>();
  }

  Set<String> _sourceInventory(_Package package) {
    final lib = Directory('${package.root.path}${Platform.pathSeparator}lib');
    if (!lib.existsSync()) return <String>{};
    final result = <String>{};
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      final normalized = file.absolute.path.replaceAll('\\', '/');
      if (!normalized.endsWith('.dart') ||
          normalized.endsWith('.g.dart') ||
          normalized.contains('/generated/') ||
          _isCoverageIgnored(file) ||
          _isPureReexport(file)) {
        continue;
      }
      final relative = normalized.substring(
        lib.absolute.path.replaceAll('\\', '/').length + 1,
      );
      result.add('package:${package.name}/$relative');
    }
    return result;
  }

  bool _isPureReexport(File file) {
    var inMultilineExport = false;
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (inMultilineExport) {
        if (trimmed.contains(';')) inMultilineExport = false;
        continue;
      }
      if (trimmed.isEmpty ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('/*') ||
          trimmed.startsWith('*') ||
          trimmed.startsWith('*/') ||
          trimmed.startsWith('import ') ||
          trimmed.startsWith('library;') ||
          trimmed.startsWith('library ')) {
        continue;
      }
      if (trimmed.startsWith('export ')) {
        inMultilineExport = !trimmed.contains(';');
        continue;
      }
      return false;
    }
    return true;
  }

  bool _isCoverageIgnored(File file) => file
      .readAsLinesSync()
      .take(5)
      .any((line) => line.trim() == '// coverage:ignore-file');

  int _behaviorLineCount(Directory packageRoot) {
    final lib = Directory('${packageRoot.path}${Platform.pathSeparator}lib');
    if (!lib.existsSync()) return 0;
    var count = 0;
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      final normalized = file.path.replaceAll('\\', '/');
      if (!normalized.endsWith('.dart') ||
          normalized.endsWith('.g.dart') ||
          normalized.contains('/generated/') ||
          _isCoverageIgnored(file) ||
          _isPureReexport(file)) {
        continue;
      }
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith('//') &&
            !trimmed.startsWith('/*') &&
            !trimmed.startsWith('*') &&
            !trimmed.startsWith('*/')) {
          count++;
        }
      }
    }
    return count;
  }

  _Package? _ownerForCoverageFile(Map<String, _Package> packages, File file) {
    final path = file.absolute.path.replaceAll('\\', '/');
    for (final package in packages.values) {
      final prefix = '${package.root.path.replaceAll('\\', '/')}/coverage/';
      if (path.startsWith(prefix)) return package;
    }
    return null;
  }

  void _readVmJson(
    File input,
    _Package coverageOwner,
    Map<String, _Package> packages,
    Map<String, Set<String>> expected,
    Map<String, Map<String, Map<int, int>>> hits,
  ) {
    final decoded = jsonDecode(input.readAsStringSync());
    if (decoded is! Map || decoded['coverage'] is! List) {
      throw FormatException('Malformed VM coverage JSON: ${input.path}');
    }
    for (final raw in decoded['coverage'] as List) {
      if (raw is! Map || raw['source'] is! String || raw['hits'] is! List) {
        throw FormatException('Malformed VM coverage entry: ${input.path}');
      }
      final resolved = _resolveSource(
        raw['source'] as String,
        coverageOwner,
        packages,
        expected,
      );
      if (resolved == null) continue;
      final lineHits = raw['hits'] as List;
      if (lineHits.length.isOdd) {
        throw FormatException('Odd VM hit-pair count: ${input.path}');
      }
      for (var index = 0; index < lineHits.length; index += 2) {
        final line = lineHits[index];
        final count = lineHits[index + 1];
        if (line is! int || count is! int || line < 1 || count < 0) {
          throw FormatException('Invalid VM hit pair: ${input.path}');
        }
        _addHit(hits, resolved.package.name, resolved.source, line, count);
      }
    }
  }

  void _readLcov(
    File input,
    _Package coverageOwner,
    Map<String, _Package> packages,
    Map<String, Set<String>> expected,
    Map<String, Map<String, Map<int, int>>> hits,
  ) {
    _ResolvedSource? source;
    var sawRecord = false;
    for (final line in input.readAsLinesSync()) {
      if (line.startsWith('SF:')) {
        source = _resolveSource(
          line.substring(3),
          coverageOwner,
          packages,
          expected,
        );
        sawRecord = true;
      } else if (line.startsWith('DA:')) {
        final parts = line.substring(3).split(',');
        if (parts.length != 2) {
          throw FormatException('Malformed LCOV DA record: ${input.path}');
        }
        final lineNumber = int.tryParse(parts[0]);
        final count = int.tryParse(parts[1]);
        if (lineNumber == null ||
            count == null ||
            lineNumber < 1 ||
            count < 0) {
          throw FormatException('Invalid LCOV hit record: ${input.path}');
        }
        if (source == null) continue;
        _addHit(hits, source.package.name, source.source, lineNumber, count);
      } else if (line == 'end_of_record') {
        source = null;
      }
    }
    if (!sawRecord) {
      throw FormatException('LCOV file has no source records: ${input.path}');
    }
  }

  _ResolvedSource? _resolveSource(
    String raw,
    _Package coverageOwner,
    Map<String, _Package> packages,
    Map<String, Set<String>> expected,
  ) {
    final ordered = <_Package>[
      coverageOwner,
      ...packages.values.where((package) => package.name != coverageOwner.name),
    ];
    for (final package in ordered) {
      final source = _canonicalSource(raw, package);
      if (source != null && expected[package.name]!.contains(source)) {
        return _ResolvedSource(package, source);
      }
    }
    return null;
  }

  String? _canonicalSource(String raw, _Package owner) {
    var source = raw.replaceAll('\\', '/');
    if (source.startsWith('package:${owner.name}/')) return source;
    if (source.startsWith('file:')) {
      source = Uri.parse(source).toFilePath().replaceAll('\\', '/');
    }
    final libPrefix = '${owner.root.path.replaceAll('\\', '/')}/lib/';
    if (source.startsWith(libPrefix)) {
      return 'package:${owner.name}/${source.substring(libPrefix.length)}';
    }
    if (source.startsWith('lib/')) {
      return 'package:${owner.name}/${source.substring(4)}';
    }
    final marker = '/${owner.name}/lib/';
    final index = source.lastIndexOf(marker);
    if (index >= 0) {
      return 'package:${owner.name}/${source.substring(index + marker.length)}';
    }
    return null;
  }

  void _addHit(
    Map<String, Map<String, Map<int, int>>> hits,
    String package,
    String source,
    int line,
    int count,
  ) {
    final packageHits = hits.putIfAbsent(package, () => {});
    final sourceHits = packageHits.putIfAbsent(source, () => {});
    final current = sourceHits[line];
    if (current == null || count > current) {
      sourceHits[line] = count;
    }
  }
}

class CoverageReport {
  final Map<String, int> behaviorLines;
  final List<_PackageCoverage> packages;

  const CoverageReport(this.behaviorLines, this.packages);

  factory CoverageReport.empty({
    required Map<String, int> behaviorLines,
    required Set<String> behaviorBearing,
  }) {
    final names = behaviorBearing.toList()..sort();
    return CoverageReport(
      behaviorLines,
      names.map(_PackageCoverage.missing).toList(),
    );
  }

  factory CoverageReport.fromHits({
    required Map<String, int> behaviorLines,
    required Set<String> behaviorBearing,
    required Map<String, Set<String>> expected,
    required Map<String, Map<String, Map<int, int>>> hits,
  }) {
    final report = <_PackageCoverage>[];
    for (final name in behaviorBearing.toList()..sort()) {
      final expectedSources = expected[name]!;
      final actual = hits[name] ?? const <String, Map<int, int>>{};
      final missingSources =
          expectedSources
              .where((source) => !actual.containsKey(source))
              .toList()
            ..sort();
      var total = 0;
      var covered = 0;
      final uncovered = <String, List<int>>{};
      for (final source in expectedSources) {
        final sourceHits = actual[source] ?? const <int, int>{};
        final missing = <int>[];
        for (final entry in sourceHits.entries) {
          total++;
          if (entry.value > 0) {
            covered++;
          } else {
            missing.add(entry.key);
          }
        }
        if (missing.isNotEmpty) uncovered[source] = missing..sort();
      }
      report.add(
        _PackageCoverage(
          name: name,
          covered: covered,
          total: total,
          missingSources: missingSources,
          uncoveredLines: uncovered,
        ),
      );
    }
    return CoverageReport(behaviorLines, report);
  }

  int get covered => packages.fold(0, (sum, package) => sum + package.covered);
  int get total => packages.fold(0, (sum, package) => sum + package.total);
  double get percentage => total == 0 ? 0 : covered * 100 / total;
  bool get passed =>
      total > 0 &&
      percentage >= _threshold &&
      packages.every((package) => package.passed);

  Map<String, Object?> toJson() => {
    'kind': 'zuke.coverage',
    'threshold': _threshold,
    'aggregate': {
      'covered': covered,
      'total': total,
      'percentage': percentage,
      'status': passed ? 'pass' : 'fail',
    },
    'packages': packages
        .map((package) => package.toJson(behaviorLines[package.name] ?? 0))
        .toList(),
    'missingPackages': packages
        .where((package) => package.total == 0)
        .map((package) => package.name)
        .toList(),
  };

  void writeText() {
    print(
      'Overall Workspace Line Coverage: ${percentage.toStringAsFixed(2)}% ($covered/$total)',
    );
    for (final package in packages) {
      print(
        '  ${package.name}: ${package.percentage.toStringAsFixed(2)}% '
        '(${package.covered}/${package.total}) [${package.passed ? 'PASS' : 'FAIL'}]',
      );
      for (final source in package.missingSources) {
        print('    ZUKE-COV-003: missing coverage for $source');
      }
    }
  }
}

class _PackageCoverage {
  final String name;
  final int covered;
  final int total;
  final List<String> missingSources;
  final Map<String, List<int>> uncoveredLines;

  const _PackageCoverage({
    required this.name,
    required this.covered,
    required this.total,
    required this.missingSources,
    required this.uncoveredLines,
  });

  factory _PackageCoverage.missing(String name) => _PackageCoverage(
    name: name,
    covered: 0,
    total: 0,
    missingSources: const [],
    uncoveredLines: const {},
  );

  double get percentage => total == 0 ? 0 : covered * 100 / total;
  bool get passed =>
      total > 0 && missingSources.isEmpty && percentage >= _threshold;

  Map<String, Object?> toJson(int behaviorLines) => {
    'name': name,
    'behaviorLines': behaviorLines,
    'covered': covered,
    'total': total,
    'percentage': percentage,
    'status': passed ? 'pass' : 'fail',
    'missingSources': missingSources,
    'uncoveredLines': uncoveredLines,
  };
}

class _Package {
  final String name;
  final Directory root;

  const _Package(this.name, this.root);
}

class _ResolvedSource {
  final _Package package;
  final String source;

  const _ResolvedSource(this.package, this.source);
}
