/// Location convention for the manifest Zuke writes with generated contracts.
///
/// Generation, stale-file cleanup, and the source digest all have to agree on
/// this path; keeping the derivation in one place stops a package-layout change
/// from silently orphaning a manifest.
library;

/// Workspace-relative directory that owns the `.zuke-generated.json` manifest
/// for [outputDir].
///
/// The root package keeps its manifest in `lib/src` for compatibility, while
/// a nested package such as `packages/calculator_contracts` keeps it at that
/// package's root.
String generatedManifestDirectory(String outputDir) {
  final normalizedOutput = outputDir.replaceAll('\\', '/');
  final libIndex = normalizedOutput.indexOf('/lib/');
  return libIndex > 0
      ? normalizedOutput.substring(0, libIndex)
      : normalizedOutput.split('/').take(2).join('/');
}

/// The `.zuke-generated.json` path for [outputDir], rooted at [root].
///
/// The result is absolute when [root] is; callers that pass a relative root
/// get a relative path.
String generatedManifestPath(String root, String outputDir) =>
    '$root/${generatedManifestDirectory(outputDir)}/.zuke-generated.json';
