import 'package:test/test.dart';
import 'package:zuke_cli/src/lock_path.dart';

void main() {
  test('resolves only official profile lock locations', () {
    expect(
      resolveProfileLockPath('workspace', 'pullRequest'),
      'workspace/assurance/locks/pullRequest.lock.json',
    );
    expect(
      profileLockRelativePath('nightly'),
      'assurance/locks/nightly.lock.json',
    );
    expect(
      () => profileLockRelativePath('legacy'),
      throwsArgumentError,
    );
  });

  test('exposes the legacy root path only for rejection checks', () {
    expect(resolveLegacyRootLockPath('workspace'), 'workspace/zuke.lock.json');
  });
}
