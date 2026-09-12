import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  test(
    'runner serialization preserves an explicitly empty profile restriction',
    () {
      final fields = <Object?, Object?>{
        'id': 'runner',
        'target': 'target',
        'sourcePackage': 'package',
        'sourceAdapter': 'adapter',
        'sourceCompatibilityId': 'source',
        'runnerCompatibilityId': 'runner',
      };
      final unrestricted = WorkspaceRunner.fromMap(fields);
      final restricted = WorkspaceRunner.fromMap({
        ...fields,
        'profiles': <String>[],
      });
      expect(unrestricted.toJson().containsKey('profiles'), isFalse);
      expect(restricted.toJson()['profiles'], isEmpty);
      expect(
        WorkspaceRunner.fromMap(restricted.toJson()).hasProfileRestriction,
        isTrue,
      );
    },
  );

  test('rejects malformed coverage layers and non-finite thresholds', () {
    for (final section in [
      'layers: {domain: [lib, 42]}',
      'layers: {domain: wrong}',
      'minimumTotal: .nan',
      'minimumTotal: NaN',
    ]) {
      expect(
        () => ZukeConfig.fromYaml('schemaVersion: 3\ncoverage:\n  $section'),
        throwsA(isA<InvalidWorkspaceConfigError>()),
      );
    }
  });

  test('typed collections retain extensions and cannot be mutated', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
execution:
  pullRequest:
    tagExpression: '@smoke'
    future: {flags: [one]}
coverage:
  includedRoots: [lib]
  layers: {domain: [lib/domain]}
  future: {flags: [one]}
''');
    expect(config.executionProfiles['pullRequest']!.tagExpression, '@smoke');
    expect(
      () => config.coverage.includedRoots.add('test'),
      throwsUnsupportedError,
    );
    expect(
      () => config.coverage.layers['domain']!.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => ((config.coverage.extensions['future'] as Map)['flags'] as List)
          .clear(),
      throwsUnsupportedError,
    );
  });
  test('rejects legacy workspace configuration forms', () {
    expect(
      () => ZukeConfig.fromYaml('schemaVersion: 2\ntargets: {}'),
      throwsA(isA<LegacyWorkspaceConfigError>()),
    );
    expect(
      () => ZukeConfig.fromYaml('targets: {}'),
      throwsA(isA<LegacyWorkspaceConfigError>()),
    );
  });

  test(
    'requires stable target, package, runner, and profile-lock identities',
    () {
      expect(
        () => ZukeConfig.fromYaml('''
schemaVersion: 3
targets:
  backend:
    language: dart
    framework: dart-frog
    packages:
      - id: backend
        path: .
        roots: [lib, routes]
execution:
  runners:
    - id: backend-tests
      target: backend
      sourcePackage: missing
      sourceAdapter: dart-frog
      sourceCompatibilityId: dart-frog-gen-2-route-topology-v1
      runnerCompatibilityId: backend-runner-v1
lock:
  directory: assurance/locks
  profiles: [pullRequest]
'''),
        throwsA(isA<InvalidWorkspaceConfigError>()),
      );
      expect(
        () => ZukeConfig.fromYaml('''
schemaVersion: 3
targets: {}
lock:
  file: zuke.lock.json
'''),
        throwsA(isA<InvalidWorkspaceConfigError>()),
      );
    },
  );

  test('accepts a complete V3 identity configuration', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
targets:
  backend:
    language: dart
    framework: dart-frog
    packages:
      - id: backend
        path: .
        roots: [lib, routes]
execution:
  runners:
    - id: backend-tests
      target: backend
      sourcePackage: backend
      sourceAdapter: dart-frog
      sourceCompatibilityId: dart-frog-gen-2-route-topology-v1
      runnerCompatibilityId: backend-runner-v1
      evidenceTypes: [topology]
evidence:
  types:
    topology:
      mode: scenario-record
lock:
  directory: assurance/locks
  profiles: [pullRequest, release]
''');

    expect(config.schemaVersion, 3);
    expect(config.targetPackages['backend']!.single['id'], 'backend');
    expect(config.lockProfiles, ['pullRequest', 'release']);
  });

  test('reads generated contract paths from the configured target', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
targets:
  fixture:
    language: dart
    framework: dart
    contractOutput: lib/src/generated
    contractExport: lib/fixture_contracts.dart
    packages:
      - id: fixture
        path: .
        roots: [lib, test]
''');

    expect(config.contractOutput, 'lib/src/generated');
    expect(config.contractExport, 'lib/fixture_contracts.dart');
  });

  test('validates declared Dart tooling and protected severity shapes', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
policies:
  protectedSeverities:
    staleLock: error
dartTooling:
  extraction:
    authority: cli
    cache: .zuke/cache/dart
    requireResolvedAnnotations: true
    rejectIncompleteFragments: true
  analyzerPlugin:
    enabled: false
  buildHooks:
    default: disabled
    enabledPackages: []
  generation:
    driver: zuke-cli
    commitGeneratedSource: true
    buildRunner: disabled
lock:
  directory: assurance/locks
  profiles: [pullRequest]
  requireCleanGeneration: true
    ''');
    expect(config.schemaVersion, 3);
    final generation = config.dartTooling['generation'] as Map;
    expect(generation['driver'], 'zuke-cli');
    expect(config.protectedSeverities['staleLock'], 'error');
    expect(config.requireCleanGeneration, isTrue);

    for (final invalid in [
      '''schemaVersion: 3\ndartTooling: enabled''',
      '''schemaVersion: 3\ndartTooling:\n  extraction:\n    requireResolvedAnnotations: yes''',
      '''schemaVersion: 3\ndartTooling:\n  generation:\n    buildRunner: maybe''',
      '''schemaVersion: 3\npolicies:\n  protectedSeverities:\n    staleLock: fatal''',
      '''schemaVersion: 3\nlock:\n  requireCleanGeneration: yes''',
    ]) {
      expect(
        () => ZukeConfig.fromYaml(invalid),
        throwsA(isA<InvalidWorkspaceConfigError>()),
      );
    }
  });

  test('retains unknown keys in extensions and warns without failing', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
futureField: keep-me
targets:
  app:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib, test]
