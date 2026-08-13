import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import '../ir.dart' as ir;
import '../ir.dart';

import '../generator.dart';
import 'workspace_digest.dart';
import 'validator.dart';
import '../source_output_catalog.dart';

final class _SourceOutputLookup {
  const _SourceOutputLookup({this.output, this.failure});

  final IrAdapterOutput? output;
  final SourceResolveFailure? failure;
}

class EvidenceValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace, {
    List<EvidenceRecord> records = const [],
    List<ControlProofResult> controlProofs = const [],
    List<IrAdapterOutput> outputs = const [],

    /// The exact scenario IDs selected by the configured execution profile.
    /// A null value means the caller is running without profile filtering.
    List<String>? selectedScenarioIds,
  }) {
    final errors = <ValidationMessage>[];

    // Compute expected digests once per validation pass
    final generator = DartContractGenerator();
    final generated = generator.generate(
      workspace: workspace,
      outputDir: workspace.config.contractOutput ?? 'lib/src/generated',
      exportPath: workspace.config.contractExport,
    );
    final contractDigest =
        'sha256:${sha256.convert(utf8.encode(generated.manifest.toJson())).toString()}';

    final rootPath = workspace.config.root;
    final specificationDigest = rootPath != null
        ? WorkspaceDigest.computeFiltered(
            rootPath,
            (path) => path.startsWith('specs/'),
          )
        : null;
    final mappingDigest = rootPath != null
        ? WorkspaceDigest.computeFiltered(
            rootPath,
            (path) =>
                path.startsWith('specs/registry/') ||
                path.startsWith('policies/') ||
                path.endsWith('zuke.yaml'),
          )
        : null;
    final sourceCatalog = SourceOutputCatalog.build(workspace, outputs);

    // B2: Build valid mappings to check for unmapped records
    final validMappings = <String>{};
    final ruleById = <String, ParsedRule>{};
    final featureByRuleId = <String, ParsedFeature>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final id = rule.metadata.id;
        if (id == null) continue;
        ruleById[id] = rule;
        featureByRuleId[id] = feature;
        final requiredEvidence = rule.metadata.requiredEvidence ?? const [];
        for (final type in requiredEvidence) {
          final slots = rule.metadata.evidenceRequirements
              ?.where(
                (slot) => slot['type'] == type || slot['evidenceType'] == type,
              )
              .toList();
          if (slots != null && slots.isNotEmpty) {
            for (final slot in slots) {
              final expectedTarget = _nonEmpty(slot['target']);
              final sourcePackage = _nonEmpty(slot['sourcePackage']);
              final sourceAdapter = _nonEmpty(slot['sourceAdapter']);
              if (expectedTarget == null ||
                  sourcePackage == null ||
                  sourceAdapter == null) {
                errors.add(
                  ValidationMessage(
                    code: 'ZK-EVIDENCE-SLOT-IDENTITY-MISSING',
                    message:
                        'Evidence slot for requirement "$id" and type "$type" '
                        'must declare target, sourcePackage, and sourceAdapter.',
                    severity: Severity.error,
                    source: rule.metadata.source,
                  ),
                );
                continue;
              }
              validMappings.add(
                _mappingKey(
                  id,
                  type,
                  expectedTarget,
                  slot['variant'] ?? 'default',
                  sourcePackage,
                  sourceAdapter,
                ),
              );
            }
          }
        }
      }
    }

    // Iterate and validate records
    for (final record in records) {
      final id = record.requirementId;
      final type = record.evidenceType;
      final target = record.target;

      // ZUKE-EVIDENCE-005: Reject unmapped records
      final mappingKey = _mappingKey(
        id,
        type,
        target,
        record.variant,
        record.sourcePackage,
        record.sourceAdapter,
      );
      if (!validMappings.contains(mappingKey)) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-EVIDENCE-005',
            message:
                'Unmapped evidence record for requirement "$id" with type "$type" and target "$target"',
            severity: Severity.error,
          ),
        );
        continue;
      }

      for (final digest in const [
        'source',
        'contract',
        'mapping',
        'specificationIndex',
        'result',
      ]) {
        if (record.digests[digest] == null) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-EVIDENCE-STALE',
              message: 'Evidence record for $id ($type) lacks $digest digest',
              severity: Severity.error,
            ),
          );
        }
      }

      final rule = ruleById[id]!;
      final feature = featureByRuleId[id]!;

      // ZUKE-EVIDENCE-006: Reject skipped security evidence
      final hasSecurityTag =
          feature.tags.any((t) => t.name == 'security') ||
          rule.tags.any((t) => t.name == 'security') ||
          rule.scenarios.any((s) => s.tags.any((t) => t.name == 'security'));
      if (hasSecurityTag && record.status == EvidenceStatus.skipped) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-EVIDENCE-006',
            message: 'Mandatory security evidence "$type" was skipped for $id',
            severity: Severity.error,
            source: rule.metadata.source,
          ),
        );
      }

      // B3: Digest validation
      // 1. Contract digest
      if (record.digests.containsKey('contract')) {
        if (record.digests['contract'] != contractDigest) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-EVIDENCE-STALE',
              message:
                  'Stale contract digest in evidence record for $id ($type)',
              severity: Severity.error,
              source: rule.metadata.source,
            ),
          );
        }
      }

      // 2. Specification digest
      if (record.digests.containsKey('specificationIndex')) {
        if (specificationDigest != null &&
            record.digests['specificationIndex'] != specificationDigest) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-EVIDENCE-STALE',
              message:
                  'Stale specification digest in evidence record for $id ($type)',
              severity: Severity.error,
              source: rule.metadata.source,
            ),
          );
        }
      }

      if (record.digests.containsKey('mapping') &&
          mappingDigest != null &&
          record.digests['mapping'] != mappingDigest) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-EVIDENCE-STALE',
            message: 'Stale mapping digest in evidence record for $id ($type)',
            severity: Severity.error,
            source: rule.metadata.source,
          ),
        );
      }

      // 3. Source digest (code-annotation mapping digest)
      if (record.digests.containsKey('source')) {
        final lookup = _sourceOutputForRecord(sourceCatalog, record);
        final output = lookup.output;
        if (output == null) {
          final failure = lookup.failure;
          if (failure != null) {
            errors.add(
              ValidationMessage(
                code: failure.code,
                message: failure.message,
                severity: Severity.error,
                source: rule.metadata.source,
              ),
            );
          }
          errors.add(
            ValidationMessage(
              code: 'ZUKE-EVIDENCE-STALE',
              message:
                  'No source extraction matches the evidence identity for $id ($type)',
              severity: Severity.error,
              source: rule.metadata.source,
            ),
          );
        } else {
          final sourceDigest = output.inputDigest.startsWith('sha256:')
              ? output.inputDigest
              : 'sha256:${output.inputDigest}';
          if (record.digests['source'] != sourceDigest) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-EVIDENCE-STALE',
                message:
                    'Stale source mapping digest in evidence record for $id ($type)',
                severity: Severity.error,
                source: rule.metadata.source,
              ),
            );
          }
        }
      }
    }

    // The runner supplies the selector's exact output. Do not reproduce
    // profile tag semantics here: that caused nightly profiles to be treated
    // as if they also selected pull-request and merge scenarios.
    final selectedRuleIds = <String>{};
    if (selectedScenarioIds != null) {
      final selected = selectedScenarioIds.toSet();
      final scenarioRules = _scenarioRules(workspace);
      for (final id in selected) {
        final rule = scenarioRules[id];
        if (rule == null) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-SCENARIO-UNTESTED',
              message:
                  'Selected scenario "$id" is not declared in the workspace',
              severity: Severity.error,
            ),
          );
          continue;
        }
        final ruleId = rule.metadata.id;
        if (ruleId != null) selectedRuleIds.add(ruleId);
      }
      final observed = _executedScenarioIds(
        records,
        scenarioRules.keys.toSet(),
      );
      for (final id in (selected.difference(observed).toList()..sort())) {
        final rule = scenarioRules[id];
        errors.add(
          ValidationMessage(
            code: 'ZUKE-SCENARIO-UNTESTED',
            message: 'Selected scenario "$id" was not executed by test runner',
            severity: Severity.error,
            source: rule == null ? null : _sourceSpan(workspace, rule),
          ),
        );
      }
      for (final id
          in (observed.difference(scenarioRules.keys.toSet()).toList()
            ..sort())) {
        final rule = scenarioRules[id];
        errors.add(
          ValidationMessage(
            code: 'ZUKE-SCENARIO-UNEXPECTED',
            message: 'Evidence was published for undeclared scenario "$id"',
            severity: Severity.error,
            source: rule == null ? null : _sourceSpan(workspace, rule),
          ),
        );
      }
    }

    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (selectedScenarioIds != null &&
            !selectedRuleIds.contains(rule.metadata.id)) {
          continue;
        }
        final requiredEvidence = rule.metadata.requiredEvidence;
        if (requiredEvidence == null || requiredEvidence.isEmpty) continue;

        // Check accessibility / security rules coherency
        final hasSecurityTag =
            feature.tags.any((t) => t.name == 'security') ||
            rule.tags.any((t) => t.name == 'security') ||
            rule.scenarios.any((s) => s.tags.any((t) => t.name == 'security'));
        if (hasSecurityTag) {
          final hasNegativeScenario = rule.scenarios.any(
            (s) => s.tags.any((t) => t.name == 'negative'),
          );
          if (!hasNegativeScenario) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-EVID-001',
                message:
                    'Security rule "${rule.metadata.id}" requires a negative scenario',
                severity: Severity.error,
                source: rule.metadata.source,
              ),
            );
          }
        }

        final hasAccessibilityTag =
            rule.tags.any((t) => t.name == 'accessibility') ||
            rule.scenarios.any(
              (s) => s.tags.any((t) => t.name == 'accessibility'),
            );
        if (hasAccessibilityTag) {
          if (!requiredEvidence.contains('flutter-widget') &&
              !requiredEvidence.contains('accessibility-integration')) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-EVID-002',
                message:
                    'Accessibility rule "${rule.metadata.id}" requires Flutter or accessibility evidence',
                severity: Severity.warning,
                source: rule.metadata.source,
              ),
            );
          }
        }

        for (final evidenceType in requiredEvidence) {
          if (!_isSatisfied(
            evidenceType,
            feature,
            rule,
            workspace,
            records,
            controlProofs,
            contractDigest,
            specificationDigest,
            mappingDigest,
            sourceCatalog,
          )) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-EVID-003',
                message:
                    'Required evidence "$evidenceType" is not present for ${rule.metadata.id}',
                severity: Severity.error,
                source: rule.metadata.source,
              ),
            );
          }
        }
      }
    }

    return ValidationResult(errors: errors);
  }

  bool _isRecordStale(
    EvidenceRecord record,
    WorkspaceDiscoveryResult workspace,
    String contractDigest,
    String? specificationDigest,
    String? mappingDigest,
    SourceOutputCatalog sourceCatalog,
  ) {
    final id = record.requirementId;

    final slots = _slotsForRequirement(workspace, id, record.evidenceType);
    if (slots.isNotEmpty &&
        !slots.any(
          (slot) =>
              record.target == slot['target'] &&
              record.variant == (slot['variant'] ?? 'default') &&
              record.sourcePackage == slot['sourcePackage'] &&
              record.sourceAdapter == slot['sourceAdapter'],
        )) {
      return true;
    }

    if (record.digests.containsKey('contract') &&
        record.digests['contract'] != contractDigest) {
      return true;
    }
    if (specificationDigest != null &&
        record.digests['specificationIndex'] != specificationDigest) {
      return true;
    }
    if (mappingDigest != null && record.digests['mapping'] != mappingDigest) {
      return true;
    }
    if (record.digests.containsKey('source')) {
      final output = _sourceOutputForRecord(sourceCatalog, record).output;
      if (output == null) {
        return true;
      } else {
        final sourceDigest = output.inputDigest.startsWith('sha256:')
            ? output.inputDigest
            : 'sha256:${output.inputDigest}';
        if (record.digests['source'] != sourceDigest) {
          return true;
        }
      }
    }

    return false;
  }

  _SourceOutputLookup _sourceOutputForRecord(
    SourceOutputCatalog sourceCatalog,
    EvidenceRecord record,
  ) {
    final sourcePackage = record.sourcePackage;
    final sourceAdapter = record.sourceAdapter;
    final compatibilityId = record.sourceCompatibilityId;
    if (sourcePackage == null ||
        sourcePackage.isEmpty ||
        sourceAdapter == null ||
        sourceAdapter.isEmpty ||
        compatibilityId == null ||
        compatibilityId.isEmpty) {
      return const _SourceOutputLookup(
        failure: SourceResolveFailure(
          code: 'ZK-EVIDENCE-SLOT-IDENTITY-MISSING',
          message: 'Evidence source identity is incomplete.',
        ),
      );
    }
    try {
      return _SourceOutputLookup(
        output: sourceCatalog
            .resolve(
              target: record.target,
              sourcePackage: sourcePackage,
              sourceAdapter: sourceAdapter,
              sourceCompatibilityId: compatibilityId,
            )
            .output,
      );
    } on SourceResolveFailure catch (failure) {
      return _SourceOutputLookup(failure: failure);
    }
  }

  bool _isSatisfied(
    String type,
    ParsedFeature feature,
    ParsedRule rule,
    WorkspaceDiscoveryResult workspace,
    List<EvidenceRecord> records,
    List<ControlProofResult> controlProofs,
    String contractDigest,
    String? specificationDigest,
    String? mappingDigest,
    SourceOutputCatalog sourceCatalog,
  ) {
    final id = rule.metadata.id;
    final executionEvidence = records
        .where(
          (r) => !_isRecordStale(
            r,
            workspace,
            contractDigest,
            specificationDigest,
            mappingDigest,
            sourceCatalog,
          ),
        )
        .toList();
    final slots = _slotsForRule(rule, type);
    if (slots.isEmpty) return false;
    // A requirement may intentionally be evidenced by multiple independent
    // target/package slots. Every exact slot must be satisfied; selecting the
    // first slot would allow one component to hide another.
    if (slots.any(
      (slot) =>
          _nonEmpty(slot['target']) == null ||
          _nonEmpty(slot['sourcePackage']) == null ||
          _nonEmpty(slot['sourceAdapter']) == null,
    )) {
      return false;
    }
    final configuredMode = workspace.config.evidenceTypes[type];
    return slots.every(
      (slot) => _isSingleSlotSatisfied(
        type: type,
        mode: configuredMode,
        rule: rule,
        records: executionEvidence,
        controlProofs: controlProofs,
        requirementId: id,
        target: slot['target']!,
        variant: slot['variant'] ?? 'default',
        sourcePackage: slot['sourcePackage']!,
        sourceAdapter: slot['sourceAdapter']!,
      ),
    );
  }

  bool _isSingleSlotSatisfied({
    required String type,
    required String? mode,
    required ParsedRule rule,
    required List<EvidenceRecord> records,
    required List<ControlProofResult> controlProofs,
    required String? requirementId,
    required String target,
    required String variant,
    required String sourcePackage,
    required String sourceAdapter,
  }) {
    if (mode != null && !_builtInEvidenceTypes.contains(type)) {
      return _isConfiguredEvidenceSatisfied(
        mode: mode,
        rule: rule,
        records: records,
        controlProofs: controlProofs,
        requirementId: requirementId,
        evidenceType: type,
        target: target,
        variant: variant,
        sourcePackage: sourcePackage,
        sourceAdapter: sourceAdapter,
      );
    }
    switch (type) {
      case 'domain-unit':
        return _hasPassedEvidence(
          records,
          requirementId,
          type,
          target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'flutter-widget':
      case 'accessibility-integration':
        return _hasPassedEvidence(
          records,
          requirementId,
          type,
          target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'api-contract':
        return _hasPassedEvidence(
          records,
          requirementId,
          type,
          target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'performance':
        return _hasPassedEvidence(
          records,
          requirementId,
          type,
          target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'gherkin-api':
        return _hasExecutedEvidence(
          rule,
          records,
          'gherkin-api',
          target: target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'gherkin-ui':
        return _hasExecutedEvidence(
          rule,
          records,
          'gherkin-ui',
          target: target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'security-integration':
        return (rule.metadata.requires ?? const <ParsedControlRef>[]).every(
              (control) => controlProofs.any(
                (proof) =>
                    proof.controlId == control.id &&
                    (proof.status == ProofStatus.proven ||
                        proof.status == ProofStatus.verified ||
                        proof.status == ProofStatus.attested),
              ),
            ) &&
            _hasExecutedEvidence(
              rule,
              records,
              'security-integration',
              target: target,
              variant: variant,
              sourcePackage: sourcePackage,
              sourceAdapter: sourceAdapter,
            );
      case 'logging-verification':
        return _hasExecutedEvidence(
          rule,
          records,
          'logging-verification',
          target: target,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'attestation-freshness':
        return (rule.metadata.requires ?? const <ParsedControlRef>[]).any(
          (control) => controlProofs.any(
            (proof) =>
                proof.controlId == control.id &&
                proof.status == ProofStatus.attested,
          ),
        );
      default:
        return false;
    }
  }

  bool _isConfiguredEvidenceSatisfied({
    required String mode,
    required ParsedRule rule,
    required List<EvidenceRecord> records,
    required List<ControlProofResult> controlProofs,
    required String? requirementId,
    required String evidenceType,
    required String? target,
    required String variant,
    required String? sourcePackage,
    required String? sourceAdapter,
  }) {
    if (target == null || target.isEmpty) return false;
    final record = switch (mode) {
      'record' => _hasPassedEvidence(
        records,
        requirementId,
        evidenceType,
        target,
        variant: variant,
        sourcePackage: sourcePackage,
        sourceAdapter: sourceAdapter,
      ),
      'scenario-record' => _hasExecutedEvidence(
        rule,
        records,
        evidenceType,
        target: target,
        variant: variant,
        sourcePackage: sourcePackage,
        sourceAdapter: sourceAdapter,
      ),
      'control-backed' =>
        _hasExecutedEvidence(
              rule,
              records,
              evidenceType,
              target: target,
              variant: variant,
              sourcePackage: sourcePackage,
              sourceAdapter: sourceAdapter,
            ) &&
            (rule.metadata.requires?.isNotEmpty ?? false) &&
            rule.metadata.requires!.every(
              (control) => controlProofs.any(
                (proof) =>
                    proof.controlId == control.id &&
                    (proof.status == ProofStatus.proven ||
                        proof.status == ProofStatus.verified ||
                        proof.status == ProofStatus.attested),
              ),
            ),
      'attestation' =>
        (rule.metadata.requires?.isNotEmpty ?? false) &&
            rule.metadata.requires!.every(
              (control) => controlProofs.any(
                (proof) =>
                    proof.controlId == control.id &&
                    proof.status == ProofStatus.attested,
              ),
            ),
      _ => false,
    };
    return record;
  }

  bool _hasExecutedEvidence(
    ParsedRule rule,
    List<EvidenceRecord> records,
    String evidenceType, {
    String? target,
    String variant = 'default',
    String? sourcePackage,
    String? sourceAdapter,
  }) {
    final id = rule.metadata.id;
    if (id == null || target == null) return false;
    return records.any((record) {
      return record.requirementId == id &&
          record.evidenceType == evidenceType &&
          record.status == EvidenceStatus.passed &&
          record.target == target &&
          record.variant == variant &&
          (sourcePackage == null || record.sourcePackage == sourcePackage) &&
          (sourceAdapter == null || record.sourceAdapter == sourceAdapter);
    });
  }

  bool _hasPassedEvidence(
    Iterable<EvidenceRecord> records,
    String? requirementId,
    String evidenceType,
    String target, {
    String variant = 'default',
    String? sourcePackage,
    String? sourceAdapter,
  }) => records.any(
    (record) =>
        record.requirementId == requirementId &&
        record.evidenceType == evidenceType &&
        record.target == target &&
        record.status == EvidenceStatus.passed &&
        record.variant == variant &&
        (sourcePackage == null || record.sourcePackage == sourcePackage) &&
        (sourceAdapter == null || record.sourceAdapter == sourceAdapter),
  );

  List<Map<String, String>> _slotsForRule(
    ParsedRule rule,
    String evidenceType,
  ) => [
    for (final slot in rule.metadata.evidenceRequirements ?? const [])
      if (slot['type'] == evidenceType || slot['evidenceType'] == evidenceType)
        slot,
  ];

  List<Map<String, String>> _slotsForRequirement(
    WorkspaceDiscoveryResult workspace,
    String requirementId,
    String evidenceType,
  ) {
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (rule.metadata.id != requirementId) continue;
        return _slotsForRule(rule, evidenceType);
      }
    }
    return const [];
  }

  String _mappingKey(
    String requirementId,
    String evidenceType,
    String target,
    String variant,
    String? sourcePackage,
    String? sourceAdapter,
  ) =>
      '$requirementId|$evidenceType|$target|$variant|'
      '${sourcePackage ?? '(missing)'}|${sourceAdapter ?? '(missing)'}';

  String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  Map<String, ParsedRule> _scenarioRules(WorkspaceDiscoveryResult workspace) {
    final result = <String, ParsedRule>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        for (final scenario in rule.scenarios) {
          final tags = <String>{
            ...scenario.tags.map((tag) => tag.name),
            for (final examples in scenario.examples)
              ...examples.tags.map((tag) => tag.name),
          };
          for (final id in tags.where((tag) => tag.startsWith('SCN-'))) {
            result[id] = rule;
          }
        }
      }
    }
    return result;
  }

  Set<String> _executedScenarioIds(
    Iterable<EvidenceRecord> records,
    Set<String> declaredIds,
  ) => {
    for (final record in records) ...[
      if (record.candidateId != null &&
          declaredIds.contains(record.candidateId))
        record.candidateId!,
      ...record.scenarioIds.map((id) => id.value).where(declaredIds.contains),
    ],
  };

  ir.SourceSpan? _sourceSpan(
    WorkspaceDiscoveryResult workspace,
    ParsedRule rule,
  ) {
    final source = rule.metadata.source;
    var path = source.file.replaceAll('\\', '/');
    final root = workspace.config.root?.replaceAll('\\', '/');
    if (root != null && path.startsWith('$root/')) {
      path = path.substring(root.length + 1);
    }
    return ir.SourceSpan(
      path: path,
      startLine: source.line,
      startColumn: source.column,
      endLine: source.line,
      endColumn: source.column,
    );
  }
}

const _builtInEvidenceTypes = <String>{
  'domain-unit',
  'flutter-widget',
  'accessibility-integration',
  'api-contract',
  'performance',
  'gherkin-api',
  'gherkin-ui',
  'security-integration',
  'logging-verification',
  'attestation-freshness',
};
