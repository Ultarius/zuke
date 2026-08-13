import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:zuke_cli/tooling.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'generator.dart';
import 'configuration_preflight.dart';

class GenerateCommand {
  final ArgResults args;

  GenerateCommand(this.args);

  Future<int> execute() async {
    final requestedRoot = args['root'] as String? ?? Directory.current.path;
    final root = Directory(requestedRoot).absolute.path;
    final checkOnly = args['check'] as bool? ?? false;
    final quiet = args['quiet'] as bool? ?? false;

    void info(String message) {
      if (!quiet) stdout.writeln(message);
    }

    info('${checkOnly ? "Checking" : "Generating"} contracts...');

    final workspace = requireCurrentWorkspace(root);

    final generator = DartContractGenerator();
    final configuredOutput =
        workspace.config.contractOutput ?? 'lib/src/generated';
    final outputDir = args['output'] as String? ?? configuredOutput;
    final result = generator.generate(
      workspace: workspace,
      outputDir: outputDir,
      exportPath: workspace.config.contractExport,
    );

    if (result.errors.isNotEmpty) {
      for (final err in result.errors) {
        stderr.writeln('  ERROR: $err');
      }
      return 1;
    }

    var allMatch = result.errors.isEmpty;
    final expectedPaths = result.files
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
    final generatedDir = Directory('$root/${outputDir.replaceAll('\\', '/')}');
    final normalizedOutput = outputDir.replaceAll('\\', '/');
    final libIndex = normalizedOutput.indexOf('/lib/');
    final packageDir = libIndex > 0
        ? normalizedOutput.substring(0, libIndex)
        : normalizedOutput.split('/').take(2).join('/');
    final manifestPath = '$root/$packageDir/.zuke-generated.json';
    final indexPath = '$root/.zuke/analyzer-index.json';
    final packageLibDir = Directory('$root/$packageDir/lib');
    final generatedStepRoots = _generatedStepRoots(root, workspace);
    final expectedManifest = result.manifest.toJson();
    final expectedIndex = _buildAnalyzerIndex(
      root: root,
      workspace: workspace,
      generatedManifestContent: expectedManifest,
      generatedManifestPath: _relativeToRoot(root, manifestPath),
    );
    final expectedIndexContent =
        const JsonEncoder.withIndent('  ').convert(expectedIndex.toJson()) +
        '\n';
    final manifestFile = File(manifestPath);
    final previousPaths = _previousManifestPaths(
      manifestFile,
      root: root,
      generatedDir: generatedDir,
      packageLibDir: packageLibDir,
      generatedStepRoots: generatedStepRoots,
    );
    final stalePaths = previousPaths.difference(expectedPaths).toList()..sort();
    final writes = <String, String>{};
    final deletions = <String>[];
    var staleCount = 0;

    for (final file in result.files) {
      final diskFile = _confinedGeneratedFile(
        root: root,
        generatedDir: generatedDir,
        packageLibDir: packageLibDir,
        generatedStepRoots: generatedStepRoots,
        relativePath: file.path,
      );
      final exists = diskFile.existsSync();
      final contentMatch =
          exists && diskFile.readAsStringSync() == file.content;

      if (checkOnly) {
        if (!exists) {
          stderr.writeln('  MISSING: ${file.path}');
          allMatch = false;
          staleCount++;
        } else if (!contentMatch) {
          stderr.writeln('  STALE: ${file.path}');
          allMatch = false;
          staleCount++;
        } else {
          info('  OK: ${file.path}');
        }
      } else {
        if (exists && !contentMatch && !_isGenerated(diskFile)) {
          stderr.writeln('  REFUSED HANDWRITTEN FILE: ${file.path}');
          return 1;
        }
        if (!exists || !contentMatch) {
          writes[diskFile.path] = file.content;
        }
      }
    }

    for (final path in stalePaths) {
      final file = _confinedGeneratedFile(
        root: root,
        generatedDir: generatedDir,
        packageLibDir: packageLibDir,
        generatedStepRoots: generatedStepRoots,
        relativePath: path,
      );
      if (checkOnly) {
        stderr.writeln('  STALE MANIFEST ENTRY: $path');
        allMatch = false;
        staleCount++;
      } else if (file.existsSync()) {
        if (!_isGenerated(file)) {
          stderr.writeln('  REFUSED HANDWRITTEN STALE FILE: $path');
          return 1;
        }
        deletions.add(file.path);
      }
    }

    if (checkOnly) {
      if (!manifestFile.existsSync() ||
          manifestFile.readAsStringSync() != expectedManifest) {
        stderr.writeln('  STALE: $packageDir/.zuke-generated.json');
        allMatch = false;
        staleCount++;
      } else {
        info('  OK: $packageDir/.zuke-generated.json');
      }
      final indexFile = File(indexPath);
      if (!indexFile.existsSync() ||
          indexFile.readAsStringSync() != expectedIndexContent) {
        stderr.writeln('  STALE: .zuke/analyzer-index.json');
        allMatch = false;
        staleCount++;
      } else {
        info('  OK: .zuke/analyzer-index.json');
      }
    } else {
      if (!manifestFile.existsSync() ||
          manifestFile.readAsStringSync() != expectedManifest) {
        writes[manifestFile.path] = expectedManifest;
      }
      final indexFile = File(indexPath);
      if (!indexFile.existsSync() ||
          indexFile.readAsStringSync() != expectedIndexContent) {
        writes[indexPath] = expectedIndexContent;
      }
      _applyAtomically(writes: writes, deletions: deletions);
      for (final path in writes.keys) {
        final relative = _relativeToRoot(root, path);
        info('  WROTE: $relative');
      }
      for (final path in deletions) {
        info('  REMOVED STALE: ${_relativeToRoot(root, path)}');
      }
    }
    if (checkOnly) {
      if (allMatch) {
        info('All generated files are current.');
        return 0;
      }
      stderr.writeln(
        'Generated files are stale ($staleCount issue(s)). Run '
        '`dart run zuke_cli:zuke generate --root "$root"` '
        'to update.',
      );
      return 1;
    }

    info('Generated ${result.files.length} file(s).');
    return 0;
  }

