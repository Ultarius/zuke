import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('ExtractDartCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-extract-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'extracts Dart annotations and prints JSON fragment when --emit omitted',
      () async {
        final pkgDir = Directory('${root.path}/packages/my_pkg')
          ..createSync(recursive: true);
        File('${pkgDir.path}/pubspec.yaml').writeAsStringSync('name: my_pkg\n');
        final libDir = Directory('${pkgDir.path}/lib')
          ..createSync(recursive: true);
        File(
          '${libDir.path}/my_pkg.dart',
        ).writeAsStringSync('class Dummy {}\n');

        final result = await runInProcessCli([
          'extract',
          'dart',
          '--root',
          root.path,
          '--package',
          'packages/my_pkg',
        ]);

        expect(result.exitCode, 0);
        expect(result.stdout, contains('"kind": "zuke.adapter-fragment"'));
      },
    );
  });
}
