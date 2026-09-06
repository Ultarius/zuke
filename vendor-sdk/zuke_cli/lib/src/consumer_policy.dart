import 'package:zuke_core/zuke_core.dart';

/// Typed model for the consumer-owned policy document
/// (`policies/project-policy.yaml` by default).
///
/// This document is independent of `zuke.yaml`: it governs risk-acceptance
/// thresholds, not workspace topology. Parsing preserves current behavior:
/// a `riskAcceptance` mapping is required, while a
/// malformed recognized value is rejected (surfaced as
/// `ZK-POLICY-CONFIG-MALFORMED`). Unrecognized keys are retained in
/// [extensions] and never fail parsing.
final class ConsumerPolicyDocument {
  final RiskAcceptancePolicy riskAcceptance;
  final Map<String, Object?> extensions;

  const ConsumerPolicyDocument({
    this.riskAcceptance = const RiskAcceptancePolicy(),
    this.extensions = const {},
  });

  static const _knownKeys = {
    'schemaVersion',
    'id',
    'description',
    'riskAcceptance',
    'scenarioCoverage',
    'documentationOnly',
  };

  factory ConsumerPolicyDocument.fromMap(Map<Object?, Object?> value) {
    final rawRisk = value['riskAcceptance'];
    if (rawRisk is! Map) {
      throw const FormatException('riskAcceptance must be a mapping');
    }
    return ConsumerPolicyDocument(
      riskAcceptance: RiskAcceptancePolicy.fromMap(
        Map<Object?, Object?>.from(rawRisk),
      ),
      extensions: {
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: entry.value,
      },
    );
  }

  RiskAcceptanceRequirements toRequirements() => RiskAcceptanceRequirements(
    requiredApprovalCount: riskAcceptance.requiredApprovalCount,
    requiredRoles: riskAcceptance.requiredRoles,
    requiredCompensatingRuns: riskAcceptance.requiredCompensatingRuns,
  );
}

/// Typed `riskAcceptance` section of the consumer policy.
final class RiskAcceptancePolicy {
  final int requiredApprovalCount;
  final Set<String> requiredRoles;
  final Set<String> requiredCompensatingRuns;
  final Map<String, Object?> extensions;

  const RiskAcceptancePolicy({
    this.requiredApprovalCount = 1,
    this.requiredRoles = const {},
    this.requiredCompensatingRuns = const {},
    this.extensions = const {},
  });

  static const _knownKeys = {
    'requiredApprovalCount',
    'requiredApprovals',
    'requiredRoles',
    'requiredCompensatingRuns',
  };

  factory RiskAcceptancePolicy.fromMap(Map<Object?, Object?> value) {
    final count = value['requiredApprovalCount'] ?? value['requiredApprovals'];
    if (count != null && (count is! int || count <= 0)) {
      throw const FormatException('requiredApprovalCount must be positive');
    }
    final roles = value['requiredRoles'];
    if (roles != null &&
        (roles is! List ||
            roles.any((item) => item is! String || item.trim().isEmpty))) {
      throw const FormatException('requiredRoles must be non-empty strings');
    }
    final runs = value['requiredCompensatingRuns'];
    if (runs != null &&
        (runs is! List ||
            runs.any((item) => item is! String || item.trim().isEmpty))) {
      throw const FormatException(
        'requiredCompensatingRuns must be non-empty strings',
      );
    }
    return RiskAcceptancePolicy(
      requiredApprovalCount: count is int && count > 0 ? count : 1,
      requiredRoles: roles is List
          ? roles.whereType<String>().toSet()
          : const {},
      requiredCompensatingRuns: runs is List
          ? runs.whereType<String>().toSet()
          : const {},
      extensions: {
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: entry.value,
      },
    );
  }
}
