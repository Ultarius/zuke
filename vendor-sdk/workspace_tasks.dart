import 'dart:async';
import 'dart:convert';
import 'dart:io';

// A package may run longer than five minutes under coverage; only a silent
// child is considered stalled.
const _packageIdleTimeout = Duration(minutes: 5);

/// Schedules independent Dart workspace packages without relying on Melos to
/// launch nested `dart` processes.  This keeps the total test isolate count
/// bounded on small CI machines and makes each child use the same SDK as this
/// script.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || !{'test', 'analyze'}.contains(arguments.first)) {
    stderr.writeln('Usage: workspace_tasks.dart <test|analyze> [arguments...]');
    exitCode = 64;
    return;
  }
  final task = arguments.first;
  final extra = arguments.skip(1).toList();
  // The regular test command leaves Calculator API scenarios to their
  // Zuke runner, which supplies the evidence environment. Coverage is a
  // separate observational pass and must include that package.
  final includeRunnerManaged = extra.remove('--include-runner-managed');
  final rawBudget = Platform.environment['ZUKE_TEST_WORKERS'];
  final rawPackageSlots = Platform.environment['ZUKE_TEST_PACKAGE_SLOTS'];
  late final WorkerBudget budget;
  try {
    budget = WorkerBudget.compute(
      overrideEnv: rawBudget,
      numProcessors: Platform.numberOfProcessors,
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final packages = await _workspacePackages();
  final selected =
      packages
          .where((package) => !package.isFlutter)
          .where((package) => task != 'test' || package.hasTests)
          // Calculator API scenarios are exercised by its configured
          // Zuke runner with the evidence environment.
          .where(
            (package) =>
                task != 'test' ||
                includeRunnerManaged ||
                !package.path
                    .replaceAll('\\', '/')
                    .endsWith(
                      '/examples/calculator-product/apps/calculator_api',
                    ),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (selected.isEmpty) return;

  late final int packageSlots;
  try {
    packageSlots = budget.packageSlotsFor(
      selected.length,
      overrideEnv: rawPackageSlots,
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final workers = task == 'test' ? budget.workersFor(packageSlots) : 1;
  // CI needs live package progress so a long analyzer/test phase is
  // distinguishable from a stalled child. Local runs keep the compact report.
  final streamOutput = Platform.environment['CI']?.toLowerCase() == 'true';
  stdout.writeln(
    'Dart $task worker budget: ${budget.budget} '
    '(packages=$packageSlots, workers/package=$workers).',
  );
  final results = await _runBounded(
    selected,
    jobs: packageSlots,
    run: (package) =>
        _runPackage(package, task: task, workers: workers, extra: extra),
  );
  // Passing tests may intentionally exercise negative CLI paths. Those paths
  // report their diagnostics on stderr, but surfacing that stream as a
  // warning makes a green workspace run look failed. Keep successful package
  // output quiet by default; set ZUKE_SHOW_TEST_STDERR=true when
  // investigating a package-level test run. Failed packages always retain
  // their stderr so the failure remains actionable.
  final showSuccessfulStderr =
      Platform.environment['ZUKE_SHOW_TEST_STDERR']?.toLowerCase() == 'true';
  var succeeded = true;
  for (final result in results) {
    stdout.writeln(
      '\n[${result.package.path}] ${result.exitCode == 0 ? 'passed' : 'failed'} '
      '(${result.duration.inMilliseconds}ms)',
    );
    if (!streamOutput && result.stdout.isNotEmpty) stdout.write(result.stdout);
    if (result.stderr.isNotEmpty &&
        (result.exitCode != 0 || showSuccessfulStderr)) {
      if (result.exitCode == 0) {
        stdout.writeln('[diagnostic] ${result.package.path} wrote to stderr:');
        stdout.write(result.stderr);
      } else {
        stderr.write(result.stderr);
      }
    }
    if (result.exitCode != 0) succeeded = false;
  }
  if (!succeeded) exitCode = 1;
}

final class WorkerBudget {
  final int budget;

  const WorkerBudget(this.budget);

  factory WorkerBudget.compute({
    required String? overrideEnv,
    required int numProcessors,
  }) {
    if (overrideEnv != null) {
      final parsed = int.tryParse(overrideEnv.trim());
      if (overrideEnv.trim().isEmpty || parsed == null || parsed < 1) {
        throw const FormatException(
          'ZUKE_TEST_WORKERS must be a positive integer.',
        );
      }
      return WorkerBudget(parsed);
    }
    return WorkerBudget(numProcessors < 1 ? 1 : numProcessors);
  }

  int packageSlotsFor(int packageCount, {String? overrideEnv}) {
    final requested = _positiveOverride(
      overrideEnv,
      name: 'ZUKE_TEST_PACKAGE_SLOTS',
    );
    final defaultSlots = packageCount < 4
        ? packageCount
        : (budget < 4 ? budget : 4);
    final selected = requested ?? defaultSlots;
    final capped = selected > packageCount ? packageCount : selected;
    return capped > budget ? budget : capped;
  }

  int workersFor(int packageSlots) {
    if (packageSlots < 1) return 1;
    final result = budget ~/ packageSlots;
    return result < 1 ? 1 : (result > 4 ? 4 : result);
  }

  int? _positiveOverride(String? value, {required String name}) {
    if (value == null) return null;
    final parsed = int.tryParse(value.trim());
    if (value.trim().isEmpty || parsed == null || parsed < 1) {
      throw FormatException('$name must be a positive integer.');
    }
    return parsed;
  }
}

final class _WorkspacePackage {
  final String path;
  final bool isFlutter;
  final bool hasTests;

  const _WorkspacePackage({
    required this.path,
    required this.isFlutter,
    required this.hasTests,
  });
}

final class _PackageResult {
  final _WorkspacePackage package;
  final int exitCode;
  final Duration duration;
  final String stdout;
  final String stderr;

  const _PackageResult({
    required this.package,
    required this.exitCode,
    required this.duration,
    required this.stdout,
    required this.stderr,
  });
}

Future<List<_WorkspacePackage>> _workspacePackages() async {
  final result = await Process.run(Platform.resolvedExecutable, [
    '--disable-dart-dev',
    '--suppress-analytics',
    'pub',
    'workspace',
    'list',
    '--json',
  ]);
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      const ['pub', 'workspace', 'list', '--json'],
      result.stderr.toString(),
      result.exitCode,
    );
  }
  final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final entries = decoded['packages'] as List<Object?>? ?? const [];
  return entries.whereType<Map>().map((entry) {
    final path = entry['path']?.toString();
    if (path == null || path.isEmpty) {
      throw const FormatException('Workspace package entry is missing path.');
    }
    final directory = Directory(path).absolute;
    final pubspec = File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    );
    final content = pubspec.existsSync() ? pubspec.readAsStringSync() : '';
    return _WorkspacePackage(
      path: directory.path,
      isFlutter: RegExp(
        r'^\s*sdk\s*:\s*flutter\s*$',
        multiLine: true,
      ).hasMatch(content),
      hasTests: _hasDartTests(directory),
    );
  }).toList();
}

bool _hasDartTests(Directory package) {
  final directory = Directory('${package.path}${Platform.pathSeparator}test');
  if (!directory.existsSync()) return false;
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .any((file) => file.path.endsWith('_test.dart'));
}

Future<List<_PackageResult>> _runBounded(
  List<_WorkspacePackage> packages, {
  required int jobs,
  required Future<_PackageResult> Function(_WorkspacePackage package) run,
}) async {
  final results = List<_PackageResult?>.filled(packages.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= packages.length) return;
      results[index] = await run(packages[index]);
    }
  }

  await Future.wait(List.generate(jobs, (_) => worker()));
  return results.cast<_PackageResult>();
}

