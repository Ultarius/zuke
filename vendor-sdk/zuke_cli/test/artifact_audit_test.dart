import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:args/args.dart';
import 'package:zuke_cli/zuke_cli.dart';

void main() {
  test(
    'copy audits fresh inputs and refuses unsafe or existing destinations',
    () {
      final root = Directory.systemTemp.createTempSync('zuke-artifact-copy-');
      addTearDown(() => root.deleteSync(recursive: true));
      final input = Directory('${root.path}/input')..createSync();
      final file = File('${input.path}/summary.txt')
        ..writeAsStringSync('status: passed');
      final output = Directory('${root.path}/output');
      const audit = ArtifactAudit();
      expect(audit.inspect(input).safe, isTrue);
      file.writeAsStringSync('Authorization: Bearer confidential');
      expect(audit.copySafe(input, output).safe, isFalse);
      expect(output.existsSync(), isFalse);
      file.writeAsStringSync('status: passed');
      expect(audit.copySafe(input, output).safe, isTrue);
      expect(
        File('${output.path}/summary.txt').readAsStringSync(),
        'status: passed',
      );
      expect(() => audit.copySafe(input, output), throwsArgumentError);
      expect(
        () => audit.copySafe(input, Directory('${input.path}/nested')),
        throwsArgumentError,
      );
    },
  );

  test('accepts a safe bundle and writes no secret into diagnostics', () {
    final root = Directory.systemTemp.createTempSync('zuke-artifacts-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      '${root.path}/summary.json',
    ).writeAsStringSync('{"status":"passed"}\n');

    final report = const ArtifactAudit().inspect(root);

    expect(report.safe, isTrue);
    expect(report.filesScanned, 1);
  });

  test('rejects source and sensitive material without echoing the value', () {
    final root = Directory.systemTemp.createTempSync('zuke-artifacts-');
    addTearDown(() => root.deleteSync(recursive: true));
    const secret = 'Bearer eyJhbGciOiJIUzI1NiJ9.secret.signature';
    File('${root.path}/raw.log').writeAsStringSync(secret);
    File('${root.path}/lib.dart').writeAsStringSync('void main() {}');

    final report = const ArtifactAudit().inspect(root);
    final encoded = jsonEncode(report.toJson());

    expect(report.safe, isFalse);
    expect(
      report.findings.map((finding) => finding.category),
      contains('bearer-token'),
    );
    expect(
      report.findings.map((finding) => finding.category),
      contains('unexpected-source'),
    );
    expect(encoded, isNot(contains(secret)));
  });

  test('rejects quoted JSON secret fields', () {
    final root = Directory.systemTemp.createTempSync('zuke-artifacts-json-');
    addTearDown(() => root.deleteSync(recursive: true));
    const secret = 'json-secret-value';
    File(
      '${root.path}/summary.json',
    ).writeAsStringSync('{"password":"$secret"}');

    final report = const ArtifactAudit().inspect(root);
    expect(report.safe, isFalse);
    expect(
      report.findings.map((finding) => finding.category),
      contains('secret-field'),
    );
    expect(jsonEncode(report.toJson()), isNot(contains(secret)));
  });

  test('rejects a missing bundle', () {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}zuke-no-such-artifacts';
    final report = const ArtifactAudit().inspect(Directory(path));

    expect(report.safe, isFalse);
    expect(report.findings.single.category, 'missing-input');
  });

  test('rejects an empty bundle so failed jobs cannot upload nothing', () {
    final root = Directory.systemTemp.createTempSync('zuke-artifacts-empty-');
    addTearDown(() => root.deleteSync(recursive: true));

    final report = const ArtifactAudit().inspect(root);

    expect(report.safe, isFalse);
    expect(report.findings.single.category, 'empty-input');
  });

  test(
    'packages directory contents and individual files through one command',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'zuke-artifact-package-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final generated = Directory('${root.path}/generated')..createSync();
      File('${generated.path}/summary.json').writeAsStringSync('{"ok":true}');
      final lock = File('${root.path}/pullRequest.lock.json')
        ..writeAsStringSync('{"profile":"pullRequest"}');
      final output = Directory('${root.path}/bundle');
      final resultFile = File('${root.path}/package-result.json');
      final parser = ArgParser()
        ..addOption('output')
        ..addOption('output-file')
        ..addMultiOption('include')
        ..addOption('format', defaultsTo: 'json')
        ..addOption('summary-file');
      final code = await ArtifactPackageCommand(
        parser.parse([
          '--output',
          output.path,
          '--output-file',
          resultFile.path,
          '--include',
          generated.path,
          '--include',
          lock.path,
          '--format',
          'json',
        ]),
      ).execute();

      expect(code, 0);
      expect(File('${output.path}/summary.json').existsSync(), isTrue);
      expect(File('${output.path}/pullRequest.lock.json').existsSync(), isTrue);
      expect(const ArtifactAudit().inspect(output).safe, isTrue);
      final packaged = jsonDecode(resultFile.readAsStringSync()) as Map;
      expect(packaged['kind'], 'zuke.command-result');
      final packagedReport = packaged['report'] as Map;
      final audited = const ArtifactAudit().inspect(output).toJson();
      for (final key in ['input', 'safe', 'filesScanned', 'findings']) {
        expect(
          packagedReport[key],
          audited[key],
          reason: 'audit report parity: $key',
        );
      }
    },
  );

  test(
    'audit command nests its report without colliding with the envelope',
    () async {
      final root = Directory.systemTemp.createTempSync('zuke-artifact-audit-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/summary.json').writeAsStringSync('{"ok":true}');
      final resultFile = File('${root.path}/audit-result.json');
      final parser = ArgParser()
        ..addOption('input')
        ..addOption('output')
        ..addOption('format', defaultsTo: 'json')
        ..addOption('summary-file');

      final code = await ArtifactAuditCommand(
        parser.parse([
          '--input',
          root.path,
          '--output',
          resultFile.path,
          '--format',
          'json',
        ]),
      ).execute();

      expect(code, 0);
      final encoded = jsonDecode(resultFile.readAsStringSync()) as Map;
      expect(encoded['kind'], 'zuke.command-result');
      expect((encoded['report'] as Map)['kind'], 'zuke.artifacts-audit');
      expect((encoded['report'] as Map)['safe'], isTrue);
    },
  );

  test(
    'rejects missing and colliding package inputs before writing output',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'zuke-artifact-package-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final source = File('${root.path}/summary.json')
        ..writeAsStringSync('{"ok":true}');
      final parser = ArgParser()
        ..addOption('output')
        ..addMultiOption('include')
        ..addOption('format', defaultsTo: 'json')
        ..addOption('summary-file');
      Future<int> run(List<String> args) =>
          ArtifactPackageCommand(parser.parse(args)).execute();

      final missingOutput = Directory('${root.path}/missing-output');
      await expectLater(
        run([
          '--output',
          missingOutput.path,
          '--include',
          '${root.path}/missing',
        ]),
        throwsA(isA<FormatException>()),
      );
      expect(missingOutput.existsSync(), isFalse);

      final collisionOutput = Directory('${root.path}/collision-output');
      await expectLater(
        run([
          '--output',
          collisionOutput.path,
          '--include',
          source.path,
          '--include',
          source.path,
        ]),
        throwsA(isA<FormatException>()),
      );
      expect(collisionOutput.existsSync(), isFalse);
    },
  );
  test('reports cannot overwrite files in the audited bundle', () async {
    final root = Directory.systemTemp.createTempSync('zuke-package-report-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File('${root.path}/summary.json')
      ..writeAsStringSync('{"ok":true}');
    final output = Directory('${root.path}/bundle');
    final parser = ArgParser()
      ..addOption('output')
      ..addMultiOption('include')
      ..addOption('output-file')
      ..addOption('summary-file')
      ..addOption('format', defaultsTo: 'json');
    for (final option in ['output-file', 'summary-file']) {
      await expectLater(
        ArtifactPackageCommand(
          parser.parse([
            '--output',
            output.path,
            '--include',
            source.path,
            '--$option',
            '${output.path}/summary.json',
          ]),
        ).execute(),
        throwsA(isA<FormatException>()),
      );
      expect(output.existsSync(), isFalse);
      expect(source.readAsStringSync(), '{"ok":true}');
    }
  });
}
