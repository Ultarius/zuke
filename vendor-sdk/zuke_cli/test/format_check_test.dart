import 'dart:convert';

import 'package:test/test.dart';

import '../../check_format.dart';

void main() {
  test('reads formatter JSON without stripping source-looking status text', () {
    const source = 'void main() {}\nFormatted 1 file\n';
    expect(
      formattedSourceFromJson(
        jsonEncode({'path': 'probe.dart', 'source': source}),
      ),
      source,
    );
  });

  test('compares source after normalizing CRLF and bare CR line endings', () {
    const formatted = 'void main() {}\n';
    final json = jsonEncode({'path': 'probe.dart', 'source': formatted});
    expect(formattedSourceMatches('void main() {}\r\n', json), isTrue);
    expect(formattedSourceMatches('void main() {}\r', json), isTrue);
    expect(formattedSourceMatches('void main() {}\n\n', json), isFalse);
  });

  test('rejects malformed formatter JSON', () {
    expect(formattedSourceFromJson('{not json'), isNull);
    expect(formattedSourceFromJson(jsonEncode({'path': 'probe.dart'})), isNull);
  });
}
