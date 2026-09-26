import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Lowercase hex SHA-256 of [bytes], without the `sha256:` wire prefix.
///
/// Content hashes that stay inside one artifact (generated file hashes, cache
/// keys) use this form; anything that crosses a component boundary uses
/// [sha256Hex] or [sha256Text].
String sha256DigestHex(List<int> bytes) => sha256.convert(bytes).toString();

/// The `sha256:<hex>` wire form of [bytes].
String sha256Hex(List<int> bytes) => 'sha256:${sha256DigestHex(bytes)}';

/// The `sha256:<hex>` wire form of the UTF-8 bytes of [value].
String sha256Text(String value) => sha256Hex(utf8.encode(value));

/// Canonical SHA-256 digest used by current evidence and ledger contracts.
final class Sha256Digest {
  final String value;

  const Sha256Digest._(this.value);

  factory Sha256Digest.parse(String value) {
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('Digest must be sha256:<64 lowercase hex>');
    }
    return Sha256Digest._(value);
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is Sha256Digest && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
