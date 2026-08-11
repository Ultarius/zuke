import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:assurance_ir/assurance_ir.dart';

/// Small analyzer-free publication primitive. The CLI owns persistence and
/// this package owns deterministic evidence identity and hashing.
final class EvidenceLedgerEntry {
  final EvidenceRecordV2 record;
  final String digest;

  EvidenceLedgerEntry(this.record) : digest = _digest(record);

  static String _digest(EvidenceRecordV2 record) =>
      'sha256:${sha256.convert(utf8.encode(jsonEncode(record.toJson())))}';

  Map<String, Object?> toJson() => {
        'schemaVersion': 'zuke.ledger-entry.v2',
        'digest': digest,
        'record': record.toJson(),
      };
}
