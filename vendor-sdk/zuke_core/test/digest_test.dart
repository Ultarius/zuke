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

    test('hashes text exactly, without normalizing line endings', () {
      // Unlike canonicalDigestBytes, sha256Text is a plain hasher: it hashes
      // the bytes it is given. Normalization is the caller's decision, because
      // silently rewriting a caller's text would change what it asked to hash.
      expect(sha256Text('a\nb'), isNot(sha256Text('a\r\nb')));
    });
  });

  group('SourceSnapshotDigest', () {
    const bare =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('holds bare hex and publishes the wire form', () {
      final digest = SourceSnapshotDigest.parse(bare);
      expect(digest.value, bare);
      expect(digest.wireForm, 'sha256:$bare');
      expect(digest.toString(), bare);
      expect(digest, SourceSnapshotDigest.parse(bare));
      expect(digest.hashCode, SourceSnapshotDigest.parse(bare).hashCode);
    });

    test('rejects a wire form and anything that is not bare lowercase hex', () {
      final uppercase = bare.toUpperCase();
      final tooShort = bare.substring(1);
      expect(
        uppercase,
        isNot(bare),
        reason: 'fixture must contain hex letters',
      );
      for (final malformed in <String>[
        // A published identity is stored bare; accepting the wire form here
        // would let a caller smuggle a second shape past the type.
        'sha256:$bare',
        '',
        'e3b0c442',
        uppercase,
        tooShort,
        '${bare}0',
        '0$bare',
      ]) {
        expect(
          () => SourceSnapshotDigest.parse(malformed),
          throwsFormatException,
          reason: 'must reject $malformed',
        );
      }
    });
  });

  group('Sha256Digest', () {
    const wire =
        'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const bare =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('parses only a stored wire digest', () {
      expect(Sha256Digest.parse(wire).value, wire);
      expect(Sha256Digest.parse(wire), Sha256Digest.parse(wire));
      expect(Sha256Digest.parse(wire).hashCode, isNotNull);

      // A bare hex is not a stored record, so parsing must reject it.
      expect(() => Sha256Digest.parse(bare), throwsFormatException);
      for (final malformed in <String>[
        'sha256:',
        'sha256:${bare.toUpperCase()}',
        'sha256:${bare.substring(1)}',
        'sha512:$bare',
        '$wire extra',
        '',
      ]) {
        expect(
          () => Sha256Digest.parse(malformed),
          throwsFormatException,
          reason: 'must reject $malformed',
        );
      }
    });
  });
}
