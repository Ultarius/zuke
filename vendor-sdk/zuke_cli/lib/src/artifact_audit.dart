import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:zuke_core/zuke_core.dart';

import 'command_result.dart';
import 'path_safety.dart';

/// A finding in an assurance artifact bundle. The finding never includes the
/// matched value, because the report may itself be uploaded to CI.
final class ArtifactAuditFinding {
  const ArtifactAuditFinding({
    required this.category,
    required this.path,
    required this.message,
  });

  final String category;
  final String path;
  final String message;

  Map<String, String> toJson() => {
    'category': category,
    'path': path,
    'message': message,
  };
}

final class ArtifactAuditReport {
  const ArtifactAuditReport({
    required this.input,
    required this.filesScanned,
    required this.findings,
  });

  final String input;
  final int filesScanned;
  final List<ArtifactAuditFinding> findings;

  bool get safe => findings.isEmpty;

  Map<String, Object?> toJson() => {
    'kind': 'zuke.artifacts-audit',
    'input': input,
    'safe': safe,
    'filesScanned': filesScanned,
    'findings': findings.map((finding) => finding.toJson()).toList(),
  };
}

List<Diagnostic> _artifactFindingDiagnostics(ArtifactAuditReport report) => [
  for (final finding in report.findings)
    Diagnostic(
      code:
          'ZK-ARTIFACT-${finding.category.toUpperCase().replaceAll('-', '_')}',
      stage: 'artifacts',
      severity: DiagnosticSeverity.error,
      owner: DiagnosticOwner.project,
      message: '${finding.path}: ${finding.message}',
      remediation:
          'Remove the finding from the exact upload bundle and rerun the audit.',
    ),
];

CommandResult _artifactCommandResult({
  required String command,
  required ArtifactAuditReport report,
  Map<String, Object?> extraDetails = const <String, Object?>{},
}) => CommandResult(
  command: command,
  stage: 'artifacts',
  exitCode: report.safe ? 0 : 1,
  status: report.safe ? CommandStatus.passed : CommandStatus.failed,
  eligible: report.safe,
  diagnostics: _artifactFindingDiagnostics(report),
  // Keep the report under a namespaced detail. Artifact reports have their
  // own `kind` discriminator, while `kind` is reserved by the command-result
  // envelope.
  details: {...extraDetails, 'report': report.toJson()},
);

int _emitArtifactResult({
  required ArgResults args,
  required CommandResult result,
  required ArtifactAuditReport report,
  required String noun,
  String? resultFile,
}) {
  final encoded = encodeCommandResult(result);
  if (resultFile != null && resultFile.isNotEmpty) {
    final outputFile = File(resultFile);
    outputFile.parent.createSync(recursive: true);
    writeCommandResult(outputFile, encoded);
  }
  if ((args['format'] as String? ?? 'text') == 'json') {
    stdout.write(encoded);
  } else {
    stdout.writeln(
      report.safe
          ? 'Artifact $noun is safe (${report.filesScanned} files).'
          : 'Artifact $noun rejected (${report.findings.length} finding(s)).',
    );
    for (final finding in report.findings) {
      stderr.writeln(
        '  ${finding.category}: ${finding.path}: ${finding.message}',
      );
    }
  }
  writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
  return result.exitCode;
}

/// Audits the exact directory that a CI workflow intends to upload.
final class ArtifactAudit {
  const ArtifactAudit();