execution:
  runners:
    - id: app-tests
      target: app
      sourcePackage: app
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: app-tests-v1
      futureRunnerFlag: true
''');
    expect(config.extensions['futureField'], 'keep-me');
    expect(
      config.warnings.map((warning) => warning.code),
      everyElement('ZK-CONFIG-UNKNOWN-KEY'),
    );
    expect(
      config.warnings.map((warning) => warning.path),
      containsAll([
        'futureField',
        'execution.runners.app-tests.futureRunnerFlag',
      ]),
    );
    final runner = config.workspaceRunners.single;
    expect(runner.extensions['futureRunnerFlag'], isTrue);
    // Preserved defaults: kind test, runnerMode auto, timeout 600.
    expect(runner.kind, 'test');
    expect(runner.runnerMode, 'auto');
    expect(runner.timeoutSeconds, 600);
  });

  test('rejects malformed values for recognized keys', () {
    for (final invalid in [
      'schemaVersion: 3\nexecution:\n  runners:\n    - id: r\n      target: t\n      sourcePackage: p\n      sourceAdapter: a\n      sourceCompatibilityId: c\n      runnerCompatibilityId: r\n      kind: turbo',
      'schemaVersion: 3\nexecution:\n  runners:\n    - id: r\n      target: t\n      sourcePackage: p\n      sourceAdapter: a\n      sourceCompatibilityId: c\n      runnerCompatibilityId: r\n      runnerMode: warp',
      'schemaVersion: 3\nexecution:\n  runners:\n    - id: r\n      target: t\n      sourcePackage: p\n      sourceAdapter: a\n      sourceCompatibilityId: c\n      runnerCompatibilityId: r\n      timeoutSeconds: -5',
      'schemaVersion: 3\ncoverage:\n  minimumTotal: 101',
      'schemaVersion: 3\nevidence:\n  types:\n    unit:\n      mode: telepathy',
      'schemaVersion: 3\nlock:\n  directory: assurance/locks\n  profiles: [pullRequest, ""]',
    ]) {
      expect(
        () => ZukeConfig.fromYaml(invalid),
        throwsA(isA<InvalidWorkspaceConfigError>()),
      );
    }
  });

  test('requires explicit lock profiles without introducing defaults', () {
    // Lock section present without profiles stays an error; parsing must not
    // invent the four-profile onboarding default.
    expect(
      () => ZukeConfig.fromYaml('''
schemaVersion: 3
lock:
  directory: assurance/locks
'''),
      throwsA(isA<InvalidWorkspaceConfigError>()),
    );
    final empty = ZukeConfig.fromYaml('schemaVersion: 3\n');
    expect(empty.lock.profiles, isEmpty);
    expect(empty.lockProfiles, isEmpty);
  });

  test('first-wins target option is compatibility behavior', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
targets:
  first:
    language: dart
    framework: dart
    contractOutput: lib/src/first
    packages:
      - id: first
        path: first
        roots: [lib]
  second:
    language: dart
    framework: dart
    contractOutput: lib/src/second
    packages:
      - id: second
        path: second
        roots: [lib]
''');
    expect(config.contractOutput, 'lib/src/first');
  });

  test('typed and raw configuration views agree before and after', () {
    const yaml = '''
schemaVersion: 3
targets:
  app:
    language: dart
    framework: dart
    packages:
      - id: app
        path: .
        roots: [lib, test]
execution:
  runners:
    - id: app-tests
      target: app
      sourcePackage: app
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: app-tests-v1
      kind: gherkin
      timeoutSeconds: 300
coverage:
  input: coverage/lcov.info
  includedRoots: [lib]
lock:
  directory: assurance/locks
  profiles: [pullRequest, merge]
''';
    final config = ZukeConfig.fromYaml(yaml);
    final runner = config.workspaceRunners.single;
    expect(runner.kind, 'gherkin');
    expect(runner.timeoutSeconds, 300);
    expect(runner.runnerMode, 'auto');
    expect(config.lock.profiles, ['pullRequest', 'merge']);
    expect(config.lockProfiles, ['pullRequest', 'merge']);
    expect(config.coverage.input, 'coverage/lcov.info');
    expect(config.coverage.includedRoots, ['lib']);
    expect(config.coverageConfig['input'], 'coverage/lcov.info');
  });

  test('execution endpoints are not parsed as profiles', () {
    final config = ZukeConfig.fromYaml('''
schemaVersion: 3
execution:
  endpoints:
    api:
      baseUrlFrom: API_URL
  pullRequest:
    tagExpression: '@pr'
''');
    expect(config.executionProfiles.keys, ['pullRequest']);
    expect(config.executionProfiles['pullRequest']!.tagExpression, '@pr');
    expect(config.executionConfig['endpoints'], {
      'api': {'baseUrlFrom': 'API_URL'},
    });
    expect(
      () => ZukeConfig.fromYaml(
        'schemaVersion: 3\nexecution:\n  pullRequest: {}',
      ),
      throwsA(isA<InvalidWorkspaceConfigError>()),
    );
  });
}
