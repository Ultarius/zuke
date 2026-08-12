import 'identity.dart';

/// Identity and output coordinates exported to a managed test process.
///
/// An entirely absent context means the test is being run as an ordinary
/// unmanaged test. Once one Zuke variable is present, all required values
/// must be present so evidence can never be emitted with guessed identity.
final class RunnerExecutionContext {
  final String resultDirectory;
  final String profile;
  final String target;
  final String runnerId;
  final String runnerCompatibilityId;
  final ExecutionSourceIdentity sourceIdentity;

  const RunnerExecutionContext({
    required this.resultDirectory,
    required this.profile,
    required this.target,
    required this.runnerId,
    required this.runnerCompatibilityId,
    required this.sourceIdentity,
  });

  static RunnerExecutionContext? fromEnvironment(
    Map<String, String> environment,
  ) {
    const keys = [
      'ZUKE_RESULT_DIR',
      'ZUKE_PROFILE',
      'ZUKE_TARGET',
      'ZUKE_RUNNER_ID',
      'ZUKE_RUNNER_COMPATIBILITY_ID',
      'ZUKE_SOURCE_PACKAGE',
      'ZUKE_SOURCE_ADAPTER',
      'ZUKE_SOURCE_COMPATIBILITY_ID',
    ];
    // Presence, rather than non-empty value, determines whether execution is
    // managed. An explicitly exported empty variable is still a partial
    // managed context and must fail closed instead of silently becoming an
    // ordinary unmanaged test.
    if (!keys.any(environment.containsKey)) return null;

    String required(String key) {
      final value = environment[key];
      if (value == null || value.trim().isEmpty) {
        throw FormatException(
          'Managed runner context is incomplete; missing $key',
        );
      }
      return value;
    }

    return RunnerExecutionContext(
      resultDirectory: required('ZUKE_RESULT_DIR'),
      profile: required('ZUKE_PROFILE'),
      target: required('ZUKE_TARGET'),
      runnerId: required('ZUKE_RUNNER_ID'),
      runnerCompatibilityId: required('ZUKE_RUNNER_COMPATIBILITY_ID'),
      sourceIdentity: ExecutionSourceIdentity(
        sourcePackage: required('ZUKE_SOURCE_PACKAGE'),
        sourceAdapter: required('ZUKE_SOURCE_ADAPTER'),
        sourceCompatibilityId: required('ZUKE_SOURCE_COMPATIBILITY_ID'),
      ),
    );
  }

  Map<String, String> toEnvironment() => {
    'ZUKE_RESULT_DIR': resultDirectory,
    'ZUKE_PROFILE': profile,
    'ZUKE_TARGET': target,
    'ZUKE_RUNNER_ID': runnerId,
    'ZUKE_RUNNER_COMPATIBILITY_ID': runnerCompatibilityId,
    'ZUKE_SOURCE_PACKAGE': sourceIdentity.sourcePackage,
    'ZUKE_SOURCE_ADAPTER': sourceIdentity.sourceAdapter,
    'ZUKE_SOURCE_COMPATIBILITY_ID': sourceIdentity.sourceCompatibilityId,
  };
}
