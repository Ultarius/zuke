import 'dart:io';

import 'package:test/test.dart';

import '../../check_coverage.dart';

void main() {
  group('CoverageChecker', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('coverage-checker-test-');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('fails a behavior-bearing package with an unreported source file', () {
      final package = _package(root, 'coverage_fixture');
      _writeLines(File('${package.path}/lib/reported.dart'), 201);
      _writeLines(File('${package.path}/lib/missing.dart'), 2);
      final coverage = Directory('${package.path}/coverage')..createSync();
      File('${coverage.path}/lcov.info').writeAsStringSync(
        'SF:${package.path.replaceAll('\\', '/')}/lib/reported.dart\n'
        'DA:1,1\n'
        'end_of_record\n',
      );

      final report = CoverageChecker(root.path).check();

      expect(report.passed, isFalse);
      final result = report.toJson()['packages'] as List<Object?>;
      final first = result.single as Map<String, Object?>;
      expect(
        first['missingSources'],
        contains('package:coverage_fixture/missing.dart'),
      );
    });

    test('excludes files marked as declaration-only from source inventory', () {
      final package = _package(root, 'coverage_fixture');
      File('${package.path}/lib/api.dart').writeAsStringSync(
        '// coverage:ignore-file\n' +
            List<String>.filled(201, 'int value = 1;').join('\n'),
      );
      _writeLines(File('${package.path}/lib/reported.dart'), 201);
      final coverage = Directory('${package.path}/coverage')..createSync();
      File('${coverage.path}/lcov.info').writeAsStringSync(
        'SF:${package.path.replaceAll('\\', '/')}/lib/reported.dart\n'
        'DA:1,1\n'
        'end_of_record\n',
      );

      final report = CoverageChecker(root.path).check();
      final result = report.toJson()['packages'] as List<Object?>;
      final first = result.single as Map<String, Object?>;
      expect(first['missingSources'], isEmpty);
    });

    test('excludes multiline pure re-export barrels from source inventory', () {
      final package = _package(root, 'coverage_fixture');
      File('${package.path}/lib/api.dart').writeAsStringSync('''
export 'package:other/api.dart'
    show PublicApi;
''');
      _writeLines(File('${package.path}/lib/reported.dart'), 201);
      final coverage = Directory('${package.path}/coverage')..createSync();
      File('${coverage.path}/lcov.info').writeAsStringSync(
        'SF:${package.path.replaceAll('\\', '/')}/lib/reported.dart\n'
        'DA:1,1\n'
        'end_of_record\n',
      );

      final report = CoverageChecker(root.path).check();
      final result = report.toJson()['packages'] as List<Object?>;
      final first = result.single as Map<String, Object?>;
      expect(first['missingSources'], isEmpty);
    });

    test('rejects malformed coverage instead of silently ignoring it', () {
      final package = _package(root, 'coverage_fixture');
      _writeLines(File('${package.path}/lib/source.dart'), 201);
      final coverage = Directory('${package.path}/coverage')..createSync();
      File('${coverage.path}/bad.vm.json').writeAsStringSync('{not json');

      expect(() => CoverageChecker(root.path).check(), throwsFormatException);
    });

    test('normalizes Windows and Unix source identities into one source', () {
      final package = _package(root, 'coverage_fixture');
      _writeLines(File('${package.path}/lib/source.dart'), 201);
      final coverage = Directory('${package.path}/coverage')..createSync();
      final windowsPath = '${package.path}\\lib\\source.dart';
      final escapedWindowsPath = windowsPath.replaceAll('\\', '\\\\');
      File('${coverage.path}/a.vm.json').writeAsStringSync(
        '{"coverage":[{"source":"$escapedWindowsPath","hits":[1,1]}]}',
      );
      File('${coverage.path}/lcov.info').writeAsStringSync(
        'SF:${package.path.replaceAll('\\', '/')}/lib/source.dart\n'
        'DA:1,0\n'
        'end_of_record\n',
      );

      final packageReport =
          (CoverageChecker(root.path).check().toJson()['packages']
                      as List<Object?>)
                  .single
              as Map<String, Object?>;
      expect(packageReport['covered'], 1);
      expect(packageReport['total'], 1);
    });

    test('attributes dependency hits to the package that owns the source', () {
      final consumer = _package(root, 'coverage_consumer');
      final dependency = _package(root, 'coverage_dependency');
      _writeLines(File('${consumer.path}/lib/consumer.dart'), 201);
      _writeLines(File('${dependency.path}/lib/dependency.dart'), 201);
      final coverage = Directory('${consumer.path}/coverage')..createSync();
      File('${coverage.path}/test.vm.json').writeAsStringSync(
        '{"coverage":['
        '{"source":"package:coverage_consumer/consumer.dart","hits":[1,1]},'
        '{"source":"package:coverage_dependency/dependency.dart","hits":[1,1]}'
        ']}',
      );

      final packages =
          (CoverageChecker(root.path).check().toJson()['packages']
                  as List<Object?>)
              .cast<Map<String, Object?>>();
      final byName = {for (final package in packages) package['name']: package};

      expect(byName['coverage_consumer']!['covered'], 1);
      expect(byName['coverage_dependency']!['covered'], 1);
      expect(byName['coverage_dependency']!['missingSources'], isEmpty);
    });
  });
}

Directory _package(Directory root, String name) {
  final package = Directory('${root.path}/vendor-sdk/$name')
    ..createSync(recursive: true);
  File('${package.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
  Directory('${package.path}/lib').createSync();
  return package;
}

void _writeLines(File file, int count) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    List<String>.filled(count, 'int value = 1;').join('\n'),
  );
}
