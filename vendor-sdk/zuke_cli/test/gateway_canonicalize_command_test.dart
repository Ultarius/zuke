import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_cli/zuke_cli.dart';
import 'package:test/test.dart';

void main() {
  group('APIM gateway canonicalization', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('apim_export_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('sorts and removes transient secret-bearing values', () {
      final input = File('${temp.path}/raw.json')
        ..writeAsStringSync(jsonEncode(_export()));
      final output = File('${temp.path}/canonical.json');

      final command = GatewayCanonicalizeCommand(_arguments(input, output));
      expect(command.execute(), 0);

      final result = jsonDecode(output.readAsStringSync()) as Map;
      expect(result['reference'], 'EDGE-POLICY-2841');
      expect(result.containsKey('accessToken'), isFalse);
      expect((result['policies'] as Map)['api'], contains('<rate-limit'));
    });

    test('rejects a policy export without a rate limit', () {
      final raw = _export();
      (raw['policies'] as Map)['api'] = '<policies><inbound /></policies>';
      final input = File('${temp.path}/raw.json')
        ..writeAsStringSync(jsonEncode(raw));
      final output = File('${temp.path}/canonical.json');

      expect(
        () => GatewayCanonicalizeCommand(_arguments(input, output)).execute(),
        throwsFormatException,
      );
    });

    test('resolves APIM base inheritance before hashing', () {
      final raw = _export();
      (raw['policies'] as Map)['service'] =
          '<policies><inbound><rate-limit calls="10" renewal-period="60" />'
          '</inbound></policies>';
      (raw['policies'] as Map)['product'] =
          '<policies><inbound><base /></inbound></policies>';
      (raw['policies'] as Map)['api'] =
          '<policies><inbound><base /></inbound></policies>';
      (raw['policies'] as Map)['operation'] =
          '<policies><inbound><base /></inbound></policies>';
      final input = File('${temp.path}/raw.json')
        ..writeAsStringSync(jsonEncode(raw));
      final output = File('${temp.path}/canonical.json');

      expect(
        GatewayCanonicalizeCommand(_arguments(input, output)).execute(),
        0,
      );
      final result = jsonDecode(output.readAsStringSync()) as Map;
      expect((result['policies'] as Map)['operation'], contains('<rate-limit'));
      expect(
        (result['policies'] as Map)['operation'],
        isNot(contains('<base')),
      );
    });

    test('rejects missing input file', () {
      final input = File('${temp.path}/nonexistent.json');
      final output = File('${temp.path}/canonical.json');

      expect(
        () => GatewayCanonicalizeCommand(_arguments(input, output)).execute(),
        throwsFormatException,
      );
    });

    test('rejects route mismatch', () {
      final raw = _export()..['route'] = '/wrong/route';
      final input = File('${temp.path}/raw.json')
        ..writeAsStringSync(jsonEncode(raw));
      final output = File('${temp.path}/canonical.json');

      expect(
        () => GatewayCanonicalizeCommand(_arguments(input, output)).execute(),
        throwsFormatException,
      );
    });

    test('rejects unresolved <base/> at service level', () {
      final raw = _export();
      (raw['policies'] as Map)['service'] =
          '<policies><inbound><base /></inbound></policies>';
      final input = File('${temp.path}/raw.json')
        ..writeAsStringSync(jsonEncode(raw));
      final output = File('${temp.path}/canonical.json');

      expect(
        () => GatewayCanonicalizeCommand(_arguments(input, output)).execute(),
        throwsFormatException,
      );
    });
  });
}

ArgResults _arguments(File input, File output) =>
    (ArgParser()
          ..addOption('input', mandatory: true)
          ..addOption('output', mandatory: true)
          ..addOption('route', mandatory: true)
          ..addOption('reference', mandatory: true))
        .parse([
          '--input',
          input.path,
          '--output',
          output.path,
          '--route',
          '/v1/calculations/**',
          '--reference',
          'EDGE-POLICY-2841',
        ]);

Map<String, Object?> _export() => {
  'route': '/v1/calculations/**',
  'accessToken': 'must-not-survive',
  'policies': {
    'service': '<policies><inbound /></policies>',
    'product': '<policies><inbound /></policies>',
    'api':
        '<policies>\n <inbound><rate-limit calls="10" '
        'renewal-period="60" /></inbound>\n</policies>',
    'operation': '<policies><inbound /></policies>',
  },
  'verification': {
    'policyAttached': true,
    'inheritanceResolved': true,
    'currentRevision': true,
  },
};