Future<_PackageResult> _runPackage(
  _WorkspacePackage package, {
  required String task,
  required int workers,
  required List<String> extra,
}) async {
  final stopwatch = Stopwatch()..start();
  final command = <String>[
    '--disable-dart-dev',
    '--suppress-analytics',
    task,
    if (task == 'test') ...['-j', '$workers'],
    ...extra,
  ];
  final process = await Process.start(
    Platform.resolvedExecutable,
    command,
    workingDirectory: package.path,
  );
  final streamOutput = Platform.environment['CI']?.toLowerCase() == 'true';
  if (streamOutput) stdout.writeln('\n[${package.path}] started');
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  Timer? idleTimer;
  final idleTimeout = Completer<void>();
  var processExited = false;

  void resetIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(_packageIdleTimeout, () {
      if (!processExited && !idleTimeout.isCompleted) idleTimeout.complete();
    });
  }

  final stdoutSubscription = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(
        (chunk) {
          stdoutBuffer.write(chunk);
          if (streamOutput) stdout.write('[${package.path}] $chunk');
          resetIdleTimer();
        },
        onError: (Object _, StackTrace __) {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );
  final stderrSubscription = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(
        (chunk) {
          stderrBuffer.write(chunk);
          resetIdleTimer();
        },
        onError: (Object _, StackTrace __) {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
        onDone: () {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );
  resetIdleTimer();
  var code = 1;
  var timedOut = false;
  try {
    await Future.any<void>([
      process.exitCode.then<void>((exitCode) {
        processExited = true;
        code = exitCode;
      }),
      idleTimeout.future.then<void>((_) {
        timedOut = true;
      }),
    ]);
    if (timedOut) {
      stderrBuffer.writeln(
        'ZUKE-PACKAGE-TIMEOUT: ${package.path} produced no output for '
        '$_packageIdleTimeout.',
      );
    }
  } finally {
    idleTimer?.cancel();
  }
  if (timedOut) {
    await _terminateTree(process.pid);
  }
  try {
    await Future.wait([
      stdoutDone.future,
      stderrDone.future,
    ]).timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // A descendant may have inherited a pipe after the package was killed.
    // Do not let that pipe keep the workspace runner alive indefinitely.
  }
  try {
    await Future.wait([
      stdoutSubscription.cancel(),
      stderrSubscription.cancel(),
    ]).timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // Cancellation can wait on a pipe inherited by a descendant. The bounded
    // drain above has already retained all output available to the runner.
  }
  stopwatch.stop();
  return _PackageResult(
    package: package,
    exitCode: code,
    duration: stopwatch.elapsed,
    stdout: stdoutBuffer.toString(),
    stderr: stderrBuffer.toString(),
  );
}

Future<void> _terminateTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/pid', '$pid', '/t', '/f']);
    return;
  }
  late final ProcessResult descendants;
  try {
    descendants = await Process.run('ps', ['-eo', 'pid=,ppid=']).timeout(
      const Duration(seconds: 5),
      onTimeout: () => ProcessResult(pid, 1, '', 'ps timed out'),
    );
  } on Object {
    // The parent may already have exited, or a minimal image may not provide
    // `ps`. Always attempt to kill the known process before returning.
    Process.killPid(pid, ProcessSignal.sigkill);
    return;
  }
  final children = <int, List<int>>{};
  if (descendants.exitCode == 0) {
    for (final line in descendants.stdout.toString().split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      final child = int.tryParse(fields[0]);
      final parent = int.tryParse(fields[1]);
      if (child != null && parent != null) {
        children.putIfAbsent(parent, () => []).add(child);
      }
    }
  }
  Future<void> killChildren(int parent) async {
    for (final child in children[parent] ?? const <int>[]) {
      await killChildren(child);
      Process.killPid(child, ProcessSignal.sigkill);
    }
  }

  await killChildren(pid);
  Process.killPid(pid, ProcessSignal.sigkill);
}
