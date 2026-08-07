import 'package:zuke_cli/zuke_cli.dart';

/// Use this descriptor for every test-spawned Dart process. Flutter's embedded
/// SDK is resolved before PATH, and each launch suppresses analytics without
/// modifying the test host's user profile.
final TestDartCommand testDart = resolveTestDartCommand();
