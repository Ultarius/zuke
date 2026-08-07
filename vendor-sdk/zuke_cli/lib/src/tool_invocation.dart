import 'dart:io';

/// A fully prepared child-process invocation.
///
/// Analytics suppression is intentionally an invocation concern: it prevents
/// the SDK from trying to persist telemetry state in a caller's profile while
/// leaving that profile and its ACLs untouched.
final class ToolInvocation {
  const ToolInvocation({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

/// A stable, coded failure while preparing a configured tool invocation.
final class ToolInvocationException implements Exception {
  const ToolInvocationException({
    required this.diagnosticCode,
    required this.message,
  });

  final String diagnosticCode;
  final String message;

  @override
  String toString() => '$diagnosticCode: $message';
}

typedef FlutterExecutableLookup = String? Function();

/// Probes whether Flutter can open the cache lockfile required for a launch.
typedef FlutterCacheAccessProbe = void Function(String lockfilePath);

enum ToolRunnerMode { auto, cli, directSnapshot }

/// Applies SDK-safe, non-persistent environment defaults to a tool launch.
///
/// Both Dart and Flutter accept the global `--suppress-analytics` option only
/// before the subcommand. Flutter also honours this environment value in
/// subprocesses that do not inherit the command-line option.
///
/// On Windows, when the logical tool is `flutter`, the generic preparation is
/// replaced by [FlutterToolchainResolver] which bypasses the batch launcher
/// and invokes the Flutter tool snapshot through the cached Dart SDK directly.
ToolInvocation prepareToolInvocation(
  String executable,
  List<String> arguments,
  Map<String, String> environment, {
  FlutterToolchainResolver? flutterResolver,
  ToolRunnerMode runnerMode = ToolRunnerMode.auto,
}) {
  final tool = _toolName(executable);
  if (runnerMode == ToolRunnerMode.directSnapshot && tool != 'flutter') {
    throw const ToolInvocationException(
      diagnosticCode: 'ZUKE-FLUTTER-RUNNER-MODE-INVALID',
      message: 'directSnapshot is only supported for Flutter runners.',
    );
  }
  final preparedArguments = List<String>.from(arguments);
  final preparedEnvironment = Map<String, String>.from(environment);

  final useSnapshot =
      tool == 'flutter' &&
      (runnerMode == ToolRunnerMode.directSnapshot ||
          (runnerMode == ToolRunnerMode.auto && Platform.isWindows));
  if (useSnapshot) {
    final resolver = flutterResolver ?? const FlutterToolchainResolver();
    return resolver.resolve(executable, preparedArguments, preparedEnvironment);
  }

  if ((tool == 'dart' || tool == 'flutter') &&
      !preparedArguments.contains('--suppress-analytics')) {
    preparedArguments.insert(0, '--suppress-analytics');
  }
  if (tool == 'dart' &&
      preparedArguments.length > 1 &&
      preparedArguments[1].toLowerCase().endsWith('.dart')) {
    preparedArguments.insert(1, 'run');
  }
  if (tool == 'flutter') {
    preparedEnvironment['FLUTTER_SUPPRESS_ANALYTICS'] = 'true';
  }

  return ToolInvocation(
    executable: executable,
    arguments: List<String>.unmodifiable(preparedArguments),
    environment: Map<String, String>.unmodifiable(preparedEnvironment),
  );
}

/// Whether [executable] names Flutter's supported command-line launcher.
bool isFlutterTool(String executable) => _toolName(executable) == 'flutter';

/// Resolves a Windows Flutter runner to a direct snapshot invocation.
///
/// Bypasses [flutter.bat] and invokes [flutter_tools.snapshot] through the
/// cached Dart SDK, avoiding batch-file argument parsing and exposing
/// cache/bootstrap failures through captured child streams. The SDK must
/// already be prepared and writable; Flutter's own startup lock still applies.
final class FlutterToolchainResolver {
  const FlutterToolchainResolver({
    this.executableLookup,
    this.cacheAccessProbe,
  });

  final FlutterExecutableLookup? executableLookup;
  final FlutterCacheAccessProbe? cacheAccessProbe;

  ToolInvocation resolve(
    String originalExecutable,
    List<String> originalArguments,
    Map<String, String> environment,
  ) {
    final flutterRoot = _resolveFlutterRoot(environment, originalExecutable);
    final dartExeName = Platform.isWindows ? 'dart.exe' : 'dart';
    final dartExe = _joinPath([
      flutterRoot,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      dartExeName,
    ]);
    final snapshot = _joinPath([
      flutterRoot,
      'bin',
      'cache',
      'flutter_tools.snapshot',
    ]);
    final packageConfig = _joinPath([
      flutterRoot,
      'packages',
      'flutter_tools',
      '.dart_tool',
      'package_config.json',
    ]);

    final missing = <String>[];
    if (!File(dartExe).existsSync()) {
      missing.add(dartExe);
    }
    if (!File(snapshot).existsSync()) {
      missing.add(snapshot);
    }
    if (!File(packageConfig).existsSync()) {
      missing.add(packageConfig);
    }
    if (missing.isNotEmpty) {
      throw ToolInvocationException(
        diagnosticCode: 'ZUKE-FLUTTER-CACHE-INCOMPLETE',
        message:
            'Flutter\'s cached tool snapshot is not ready.\n'
            '\n'
            '  Flutter SDK: $flutterRoot\n'
            '  Missing:\n'
            '${missing.map((path) => '    $path').join('\n')}\n'
            '\n'
            'Run:\n'
            '  flutter doctor\n'
            '  flutter precache\n'
            '  flutter pub get',
      );
    }

    final lockfile = _joinPath([flutterRoot, 'bin', 'cache', 'lockfile']);
    try {
      (cacheAccessProbe ?? _verifyCacheLockfileWritable)(lockfile);
    } on FileSystemException catch (error) {
      throw ToolInvocationException(
        diagnosticCode: 'ZUKE-FLUTTER-CACHE-UNWRITABLE',
        message:
            'Flutter\'s prepared SDK cache cannot be opened for a '
            'shell-free launch.\n'
            '\n'
            '  Flutter SDK: $flutterRoot\n'
            '  Cache lockfile: $lockfile\n'
            '\n'
            'Use a prepared Flutter SDK whose bin/cache directory is '
            'writable by the process running Zuke. Set FLUTTER_ROOT '
            'to that SDK, or grant the runner access to this cache.\n'
            '\n'
            'Underlying error: ${error.message}',
      );
    }

    final toolArgs = environment['FLUTTER_TOOL_ARGS'];
    if (toolArgs != null && toolArgs.trim().isNotEmpty) {
      throw const ToolInvocationException(
        diagnosticCode: 'ZUKE-FLUTTER-TOOL-ARGS-UNSUPPORTED',
        message:
            'FLUTTER_TOOL_ARGS cannot be represented safely by the '
            'shell-free Flutter runner. Unset FLUTTER_TOOL_ARGS and express '
            'supported runner options in the configured args list.',
      );
    }

    final resolvedArguments = <String>['--packages=$packageConfig', snapshot];
    if (!originalArguments.contains('--suppress-analytics')) {
      resolvedArguments.add('--suppress-analytics');
    }
    resolvedArguments.addAll(originalArguments);

    final resolvedEnvironment = Map<String, String>.from(environment)
      ..['FLUTTER_ROOT'] = flutterRoot
      ..['FLUTTER_SUPPRESS_ANALYTICS'] = 'true';

    return ToolInvocation(
      executable: dartExe,
      arguments: List<String>.unmodifiable(resolvedArguments),
      environment: Map<String, String>.unmodifiable(resolvedEnvironment),
    );
  }

  static void _verifyCacheLockfileWritable(String lockfilePath) {
    final lockfile = File(lockfilePath);
    RandomAccessFile? handle;
    try {
      // Append preserves the existing zero-byte lockfile while exercising the
      // same open-for-write permission Flutter requires before locking it.
      handle = lockfile.openSync(mode: FileMode.append);
    } finally {
      handle?.closeSync();
    }
  }

  String _resolveFlutterRoot(
    Map<String, String> environment,
    String executable,
  ) {
    if (_isExplicitExecutable(executable)) {
      final resolved = _resolveFromExecutable(executable);
      if (resolved != null) return resolved;
      throw ToolInvocationException(
        diagnosticCode: 'ZUKE-FLUTTER-NOT-FOUND',
        message:
            'The configured Flutter executable does not identify a valid '
            'Flutter SDK.\n'
            '  Executable: ${File(executable).absolute.path}',
      );
    }

    final envRoot = environment['FLUTTER_ROOT'];
    if (envRoot != null && envRoot.trim().isNotEmpty) {
      return _normalizeRoot(envRoot, source: 'FLUTTER_ROOT');
    }

    final resolved = _resolveFromExecutable(executable);
    if (resolved != null) return resolved;

    final where = _whereFlutter();
    if (where != null) return where;

    throw const ToolInvocationException(
      diagnosticCode: 'ZUKE-FLUTTER-NOT-FOUND',
      message:
          'Could not resolve a Flutter SDK root to obtain the cached '
          'toolchain.\n'
          '  Set FLUTTER_ROOT or ensure flutter is on PATH.',
    );
  }

  String? _resolveFromExecutable(String executable) {
    final file = File(executable).absolute;
    if (!file.existsSync() || !isFlutterTool(file.path)) return null;
    final canonical = File(file.resolveSymbolicLinksSync());
    final bin = canonical.parent;
    if (_basename(bin.path).toLowerCase() != 'bin') return null;
    return _normalizeRoot(
      bin.parent.path,
      source: 'Flutter executable ${canonical.path}',
    );
  }

  bool _isExplicitExecutable(String executable) {
    final normalized = executable.replaceAll('\\', '/');
    return File(executable).isAbsolute ||
        normalized.contains('/') ||
        normalized.contains(':');
  }

  String? _whereFlutter() {
    try {
      final executable = executableLookup?.call() ?? _lookupFlutterOnPath();
      if (executable == null || executable.trim().isEmpty) return null;
      return _resolveFromExecutable(executable.trim());
    } on FileSystemException {
      return null;
    } on ProcessException {
      return null;
    }
  }

  String? _lookupFlutterOnPath() {
    final command = Platform.isWindows ? 'where.exe' : 'which';
    final result = Process.runSync(command, ['flutter']);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final candidate = line.trim();
      if (candidate.isNotEmpty && isFlutterTool(candidate)) return candidate;
    }
    return null;
  }

  String _normalizeRoot(String value, {required String source}) {
    final trimmed = value.trim();
    final directory = Directory(trimmed).absolute;
    if (!directory.existsSync()) {
      throw ToolInvocationException(
        diagnosticCode: 'ZUKE-FLUTTER-NOT-FOUND',
        message:
            '$source does not identify an existing Flutter SDK directory.\n'
            '  Resolved path: ${directory.path}',
      );
    }
    try {
      return directory.resolveSymbolicLinksSync();
    } on FileSystemException {
      return directory.path;
    }
  }
}

String _joinPath(List<String> components) =>
    components.join(Platform.pathSeparator);

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _toolName(String executable) {
  final lower = _basename(executable).toLowerCase();
  if (lower.endsWith('.exe') ||
      lower.endsWith('.bat') ||
      lower.endsWith('.cmd')) {
    return lower.substring(0, lower.lastIndexOf('.'));
  }
  return lower;
}

/// The Dart command descriptor used by tests that spawn the CLI. It resolves
/// the SDK driving the test before falling back to PATH, and always keeps the
/// non-persistent analytics option before the Dart subcommand.
final class TestDartCommand {
  const TestDartCommand(this.executable);

  final String executable;

  List<String> arguments(Iterable<String> commandArguments) {
    final result = List<String>.from(commandArguments);
    if (!result.contains('--suppress-analytics')) {
      result.insert(0, '--suppress-analytics');
    }
    // `dart <script.dart>` is a legacy shorthand. Once a global option is
    // present, make the command explicit so the option is parsed by the Dart
    // tool rather than forwarded to the VM that runs the script.
    if (result.length > 1 && result[1].toLowerCase().endsWith('.dart')) {
      result.insert(1, 'run');
    }
    return result;
  }

  Future<ProcessResult> run(
    List<String> commandArguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.run(
    executable,
    arguments(commandArguments),
    workingDirectory: workingDirectory,
    environment: environment,
  );

  Future<Process> start(
    List<String> commandArguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.start(
    executable,
    arguments(commandArguments),
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

TestDartCommand resolveTestDartCommand() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final candidates = <String>[];
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add(
      '$flutterRoot${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}$executableName',
    );
  }

  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 10; depth++) {
    candidates.add(
      '${directory.path}${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}$executableName',
    );
    candidates.add(
      '${directory.path}${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}$executableName',
    );
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return TestDartCommand(File(candidate).absolute.path);
    }
  }
  if (Platform.isWindows) {
    final where = Process.runSync('where.exe', ['dart.exe']);
    if (where.exitCode == 0) {
      final path = where.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
      if (path.isNotEmpty) return TestDartCommand(path);
    }
  }
  return const TestDartCommand('dart');
}
