/// Test-only bridge to the repository's single temporary-directory helper.
///
/// This stays local to the test tree so published packages do not acquire a
/// dependency on the repository-only `zuke_test_support` package.
library;

export '../../../zuke_test_support/lib/src/temporary_directory.dart';
