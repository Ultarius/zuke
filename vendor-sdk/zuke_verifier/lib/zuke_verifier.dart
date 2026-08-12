/// Supported application-facing exported-history verification API.
library;

import 'dart:convert';

import 'package:zuke_core/zuke_core.dart';

/// A verification verdict for an exported current history.
class ExportVerificationResult {
  final bool valid;
  final List<String> diagnostics;
  final List<String> recordDigests;

  const ExportVerificationResult({
    required this.valid,
    this.diagnostics = const [],
    this.recordDigests = const [],
  });

  Map<String, Object?> toJson() => {
    'kind': 'zuke.verification-result',
    'valid': valid,
    'diagnostics': diagnostics,
    'recordDigests': recordDigests,
  };
}

/// Verifies a `zuke.behavioral-assurance-release-export` value produced by
/// `zuke manifest export`. The export is ordered from its head through
/// each predecessor, so ordering itself is part of the checked contract.
class ExportedReleaseVerifier {
  const ExportedReleaseVerifier();

  Future<ExportVerificationResult> verifyJson(
    String exportJson,
    String trustJson,
  ) async {
    try {
      final exportValue = jsonDecode(exportJson);
      final trustValue = jsonDecode(trustJson);
      if (exportValue is! Map || trustValue is! Map) {
        return const ExportVerificationResult(
          valid: false,
          diagnostics: ['Export and trust bundle must both be JSON objects'],
        );
      }
      return verify(
        Map<String, Object?>.from(exportValue),
        TrustBundle.fromJson(trustValue),
      );
    } on FormatException catch (error) {
      return ExportVerificationResult(
        valid: false,
        diagnostics: [error.message],
      );
    } on Object catch (error) {
      return ExportVerificationResult(
        valid: false,
        diagnostics: ['Invalid export or trust data: $error'],
      );
    }
  }

  Future<ExportVerificationResult> verify(
    Map<String, Object?> export,
    TrustBundle trust,
  ) async {
    if (export['kind'] != 'zuke.behavioral-assurance-release-export') {
      return const ExportVerificationResult(
        valid: false,
        diagnostics: ['Unsupported assurance-history export schema'],
      );
    }
    final chain = export['chain'];
    if (chain is! List) {
      return const ExportVerificationResult(
        valid: false,
        diagnostics: ['Export chain must be a JSON list'],
      );
    }
    final records = <Map<String, Object?>>[];
    for (var index = 0; index < chain.length; index++) {
      final value = chain[index];
      if (value is! Map) {
        return ExportVerificationResult(
          valid: false,
          diagnostics: ['Export record $index is not a JSON object'],
        );
      }
      records.add(Map<String, Object?>.from(value));
    }
    if (records.isEmpty) {
      return const ExportVerificationResult(
        valid: false,
        diagnostics: ['Export chain is empty'],
      );
    }

    final seen = <String>{};
    final digests = <String>[];
    final releaseVerifier = TrustedReleaseVerifier();
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final digest = record['recordDigest'];
      if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        return ExportVerificationResult(
          valid: false,
          diagnostics: ['Export record $index has an invalid recordDigest'],
          recordDigests: digests,
        );
      }
      if (!seen.add(digest)) {
        return ExportVerificationResult(
          valid: false,
          diagnostics: ['Export chain repeats record $digest'],
          recordDigests: digests,
        );
      }
      if (!await releaseVerifier.verify(record, trust)) {
        return ExportVerificationResult(
          valid: false,
          diagnostics: [
            'Export record $digest has an invalid signature or trust identity',
          ],
          recordDigests: digests,
        );
      }
      final previous = (record['body'] as Map?)?['previousRecord'];
      final expectedPrevious = index + 1 < records.length
          ? records[index + 1]['recordDigest']
          : null;
      if (previous != expectedPrevious) {
        return ExportVerificationResult(
          valid: false,
          diagnostics: [
            'Export record $digest has predecessor $previous; expected $expectedPrevious',
          ],
          recordDigests: digests,
        );
      }
      digests.add(digest);
    }
    return ExportVerificationResult(valid: true, recordDigests: digests);
  }
}
