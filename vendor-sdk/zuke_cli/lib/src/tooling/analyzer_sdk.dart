import 'dart:io';

import 'package:path/path.dart' as path;

/// Resolves the SDK used by analyzer-backed tooling.
///
/// Analyzer normally derives this from [Platform.resolvedExecutable]. That is
/// correct for `dart`, but not for a compiled Zuke executable. The explicit
/// resolution keeps generated/extraction commands deterministic in both forms
/// without mutating or installing an SDK.
String? resolveAnalyzerSdkPath() {
  final environment = Platform.environment;
  for (final key in const ['ZUKE_DART_SDK', 'DART_SDK']) {
    final configured = environment[key];
    if (configured != null && _isDartSdk(configured)) {
      return path.normalize(File(configured).absolute.path);
    }
  }

  final flutterRoot = environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final candidate = path.join(flutterRoot, 'bin', 'cache', 'dart-sdk');
    if (_isDartSdk(candidate)) return path.normalize(candidate);
  }

  final executable = File(Platform.resolvedExecutable).absolute;
  final executableParent = executable.parent;
  if (path.basename(executableParent.path).toLowerCase() == 'bin') {
    final candidate = executableParent.parent.path;
    if (_isDartSdk(candidate)) return path.normalize(candidate);
  }

  return null;
}

bool _isDartSdk(String candidate) {
  final sdk = Directory(candidate).absolute;
  return Directory(path.join(sdk.path, 'lib')).existsSync() &&
      Directory(path.join(sdk.path, 'lib', '_internal')).existsSync();
}

/// The SDK executable, including when Zuke itself is an AOT executable.
String resolveDartExecutable() {
  final sdk = resolveAnalyzerSdkPath();
  if (sdk == null) {
    throw StateError(
      'Cannot locate Dart SDK. Set ZUKE_DART_SDK to the SDK directory.',
    );
  }
  final executable = path.join(
    sdk,
    'bin',
    Platform.isWindows ? 'dart.exe' : 'dart',
  );
  if (!File(executable).existsSync()) {
    throw FileSystemException('Dart SDK executable is missing', executable);
  }
  return executable;
}
