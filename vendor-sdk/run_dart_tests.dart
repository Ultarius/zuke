import 'workspace_tasks.dart' as tasks;

/// Backwards-compatible entry point for the repository-owned package runner.
Future<void> main(List<String> arguments) => tasks.main(['test', ...arguments]);
