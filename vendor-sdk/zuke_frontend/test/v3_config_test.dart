import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  test('rejects legacy workspace configuration forms', () {
    expect(
      () => ZukeConfig.fromYaml('schemaVersion: 2\ntargets: {}'),
      throwsFormatException,
    );
    expect(() => ZukeConfig.fromYaml('targets: {}'), throwsFormatException);
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
        throwsFormatException,
      );
      expect(
        () => ZukeConfig.fromYaml('''
schemaVersion: 3
targets: {}
lock:
  file: zuke.lock.json
'''),
        throwsFormatException,
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
}
