import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zuke_frontend/zuke_frontend.dart';

import '../path_safety.dart';

const defaultContractOutput = 'lib/src/generated';

/// Workspace-relative Dart source roots included in the annotation scans.
///
/// The analyzer index stores these roots with its source-file inventory so it
/// can notice a new Dart file before generation refreshes that inventory.
List<String> workspaceDartSourceRoots(WorkspaceDiscoveryResult workspace) {
  final roots = <String>{};
  for (final target in workspace.config.workspaceTargets.values) {
    if (target.language != 'dart') continue;
    for (final package in target.packages) {
      // The root package normalizes to `.`, which is not a directory prefix to
      // join onto; an empty path is what makes the bare source root work here.
      final packagePath = normalizePackagePath(package.path);
      for (final packageRoot in package.roots) {
        final relativeRoot = packageRoot.replaceAll('\\', '/').trim();
        final joined = [
          if (packagePath.isNotEmpty && packagePath != '.') packagePath,
          relativeRoot,
        ].where((part) => part.isNotEmpty).join('/');
        if (joined.isNotEmpty) roots.add(normalizeRelativePath(joined));
      }
    }
  }
  return roots.toList()..sort();
}

/// Every Dart source file under the configured package roots, in a stable
/// order so collected constants do not depend on directory iteration.
///
/// Applies the same source-selection policy as extraction: documentation
/// fixtures under `test/guide_snippets/` restate annotated code in prose and
/// are not code. Counting them would let a snippet in the guide satisfy coverage
/// for a requirement nothing implements.
///
/// [pendingContent] contributes files that exist only in memory. Generated
/// contracts usually sit under a package root, so without this a first
/// generation would index fewer sources than the run after it.
Iterable<File> packageDartFiles(
  String root,
  WorkspaceDiscoveryResult workspace, {
  Map<String, String> pendingContent = const {},
}) sync* {
  final files = <String>{};
  for (final relativeRoot in workspaceDartSourceRoots(workspace)) {
    final directory = Directory(p.normalize(p.join(root, relativeRoot)));
    if (directory.existsSync()) {
      files.addAll(
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => p.normalize(file.absolute.path)),
      );
    }
    for (final path in pendingContent.keys) {
      final normalized = p.normalize(File(path).absolute.path);
      if (p.isWithin(directory.path, normalized)) files.add(normalized);
    }
  }
  for (final path in files.toList()..sort()) {
    if (path.endsWith('.dart') && !isGuideSnippetFixture(path)) {
      yield File(path);
    }
  }
}

/// Whether [file] is generated rather than hand-maintained source.
///
/// Generated files declare identifiers; they never implement them, so a scan
/// for implementations must skip them or every requirement would look covered.
bool isGeneratedSource(File file) =>
    file.path.endsWith('.g.dart') || file.path.endsWith('.freezed.dart');
