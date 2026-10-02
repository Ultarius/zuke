/// Supported application-facing specification parsing API.
library;

export 'src/discovery.dart';
export 'src/config_models.dart';
export 'src/gherkin_parser.dart';
export 'src/gherkin_syntax.dart';
export 'src/metadata_extractor.dart';
export 'src/types.dart';

// Workspace path handling lives here rather than in the CLI so that
// configuration parsing and every later consumer of a normalized package path
// cannot drift apart. The CLI's `path_safety.dart` re-exports these.
export 'src/workspace_paths.dart'
    show
        WorkspacePackageClaim,
        WorkspacePackageOwnership,
        normalizePackagePath,
        normalizeRelativePath,
        pathComparisonKey;