  /// Audits the current inputs before copying to a separate, empty bundle.
  /// A caller-supplied earlier report cannot authorize a changed directory.
  ArtifactAuditReport copySafe(Directory input, Directory output) {
    final report = inspect(input);
    if (!report.safe) return report;
    if (pathEqualsOrWithin(input.path, output.path)) {
      throw ArgumentError(
        'Artifact output must be outside the input directory',
      );
    }
    if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ArgumentError('Artifact output must not already exist');
    }
    final files = input
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList();
    output.createSync(recursive: true);
    for (final file in files) {
      final copy = File(
        p.join(output.path, p.relative(file.path, from: input.path)),
      );
      copy.parent.createSync(recursive: true);
      file.copySync(copy.path);
    }
    return report;
  }

  ArtifactAuditReport inspect(Directory input) {
    final absolute = input.absolute;
    if (!input.existsSync()) {
      return ArtifactAuditReport(
        input: absolute.path,
        filesScanned: 0,
        findings: [
          ArtifactAuditFinding(
            category: 'missing-input',
            path: _displayPath(absolute, absolute),
            message: 'Artifact bundle directory does not exist.',
          ),
        ],
      );
    }
    final inputType = FileSystemEntity.typeSync(input.path, followLinks: false);
    if (inputType == FileSystemEntityType.link) {
      return ArtifactAuditReport(
        input: absolute.path,
        filesScanned: 0,
        findings: [
          ArtifactAuditFinding(
            category: 'unsafe-path',
            path: _displayPath(absolute, absolute),
            message: 'The artifact bundle root must not be a symbolic link.',
          ),
        ],
      );
    }
    if (inputType != FileSystemEntityType.directory) {
      return ArtifactAuditReport(
        input: absolute.path,
        filesScanned: 0,
        findings: [
          ArtifactAuditFinding(
            category: 'invalid-input',
            path: _displayPath(absolute, absolute),
            message: 'Artifact input must be a directory.',
          ),
        ],
      );
    }
    final findings = <ArtifactAuditFinding>[];
    var filesScanned = 0;
    final rootPath = _canonicalPath(absolute);
    for (final entity in absolute.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final relative = _relativePath(absolute, entity);
      if (entity is Link) {
        findings.add(
          ArtifactAuditFinding(
            category: 'unsafe-path',
            path: relative,
            message: 'Symbolic links are not allowed in an upload bundle.',
          ),
        );
        continue;
      }
      if (entity is! File) continue;
      filesScanned++;
      final canonicalFile = _canonicalPath(entity);
      if (!_isWithin(rootPath, canonicalFile)) {
        findings.add(
          ArtifactAuditFinding(
            category: 'unsafe-path',
            path: relative,
            message: 'Artifact path resolves outside the upload root.',
          ),
        );
        continue;
      }
      if (_isSourceFile(relative)) {
        findings.add(
          ArtifactAuditFinding(
            category: 'unexpected-source',
            path: relative,
            message: 'Source files are not valid assurance artifacts.',
          ),
        );
      }
      final bytes = _readBytes(entity, relative, findings);
      if (bytes == null) continue;
      final content = utf8.decode(bytes, allowMalformed: true);
      for (final pattern in _sensitivePatterns) {
        if (pattern.expression.hasMatch(content)) {
          findings.add(
            ArtifactAuditFinding(
              category: pattern.category,
              path: relative,
              message: 'Sensitive material detected; matching content omitted.',
            ),
          );
        }
      }
    }
    if (filesScanned == 0) {
      findings.add(
        const ArtifactAuditFinding(
          category: 'empty-input',
          path: '.',
          message: 'Artifact bundle contains no readable files.',
        ),
      );
    }
    return ArtifactAuditReport(
      input: absolute.path,
      filesScanned: filesScanned,
      findings: _unique(findings),
    );
  }

  List<int>? _readBytes(
    File file,
    String relative,
    List<ArtifactAuditFinding> findings,
  ) {
    try {
      return file.readAsBytesSync();
    } on Object {
      findings.add(
        ArtifactAuditFinding(
          category: 'unreadable-input',
          path: relative,
          message: 'Artifact could not be read.',
        ),
      );
      return null;
    }
  }
}

final class ArtifactAuditCommand {
  const ArtifactAuditCommand(this.args);

  final ArgResults args;

  Future<int> execute() async {
    final input = args['input'] as String?;
    if (input == null || input.trim().isEmpty) {
      throw const FormatException(
        'artifacts audit requires --input <directory>',
      );
    }
    final report = const ArtifactAudit().inspect(Directory(input));
    return _emitArtifactResult(
      args: args,
      result: _artifactCommandResult(
        command: 'artifacts audit',
        report: report,
      ),
      report: report,
      noun: 'bundle',
      resultFile: args['output'] as String?,
    );
  }
}

/// Builds an upload bundle from framework-produced artifact directories.
///
/// Each directory contributes its contents at the bundle root; individual
/// files contribute their basename. The destination is created only after all
/// inputs have been validated, so a typo cannot silently produce a partial
/// upload.
final class ArtifactPackageCommand {
  const ArtifactPackageCommand(this.args);

  final ArgResults args;

