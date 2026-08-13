import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/generated/release_contract.dart';

import '../../../tool/release_matrix.dart';

void main() {
  test('generated release contract matches the authoritative matrix', () {
    final root = _findRoot(Directory.current);
    final matrix = readReleaseMatrix(root);

    expect(releasePublicPackageVersions, matrix.publicPackageVersions);
    expect(releaseRetiredPackages, matrix.retiredPackages);
    expect(
      releaseSupportedOperatingSystems.toSet(),
      matrix.operatingSystems.toSet(),
    );
    expect(releaseCompatibilityIds, matrix.compatibilityIds);
    expect(
      releaseDartFrogCompatibilityId,
      matrix.compatibilityIds['dart-frog'],
    );
    expect(
      releaseDartSourceCompatibilityId,
      matrix.compatibilityIds['dart-source'],
    );

    final publishable = matrix.packages.values
        .where((package) => package.releaseAction == 'publish')
        .map((package) => package.name)
        .toSet();
    expect(matrix.publicationOrder.toSet(), publishable);
    expect(matrix.publicationOrder, hasLength(publishable.length));
  });
}

Directory _findRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File(
      '${current.path}${Platform.pathSeparator}docs${Platform.pathSeparator}release-matrix.yaml',
    ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the Zuke workspace root.');
    }
    current = parent;
  }
}
