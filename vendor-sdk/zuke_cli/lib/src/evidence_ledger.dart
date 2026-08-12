import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart';

/// Hash-linked evidence publication primitive owned by the CLI boundary.
final class EvidenceLedgerEntry {
  final EvidenceRecord record;
  final Sha256Digest digest;

  EvidenceLedgerEntry(this.record) : digest = _digest(record);

  static Sha256Digest _digest(EvidenceRecord record) => Sha256Digest.parse(
    'sha256:${sha256.convert(utf8.encode(jsonEncode(record.toJson())))}',
  );

  Map<String, Object?> toJson() => {
    'kind': 'zuke.ledger-entry',
    'digest': digest.value,
    'record': record.toJson(),
  };

  factory EvidenceLedgerEntry.fromJson(Map<Object?, Object?> json) {
    if (json['kind'] != 'zuke.ledger-entry') {
      throw const FormatException(
        'Unsupported ledger entry format; regenerate with the current Zuke CLI',
      );
    }
    final rawDigest = json['digest'];
    if (rawDigest is! String) {
      throw const FormatException('Ledger entry digest is missing');
    }
    final digest = Sha256Digest.parse(rawDigest);
    final rawRecord = json['record'];
    if (rawRecord is! Map) {
      throw const FormatException('Ledger entry record is missing');
    }
    final record = EvidenceRecord.fromJson(rawRecord.cast<Object?, Object?>());
    final expected = _digest(record);
    if (expected != digest) {
      throw const FormatException('Ledger entry digest mismatch');
    }
    return EvidenceLedgerEntry._(record, digest);
  }

  EvidenceLedgerEntry._(this.record, this.digest);
}
