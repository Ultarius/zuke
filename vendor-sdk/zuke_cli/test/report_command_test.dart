import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('ReportCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-report-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('writes zuke-model.json report file', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli(['report', '--root', root.path]);
      expect(result.exitCode, 0);

      final reportFile = File('${root.path}/generated/report/zuke-model.json');
      expect(reportFile.existsSync(), isTrue);
      expect(reportFile.readAsStringSync(), contains('FEAT-GATEWAY-001'));
    });

    test(
      'reports Examples IDs on blocks without an empty outline ID',
      () async {
        File('${root.path}/specs/features/gateway.feature').writeAsStringSync(
          '''
    Scenario Outline: Result for <request>
      Given a <request> request
      @SCN-GATEWAY-ALLOWED
      Examples: Allowed requests
        | request |
        | allowed |
      @SCN-GATEWAY-DENIED
      Examples: Denied requests
        | request |
        | denied  |
''',
          mode: FileMode.append,
        );
        final result = await runInProcessCli(['report', '--root', root.path]);
        expect(result.exitCode, 0);
        final contents = File(
          '${root.path}/generated/report/zuke-model.json',
        ).readAsStringSync();
        final model = jsonDecode(contents) as Map<String, Object?>;
        final graph = model['graph'] as Map<String, Object?>;
        final feature =
            (graph['features'] as List<Object?>).single as Map<String, Object?>;
        final rule =
            (feature['rules'] as List<Object?>).single as Map<String, Object?>;
        final outline =
            (rule['scenarios'] as List<Object?>).last as Map<String, Object?>;
        expect(outline.keys, isNot(contains('id')));
        final examples = (outline['examples'] as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(examples.map((block) => block['id']), [
          'SCN-GATEWAY-ALLOWED',
          'SCN-GATEWAY-DENIED',
        ]);
      },
    );
  });
}
