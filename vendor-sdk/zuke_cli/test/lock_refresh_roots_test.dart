import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/lock_refresh_roots.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('zuke roots '));
  tearDown(() => root.deleteSync(recursive: true));

  test('discovers nearest roots and deduplicates shared package owners', () {
    for (final path in ['product/a', 'product/b', 'other']) {
      Directory('${root.path}/$path').createSync(recursive: true);
    }
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('workspace: [product/a, product/b, other]');
    File('${root.path}/product/zuke.yaml').writeAsStringSync('');
    File('${root.path}/other/zuke.yaml').writeAsStringSync('');
    final found = lockRefreshRoots([root.path, '${root.path}/product']);
    expect(found.map((d) => d.resolveSymbolicLinksSync()), [
      Directory('${root.path}/product').resolveSymbolicLinksSync(),
      Directory('${root.path}/other').resolveSymbolicLinksSync(),
    ]);
  });

  test('rejects empty discovery, malformed members and escaping paths', () {
    final manifest = File('${root.path}/pubspec.yaml');
    for (final content in [
      'workspace: []',
      'workspace: [12]',
      'workspace: [..]',
    ]) {
      manifest.writeAsStringSync(content);
      expect(() => lockRefreshRoots([root.path]), throwsFormatException);
    }
  });
}