  ZukeIndex _buildAnalyzerIndex({
    required String root,
    required WorkspaceDiscoveryResult workspace,
    required String generatedManifestContent,
    required String generatedManifestPath,
  }) {
    final inputs = <String>{...workspace.inputContents.keys};
    final requirements = <String>{};
    final bindings = <String>{};
    for (final feature in workspace.data.features) {
      _collectMetadataIds(feature.metadata, requirements, bindings);
      for (final rule in feature.rules) {
        _collectMetadataIds(rule.metadata, requirements, bindings);
      }
    }
    return ZukeIndex.create(
      root: root,
      inputPaths: inputs,
      generatedManifestContent: generatedManifestContent,
      generatedManifestPath: generatedManifestPath,
      requirementIds: requirements,
      controlIds: workspace.data.controls.keys,
      bindingIds: bindings,
      inputPatterns: workspace.inputPatterns,
      patternInputPaths: workspace.patternInputPaths,
      inputContents: workspace.inputContents,
    );
  }

  void _collectMetadataIds(
    ParsedMetadata metadata,
    Set<String> requirements,
    Set<String> bindings,
  ) {
    final id = metadata.id;
    if (id != null && id.isNotEmpty) requirements.add(id);
    for (final binding in metadata.bindings ?? const <ParsedBinding>[]) {
      bindings.add(binding.id);
    }
  }

