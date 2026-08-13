import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

const _defaultTrustBundle = 'assurance-history/trust/ed25519.json';

File configuredTrustBundle(String root, {String? configuredPath}) {
  final relativePath = configuredPath ?? _trustBundlePathFromConfig(root);
  if (File(relativePath).isAbsolute) {
    throw FormatException('Trust bundle path must be workspace-relative');
  }
  final workspace = Directory(root).absolute;
  final candidate = File(
    workspace.uri.resolve(relativePath).toFilePath(),
  ).absolute;
  final normalizedRoot = workspace.path.replaceAll('\\', '/');
  final normalizedCandidate = candidate.path.replaceAll('\\', '/');
  if (normalizedCandidate != normalizedRoot &&
      !normalizedCandidate.startsWith('$normalizedRoot/')) {
    throw FormatException('Trust bundle must stay inside the workspace');
  }
  return candidate;
}

String _trustBundlePathFromConfig(String root) {
  final configFile = File('${Directory(root).absolute.path}/zuke.yaml');
  if (!configFile.existsSync()) return _defaultTrustBundle;
  try {
    return ZukeConfig.fromYaml(
          configFile.readAsStringSync(),
          root: root,
        ).trustBundle ??
        _defaultTrustBundle;
  } on WorkspaceConfigError catch (error) {
    throw FormatException(
      'Current workspace configuration is invalid: ${error.message}',
    );
  }
}

TrustBundle loadTrustBundle(String root, {String? configuredPath}) {
  final file = configuredTrustBundle(root, configuredPath: configuredPath);
  if (!file.existsSync()) {
    throw StateError('Missing Ed25519 trust metadata: ${file.path}');
  }
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map) {
    throw const FormatException('Invalid Ed25519 trust metadata');
  }
  return TrustBundle.fromJson(value);
}

TrustBundle loadWorkspaceTrustBundle(WorkspaceDiscoveryResult workspace) =>
    loadTrustBundle(
      workspace.config.root!,
      configuredPath: workspace.config.trustBundle,
    );
