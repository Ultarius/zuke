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

/// The published identity of one source snapshot.
///
/// Bare hex internally; [wireForm] is the `sha256:<hex>` form that evidence
/// records, lock fragments and control digests store.
///
/// This is a different quantity from both [Sha256Digest] (the wire form of an
/// arbitrary payload) and an extraction cache key (which must also cover
/// generated files, so that regenerating a contract misses the cache). Those
/// three used to share the field name `inputDigest` and were reconciled by
/// silently overwriting one with another; giving the published identity its own
/// type means a cache identity can no longer be passed where a published
/// identity is expected.
final class SourceSnapshotDigest {
  /// The bare lowercase hex digest, without the `sha256:` prefix.
  final String value;

  const SourceSnapshotDigest._(this.value);

  /// Parses a bare lowercase hex [value] as produced by a source walker.
  factory SourceSnapshotDigest.parse(String value) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException(
        'Source snapshot digest must be 64 lowercase hex characters',
      );
    }
    return SourceSnapshotDigest._(value);
  }

  /// The `sha256:<hex>` form stored in evidence and lock documents.
  String get wireForm => 'sha256:$value';

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is SourceSnapshotDigest && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Canonical SHA-256 digest used by current evidence and ledger contracts.
///
/// The wire form is `sha256:<64 lowercase hex>`. The prefix is spelled out here
/// rather than exposed as a constant: no caller needs to split a digest apart,
/// and an unused public constant in a published package is just API to maintain.
final class Sha256Digest {
  static final _wirePattern = RegExp(r'^sha256:[a-f0-9]{64}$');

  final String value;

  const Sha256Digest._(this.value);

  /// Parses [value] as a stored `sha256:<64 lowercase hex>` wire digest.
  ///
  /// Strict: a stored record is required to carry the prefix, so a bare hex
  /// here is a malformed record rather than a digest in another shape. A value
  /// that may still be an adapter's bare hex has to be resolved leniently by the
  /// caller — `IrAdapterOutput` does that in one place, so a stored record and
  /// an adapter's own read-digest are never confused for each other here.
  factory Sha256Digest.parse(String value) {
    if (!_wirePattern.hasMatch(value)) {
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
