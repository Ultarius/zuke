import 'dart:collection';

/// A diagnostic produced while checking a risk-acceptance record.
final class RiskAcceptanceDiagnostic {
  const RiskAcceptanceDiagnostic({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, String> toJson() => {'code': code, 'message': message};
}

/// Consumer-owned approval and compensating-run requirements.
///
/// The verifier intentionally receives this separately from the acceptance
/// record. This prevents a record from lowering its own approval threshold or
/// role requirements.
final class RiskAcceptanceRequirements {
  const RiskAcceptanceRequirements({
    this.requiredApprovalCount = 1,
    this.requiredRoles = const {},
    this.requiredCompensatingRuns = const {},
  });

  final int requiredApprovalCount;
  final Set<String> requiredRoles;
  final Set<String> requiredCompensatingRuns;
}

/// Validates one approval against an external trust/attestation source.
///
/// A YAML record cannot authenticate itself. Callers that have verified a
/// signature or CI identity may provide that verification here; callers that
/// do not have such a source must leave it null and the result stays
/// unauthenticated.
typedef RiskAcceptanceApprovalVerifier =
    bool Function(Map<Object?, Object?> approval, Map<Object?, Object?> record);

final class RiskAcceptanceVerificationResult {
  const RiskAcceptanceVerificationResult({
    required this.valid,
    this.authenticated = false,
    this.diagnostics = const [],
  });

  final bool valid;
  final bool authenticated;
  final List<RiskAcceptanceDiagnostic> diagnostics;

  Map<String, Object?> toJson() => {
    'valid': valid,
    'authenticated': authenticated,
    'diagnostics': diagnostics
        .map((diagnostic) => diagnostic.toJson())
        .toList(),
  };
}

/// Validates a consumer risk-acceptance record without treating names in a
/// YAML/JSON file as authenticated approval evidence.
final class RiskAcceptanceVerifier {
  const RiskAcceptanceVerifier();

  RiskAcceptanceVerificationResult verify(
    Map<Object?, Object?> record, {
    RiskAcceptanceRequirements requirements =
        const RiskAcceptanceRequirements(),
    String? expectedCommit,
    String? expectedRelease,
    DateTime? now,
    RiskAcceptanceApprovalVerifier? approvalVerifier,
  }) {
    final diagnostics = <RiskAcceptanceDiagnostic>[];
    void error(String code, String message) =>
        diagnostics.add(RiskAcceptanceDiagnostic(code: code, message: message));

    if (record['kind'] != 'zuke.risk-acceptance') {
      error(
        'ZK-POLICY-KIND',
        'Risk-acceptance kind is missing or unsupported.',
      );
    }
    _requireText(record, 'id', error);
    final acceptedAt = _date(record['acceptedAt'], 'acceptedAt', error);
    final expiresAt = _date(record['expiresAt'], 'expiresAt', error);
    final clock = now ?? DateTime.now().toUtc();
    if (expiresAt != null && !expiresAt.isAfter(clock)) {
      error('ZK-POLICY-EXPIRED', 'Risk acceptance has expired.');
    }
    if (acceptedAt != null &&
        expiresAt != null &&
        !expiresAt.isAfter(acceptedAt)) {
      error(
        'ZK-POLICY-DATE-ORDER',
        'Risk acceptance expires before it was accepted.',
      );
    }
    if (expectedCommit != null && record['commit'] != expectedCommit) {
      error(
        'ZK-POLICY-COMMIT-MISMATCH',
        'Risk acceptance is not bound to the expected commit.',
      );
    }
    if (expectedRelease != null && record['release'] != expectedRelease) {
      error(
        'ZK-POLICY-RELEASE-MISMATCH',
        'Risk acceptance is not bound to the expected release.',
      );
    }

    final approvers = record['approvers'];
    final ids = <String>{};
    final roles = <String>{};
    var authenticated = approvers is List && approvers.isNotEmpty;
    if (approvers is! List || approvers.isEmpty) {
      error(
        'ZK-POLICY-APPROVERS',
        'Risk acceptance must list at least one approver.',
      );
      authenticated = false;
    } else {
      for (final value in approvers) {
        if (value is! Map) {
          error(
            'ZK-POLICY-APPROVER-FORMAT',
            'Each approver must be an object.',
          );
          authenticated = false;
          continue;
        }
        final id = value['id'];
        final role = value['role'];
        if (id is! String || id.trim().isEmpty) {
          error(
            'ZK-POLICY-APPROVER-ID',
            'Each approver must have a non-empty id.',
          );
        } else if (!ids.add(id)) {
          error(
            'ZK-POLICY-DUPLICATE-APPROVER',
            'Approver ids must be distinct.',
          );
        }
        if (role is String && role.trim().isNotEmpty) {
          roles.add(role);
        } else {
          error(
            'ZK-POLICY-APPROVER-ROLE',
            'Each approver must have a non-empty role.',
          );
        }
        // An id/role pair is only an assertion. A separate authenticated
        // approval proof is required before this record can be trusted.
        final proof = value['proof'];
        final proofMap = proof is Map
            ? Map<Object?, Object?>.from(proof)
            : null;
        if (approvalVerifier == null ||
            proofMap == null ||
            !approvalVerifier(Map<Object?, Object?>.from(value), record)) {
          authenticated = false;
        }
      }
    }
    if (ids.length < requirements.requiredApprovalCount) {
      error(
        'ZK-POLICY-APPROVAL-COUNT',
        'Risk acceptance has ${ids.length} distinct approver(s); '
            '${requirements.requiredApprovalCount} required.',
      );
    }
    for (final role in requirements.requiredRoles) {
      if (!roles.contains(role)) {
        error(
          'ZK-POLICY-ROLE-MISSING',
          'Required approval role is missing: $role.',
        );
      }
    }
    final runs = record['compensatingRuns'];
    final completedRuns = <String>{};
    if (runs is List) {
      for (final value in runs) {
        if (value is Map &&
            value['id'] is String &&
            value['status'] == 'passed') {
          completedRuns.add(value['id'] as String);
        }
      }
    }
    for (final run in requirements.requiredCompensatingRuns) {
      if (!completedRuns.contains(run)) {
        error(
          'ZK-POLICY-COMPENSATING-RUN',
          'Required compensating run is missing or not passed: $run.',
        );
      }
    }
    if (!authenticated) {
      error(
        'ZK-POLICY-APPROVAL-NOT-AUTHENTICATED',
        'Named approvers are not authenticated approval evidence.',
      );
    }
    return RiskAcceptanceVerificationResult(
      valid: diagnostics.isEmpty,
      authenticated: authenticated,
      diagnostics: UnmodifiableListView(diagnostics),
    );
  }

  void _requireText(
    Map<Object?, Object?> record,
    String field,
    void Function(String, String) error,
  ) {
    final value = record[field];
    if (value is! String || value.trim().isEmpty) {
      error(
        'ZK-POLICY-FIELD',
        'Risk acceptance field $field must be non-empty.',
      );
    }
  }

  DateTime? _date(
    Object? value,
    String field,
    void Function(String, String) error,
  ) {
    if (value is! String || value.trim().isEmpty) {
      error(
        'ZK-POLICY-DATE',
        'Risk acceptance field $field must be an ISO-8601 date.',
      );
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      error(
        'ZK-POLICY-DATE',
        'Risk acceptance field $field must be an ISO-8601 date.',
      );
    }
    return parsed?.toUtc();
  }
}
