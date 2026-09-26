import 'dart:convert';

import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  group('sha256 helpers', () {
    test('produce the canonical wire form', () {
      // Known-answer test: SHA-256 of the empty input.
      const emptyHex =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(sha256DigestHex(const []), emptyHex);
      expect(sha256Hex(const []), 'sha256:$emptyHex');
      expect(sha256Text(''), 'sha256:$emptyHex');
    });

    test('hash text as its UTF-8 bytes', () {
      expect(sha256Text('abc'), sha256Hex(utf8.encode('abc')));
      expect(
        sha256DigestHex(utf8.encode('abc')),
        sha256Text('abc').substring(7),
      );
    });

    test('stay stable across LF and CRLF inputs', () {
      expect(sha256Text('a\nb'), isNot(sha256Text('a\r\nb')));
      expect(
        sha256Text('a\r\nb'),
        sha256Text(
          'a\nb'.replaceAll('\n', '\r\n').replaceAll('\r\r\n', '\r\n'),
        ),
      );
    });
  });
}