  Set<String> _previousManifestPaths(
    File manifestFile, {
    required String root,
    required Directory generatedDir,
    required Directory packageLibDir,
    required List<Directory> generatedStepRoots,
  }) {
    if (!manifestFile.existsSync()) return <String>{};
    try {
      final decoded = jsonDecode(manifestFile.readAsStringSync());
      if (decoded is! Map || decoded['files'] is! List) {
        throw const FormatException('manifest root must contain files');
      }
      final paths = <String>{};
      for (final entry in decoded['files'] as List) {
        if (entry is! Map || entry['path'] is! String) {
          throw const FormatException('manifest file entry is invalid');
        }
        final path = (entry['path'] as String).replaceAll('\\', '/');
        _confinedGeneratedFile(
          root: root,
          generatedDir: generatedDir,
          packageLibDir: packageLibDir,
          generatedStepRoots: generatedStepRoots,
          relativePath: path,
        );
        paths.add(path);
      }
      return paths;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid generated manifest: $error');
    }
  }

  File _confinedGeneratedFile({
    required String root,
    required Directory generatedDir,
    required Directory packageLibDir,
    required List<Directory> generatedStepRoots,
    required String relativePath,
  }) {
    if (File(relativePath).isAbsolute) {
      throw FormatException('Generated path must be workspace-relative');
    }
    final workspace = Directory(root).absolute;
    final file = File(
      '${workspace.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    ).absolute;
    final generated = generatedDir.absolute.path.replaceAll('\\', '/');
    final packageLib = packageLibDir.absolute.path.replaceAll('\\', '/');
    final supportRoots = generatedStepRoots.map(
      (directory) => directory.absolute.path.replaceAll('\\', '/'),
    );
    final candidate = file.path.replaceAll('\\', '/');
    if (!candidate.startsWith('$generated/') &&
        !candidate.startsWith('$packageLib/') &&
        !supportRoots.any(
          (supportRoot) => candidate.startsWith('$supportRoot/'),
        )) {
      throw FormatException(
        'Generated path escapes the configured contract package: $relativePath',
      );
    }
    return file;
  }

  List<Directory> _generatedStepRoots(
    String root,
    WorkspaceDiscoveryResult workspace,
  ) {
    final runners = workspace.config.executionConfig['runners'];
    if (runners is! List) return const [];
    return [
      for (final runner in runners)
        if (runner is Map && runner['generatedStepsOutput'] is String)
          Directory('$root/${runner['generatedStepsOutput'] as String}'),
    ];
  }

  bool _isGenerated(File file) =>
      file.readAsStringSync().startsWith('// GENERATED. DO NOT EDIT.');

  String _relativeToRoot(String root, String path) {
    final normalizedRoot = Directory(root).absolute.path.replaceAll('\\', '/');
    final normalizedPath = path.replaceAll('\\', '/');
    return normalizedPath.startsWith('$normalizedRoot/')
        ? normalizedPath.substring(normalizedRoot.length + 1)
        : normalizedPath;
  }

  void _applyAtomically({
    required Map<String, String> writes,
    required List<String> deletions,
  }) {
    final runId = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final temporary = <String, String>{};
    final backups = <String, String>{};
    final committedWrites = <String>[];
    try {
      for (final entry in writes.entries) {
        final destination = File(entry.key);
        destination.parent.createSync(recursive: true);
        final tempPath = '${destination.path}.zuke-tmp-$runId';
        File(tempPath).writeAsStringSync(entry.value, flush: true);
        temporary[destination.path] = tempPath;
      }
      for (final path in {...writes.keys, ...deletions}) {
        final destination = File(path);
        if (!destination.existsSync()) continue;
        final backupPath = '${destination.path}.zuke-backup-$runId';
        destination.renameSync(backupPath);
        backups[path] = backupPath;
      }
      for (final entry in temporary.entries) {
        File(entry.value).renameSync(entry.key);
        committedWrites.add(entry.key);
      }
      for (final backup in backups.values) {
        final file = File(backup);
        if (file.existsSync()) file.deleteSync();
      }
    } catch (_) {
      for (final path in committedWrites) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      for (final entry in backups.entries) {
        final backup = File(entry.value);
        if (backup.existsSync()) backup.renameSync(entry.key);
      }
      rethrow;
    } finally {
      for (final path in temporary.values) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    }
  }
}
