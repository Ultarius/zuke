import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/v2.dart';

/// Hash-linked evidence publication primitive owned by the CLI boundary.
final class EvidenceLedgerEntry {
  final EvidenceRecordV2 record;
  final Sha256Digest digest;

  EvidenceLedgerEntry(this.record) : digest = _digest(record);

  static Sha256Digest _digest(EvidenceRecordV2 record) => Sha256Digest.parse(
        'sha256:${sha256.convert(utf8.encode(jsonEncode(record.toJson())))}',
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': 'zuke.ledger-entry.v2',
        'digest': digest.value,
        'record': record.toJson(),
      };

  factory EvidenceLedgerEntry.fromJson(Map<Object?, Object?> json) {
    if (json['schemaVersion'] != 'zuke.ledger-entry.v2') {
      throw const FormatException('Unsupported ledger entry schema');
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
    final record = EvidenceRecordV2.fromJson(
      rawRecord.cast<Object?, Object?>(),
    );
    final expected = _digest(record);
    if (expected != digest) {
      throw const FormatException('Ledger entry digest mismatch');
    }
    return EvidenceLedgerEntry._(record, digest);
  }

  EvidenceLedgerEntry._(this.record, this.digest);
}
