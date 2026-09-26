import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_core/src/diagnostic_codes.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-diagnostic-codes-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String relativePath, String contents) {
    final file = File('${root.path}/$relativePath');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  group('scanDeclaredDiagnosticCodes', () {
    test('finds codes behind every emission key', () {
      write('lib/src/findings.dart', '''
const a = 'ZK-ONE-001';
const b = 'ZUKE-TWO-002';
const fallback = 'ZK-THREE-003';
const viaDiagnosticCode = 'ZUKE-BATCH-UNSAFE-ARGUMENT';
''');
      write('lib/src/diagnosticCode.dart', '''
const diagnosticCode = 'ZUKE-FOUR-004';
''');
      final codes = scanDeclaredDiagnosticCodes([
        Directory('${root.path}/lib'),
      ]);
      expect(codes, {
        'ZK-ONE-001',
        'ZUKE-TWO-002',
        'ZK-THREE-003',
        'ZUKE-BATCH-UNSAFE-ARGUMENT',
        'ZUKE-FOUR-004',
      });
    });

    test('skips package test trees', () {
      write('pubspec.yaml', 'name: fixture\n');
      write('lib/src/shipped.dart', "const code = 'ZK-SHIPPED-001';\n");
      write('test/fake_test.dart', "const code = 'ZK-FAKE-001';\n");
      write('test/fixtures/adversarial.dart', "const code = 'ZK-FAKE-002';\n");
      write('integration_test/flow.dart', "const code = 'ZK-FAKE-003';\n");

      final codes = scanDeclaredDiagnosticCodes([root]);
      expect(codes, {'ZK-SHIPPED-001'});
    });

    test('still scans test-named directories that are not a test root', () {
      write('pubspec.yaml', 'name: fixture\n');
      write(
        'lib/src/test_support/helper.dart',
        "const code = 'ZK-HELPER-001';\n",
      );
      write('lib/src/fixtures/sample.dart', "const code = 'ZK-SAMPLE-001';\n");

      final codes = scanDeclaredDiagnosticCodes([root]);
      expect(codes, {'ZK-HELPER-001', 'ZK-SAMPLE-001'});
    });
  });

  group('isPackageTestSource', () {
    test('is anchored on the owning pubspec', () {
      write('pubspec.yaml', 'name: fixture\n');
      write('test/unit_test.dart', '');
      write('integration_test/flow.dart', '');
      write('lib/src/test_support/helper.dart', '');
      write('lib/src/fixtures/sample.dart', '');

      expect(isPackageTestSource('${root.path}/test/unit_test.dart'), isTrue);
      expect(
        isPackageTestSource('${root.path}/integration_test/flow.dart'),
        isTrue,
      );
      expect(
        isPackageTestSource('${root.path}/lib/src/test_support/helper.dart'),
        isFalse,
      );
      expect(
        isPackageTestSource('${root.path}/lib/src/fixtures/sample.dart'),
        isFalse,
      );
    });

    test('treats backslashes as separators', () {
      write('pubspec.yaml', 'name: fixture\n');
      write('test/unit_test.dart', '');
      expect(isPackageTestSource('${root.path}\\test\\unit_test.dart'), isTrue);
    });
  });
}