  Future<int> execute() async {
    final outputValue = args['output'] as String?;
    final includes = (args['include'] as List<String>?) ?? const <String>[];
    if (outputValue == null || outputValue.trim().isEmpty) {
      throw const FormatException(
        'artifacts package requires --output <directory>',
      );
    }
    if (includes.isEmpty) {
      throw const FormatException(
        'artifacts package requires at least one --include path',
      );
    }
    final output = Directory(outputValue);
    if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FormatException(
        'Artifact package output must not already exist: ${output.path}',
      );
    }
    final destination = canonicalComparablePath(output.path);
    final plans = <_ArtifactCopyPlan>[];
    for (final option in ['output-file', 'summary-file']) {
      if (!args.options.contains(option)) continue;
      final value = args[option] as String?;
      if (value == null || value.isEmpty) continue;
      final reportPath = canonicalComparablePath(value);
      if (pathEqualsOrWithin(destination, reportPath)) {
        throw FormatException(
          '--$option must be outside the audited artifact package',
        );
      }
    }
    final destinations = <String>{};
    for (final value in includes) {
      final source = FileSystemEntity.typeSync(value, followLinks: false);
      if (source == FileSystemEntityType.notFound) {
        throw FormatException('Artifact package input does not exist: $value');
      }
      if (source == FileSystemEntityType.link) {
        throw FormatException(
          'Artifact package input must not be a link: $value',
        );
      }
      if (pathEqualsOrWithin(value, destination)) {
        throw FormatException(
          'Artifact package output must be outside input: $value',
        );
      }
      if (source == FileSystemEntityType.directory) {
        final entity = Directory(value);
        for (final child in entity.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (child is Link) {
            throw FormatException(
              'Artifact package input contains a symbolic link: ${child.path}',
            );
          }
          if (child is! File) continue;
          plans.add(
            _ArtifactCopyPlan(
              child,
              p.join(output.path, p.relative(child.path, from: entity.path)),
            ),
          );
        }
      } else {
        plans.add(
          _ArtifactCopyPlan(
            File(value),
            p.join(output.path, p.basename(value)),
          ),
        );
      }
    }
    for (final plan in plans) {
      final key = Platform.isWindows
          ? p.canonicalize(plan.destination).toLowerCase()
          : p.canonicalize(plan.destination);
      if (!destinations.add(key)) {
        throw FormatException(
          'Artifact package inputs collide at ${plan.destination}',
        );
      }
    }

    try {
      output.createSync(recursive: true);
      for (final plan in plans) {
        final destinationFile = File(plan.destination);
        destinationFile.parent.createSync(recursive: true);
        plan.source.copySync(destinationFile.path);
      }
      final report = const ArtifactAudit().inspect(output);
      final result = _artifactCommandResult(
        command: 'artifacts package',
        report: report,
        extraDetails: {'output': output.absolute.path, 'inputs': includes},
      );
      final resultOutput = args.options.contains('output-file')
          ? args['output-file'] as String?
          : null;
      return _emitArtifactResult(
        args: args,
        result: result,
        report: report,
        noun: 'package',
        resultFile: resultOutput,
      );
    } catch (_) {
      if (output.existsSync()) output.deleteSync(recursive: true);
      rethrow;
    }
  }
}

final class _ArtifactCopyPlan {
  const _ArtifactCopyPlan(this.source, this.destination);

  final File source;
  final String destination;
}

final class _SensitivePattern {
  const _SensitivePattern(this.category, this.expression);

  final String category;
  final RegExp expression;
}

final _sensitivePatterns = <_SensitivePattern>[
  _SensitivePattern(
    'bearer-token',
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
  ),
  _SensitivePattern(
    'jwt-like-value',
    RegExp(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'),
  ),
  _SensitivePattern(
    'secret-field',
    RegExp(
      r'''(?:"|\b)(password|secret|api[-_]?key|access[-_]?token|refresh[-_]?token)(?:"|\b)\s*[:=]\s*(?:"[^"]+"|'[^']+'|\S+)''',
      caseSensitive: false,
    ),
  ),
  _SensitivePattern(
    'raw-payload-field',
    RegExp(
      r'("?(payload|requestBody|responseBody|outboxPayload|body)"?)\s*[:=]\s*("[^"]{20,}"|\{[^}]{20,}\}|\[[^]]{20,}\])',
      caseSensitive: false,
    ),
  ),
];

List<ArtifactAuditFinding> _unique(List<ArtifactAuditFinding> findings) {
  final seen = <String>{};
  return findings
      .where((finding) => seen.add('${finding.category}|${finding.path}'))
      .toList(growable: false);
}

bool _isSourceFile(String path) {
  final normalized = path.replaceAll('\\', '/');
  final extension = normalized.contains('.')
      ? normalized.substring(normalized.lastIndexOf('.')).toLowerCase()
      : '';
  return normalized.startsWith('lib/') ||
      normalized.startsWith('routes/') ||
      const {
        '.dart',
        '.kt',
        '.java',
        '.swift',
        '.tsx',
        '.ts',
        '.js',
        '.cc',
        '.cpp',
        '.h',
      }.contains(extension);
}

String _canonicalPath(FileSystemEntity entity) {
  try {
    return entity.resolveSymbolicLinksSync().replaceAll('\\', '/');
  } on Object {
    return entity.absolute.path.replaceAll('\\', '/');
  }
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final base = _canonicalPath(root).replaceFirst(RegExp(r'/$'), '');
  final value = entity.absolute.path.replaceAll('\\', '/');
  if (value == base) return '.';
  if (value.startsWith('$base/')) return value.substring(base.length + 1);
  return value;
}

String _displayPath(Directory root, FileSystemEntity entity) =>
    _relativePath(root, entity);

bool _isWithin(String root, String value) =>
    value == root || value.startsWith('$root/');
