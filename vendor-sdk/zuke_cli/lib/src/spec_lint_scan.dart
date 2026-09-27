import 'package:zuke_frontend/zuke_frontend.dart';

import 'proof_engine/reference_resolver.dart';
import 'proof_engine/validator.dart';
import 'tooling/dart_extractor/zuke_index.dart';

/// Specification findings, ready to be recorded in the analyzer index.
///
/// The reference resolver is what finds a `.feature` problem, but the editor
/// only reads the index, and an analysis-server plugin can only anchor a
/// diagnostic on a Dart node. Recording the findings in the index is what
/// bridges the two.
///
/// A finding is attributed to a feature by the specification file it points at,
/// never by its message. The resolver already records the `SourceLocation` of the
/// feature or rule that caused it, and the workspace knows which feature each
/// `.feature` file declares. Reading the ID out of the message would couple the
/// editor to prose that is free to change.
///
/// [root] must be the absolute workspace root: the resolver records absolute
/// specification paths, and the index stores workspace-relative ones so a
/// checkout at a different path produces the same index.
List<ZukeSpecDiagnostic> scanSpecDiagnostics(
  WorkspaceDiscoveryResult workspace, {
  required String root,
}) {
  final featuresBySpecFile = <String, String>{};
  for (final feature in workspace.data.features) {
    final id = feature.metadata.id;
    final file = feature.metadata.source.file;
    if (id == null || id.isEmpty || file.isEmpty) continue;
    final specPath = _specPath(root, file);
    if (specPath == null) continue;
    // A spec file may declare more than one feature. Attribute to the first so a
    // finding is reported once, and so the choice does not depend on iteration
    // order.
    featuresBySpecFile.putIfAbsent(specPath, () => id);
  }
  if (featuresBySpecFile.isEmpty) return const [];

  final result = ReferenceResolver().validate(workspace);
  final diagnostics = <ZukeSpecDiagnostic>[];
  for (final message in <ValidationMessage>[
    ...result.errors,
    ...result.warnings,
    ...result.infos,
  ]) {
    final location = message.source;
    if (location is! SourceLocation) continue;
    final specPath = _specPath(root, location.file);
    if (specPath == null) continue;
    // Only findings inside a parsed feature are actionable here. A finding about
    // zuke.yaml, or one the frontend could not locate, has no feature to anchor
    // to and remains a CLI concern.
    final featureId = featuresBySpecFile[specPath];
    if (featureId == null) continue;
    diagnostics.add(
      ZukeSpecDiagnostic(
        file: specPath,
        line: location.line < 1 ? 1 : location.line,
        column: location.column < 0 ? 0 : location.column,
        code: message.code,
        severity: switch (message.severity) {
          Severity.warning => 'warning',
          Severity.info => 'info',
          Severity.error => 'error',
        },
        message: message.message,
        featureId: featureId,
      ),
    );
  }
  return diagnostics;
}

/// A specification path as workspace-relative and forward-slashed, or null when
/// it cannot be expressed that way.
///
/// Never returns an absolute path. An absolute path recorded in the index makes
/// the index's digest differ per machine, so `zuke generate --check` fails in a
/// different checkout, and it leaks a local directory into an editor message. A
/// path outside the workspace is therefore dropped rather than guessed at.
String? _specPath(String root, String file) {
  final path = file.replaceAll('\\', '/');
  final looksAbsolute =
      path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path);
  if (!looksAbsolute) {
    // Already workspace-relative. Stripping a leading `./` cannot make it leak
    // anything, and a parser handed a relative path is a legitimate caller.
    var relative = path;
    while (relative.startsWith('./')) {
      relative = relative.substring(2);
    }
    return relative.isEmpty ? null : relative;
  }
  return ZukeIndex.relativeToRoot(root, path);
}
