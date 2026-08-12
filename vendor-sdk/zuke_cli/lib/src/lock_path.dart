/// Canonical lock locations for the current CLI.
library;

const currentLockProfiles = <String>{
  'pullRequest',
  'merge',
  'release',
  'nightly',
};

String profileLockRelativePath(String profile) {
  if (!currentLockProfiles.contains(profile)) {
    throw ArgumentError.value(profile, 'profile', 'Unsupported lock profile');
  }
  return 'assurance/locks/$profile.lock.json';
}

String resolveProfileLockPath(String root, String profile) =>
    '$root/${profileLockRelativePath(profile)}';

String resolveLegacyRootLockPath(String root) => '$root/zuke.lock.json';
