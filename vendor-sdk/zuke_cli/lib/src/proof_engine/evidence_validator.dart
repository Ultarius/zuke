import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/zuke_core.dart' as ir;

import '../generator.dart';
import 'workspace_digest.dart';
import 'validator.dart';

class EvidenceValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace, {
    List<SemanticEvidenceRecord> records = const [],
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
              final expectedTarget = slot['target'];
              if (expectedTarget == null) continue;
              validMappings.add(
                _mappingKey(
                  id,
                  type,
                  expectedTarget,
                  slot['variant'] ?? 'default',
                  slot['sourcePackage'],
                  slot['sourceAdapter'],
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
        final output = _sourceOutputForRecord(workspace, record, outputs);
        if (output == null) {
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
            outputs,
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
    SemanticEvidenceRecord record,
    WorkspaceDiscoveryResult workspace,
    String contractDigest,
    String? specificationDigest,
    String? mappingDigest,
    List<IrAdapterOutput> outputs,
  ) {
    final id = record.requirementId;

    final slot = _slotForRequirement(workspace, id, record.evidenceType);
    if (slot != null &&
        (record.variant != (slot['variant'] ?? 'default') ||
            record.sourcePackage != slot['sourcePackage'] ||
            record.sourceAdapter != slot['sourceAdapter'])) {
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
      final output = _sourceOutputForRecord(workspace, record, outputs);
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

  IrAdapterOutput? _sourceOutputForRecord(
    WorkspaceDiscoveryResult workspace,
    SemanticEvidenceRecord record,
    List<IrAdapterOutput> outputs,
  ) {
    final root = workspace.config.root;
    if (root == null ||
        record.sourcePackage == null ||
        record.sourcePackage!.isEmpty) {
      return null;
    }
    final packages = workspace.config.targetPackages[record.target] ?? const [];
    final package = packages.cast<Map?>().firstWhere(
      (candidate) => candidate?['id'] == record.sourcePackage,
      orElse: () => null,
    );
    final packagePath = package?['path'];
    if (packagePath is! String) return null;
    final directory = Directory('$root${Platform.pathSeparator}$packagePath');
    if (!directory.existsSync()) return null;
    final packageRoot = directory.resolveSymbolicLinksSync();
    String canonical(String path) {
      final normalized = path
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/$'), '');
      return Platform.isWindows ? normalized.toLowerCase() : normalized;
    }

    final candidates = outputs
        .where(
          (output) =>
              output.packageRoot != null &&
              canonical(output.packageRoot!) == canonical(packageRoot),
        )
        .toList();
    if (candidates.isEmpty) return null;
    final compatible = candidates
        .where(
          (output) =>
              output.adapter.compatibilityId == record.sourceCompatibilityId,
        )
        .toList();
    final selected = compatible.isNotEmpty ? compatible : candidates;
    return selected.length == 1 ? selected.single : null;
  }

  bool _isSatisfied(
    String type,
    ParsedFeature feature,
    ParsedRule rule,
    WorkspaceDiscoveryResult workspace,
    List<SemanticEvidenceRecord> records,
    List<ControlProofResult> controlProofs,
    String contractDigest,
    String? specificationDigest,
    String? mappingDigest,
    List<IrAdapterOutput> outputs,
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
            outputs,
          ),
        )
        .toList();
    final configuredTarget = _targetForRule(rule, type, workspace);
    final slot = _slotForRule(rule, type);
    final variant = slot?['variant'] ?? 'default';
    final sourcePackage = slot?['sourcePackage'];
    final sourceAdapter = slot?['sourceAdapter'];
    switch (type) {
      case 'domain-unit':
        return _hasPassedEvidence(
          executionEvidence,
          id,
          type,
          configuredTarget ?? 'backend',
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'flutter-widget':
      case 'accessibility-integration':
        return _hasPassedEvidence(
          executionEvidence,
          id,
          type,
          configuredTarget ?? 'flutter',
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'api-contract':
        return _hasPassedEvidence(
          executionEvidence,
          id,
          type,
          configuredTarget ?? 'backend',
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'performance':
        return _hasPassedEvidence(
          executionEvidence,
          id,
          type,
          configuredTarget ?? 'backend',
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'gherkin-api':
        return _hasExecutedEvidence(
          rule,
          executionEvidence,
          'gherkin-api',
          target: configuredTarget,
          variant: variant,
          sourcePackage: sourcePackage,
          sourceAdapter: sourceAdapter,
        );
      case 'gherkin-ui':
        return _hasExecutedEvidence(
          rule,
          executionEvidence,
          'gherkin-ui',
          target: configuredTarget,
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
              executionEvidence,
              'security-integration',
              target: configuredTarget,
              variant: variant,
              sourcePackage: sourcePackage,
              sourceAdapter: sourceAdapter,
            );
      case 'logging-verification':
        return _hasExecutedEvidence(
          rule,
          executionEvidence,
          'logging-verification',
          target: configuredTarget,
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

  bool _hasExecutedEvidence(
    ParsedRule rule,
    List<SemanticEvidenceRecord> records,
    String evidenceType, {
    String? target,
    String variant = 'default',
    String? sourcePackage,
    String? sourceAdapter,
  }) {
    final id = rule.metadata.id;
    if (id == null) return false;
    return records.any((record) {
      return record.requirementId == id &&
          record.evidenceType == evidenceType &&
          record.status == EvidenceStatus.passed &&
          (target == null || record.target == target) &&
          record.variant == variant &&
          (sourcePackage == null || record.sourcePackage == sourcePackage) &&
          (sourceAdapter == null || record.sourceAdapter == sourceAdapter);
    });
  }

  bool _hasPassedEvidence(
    Iterable<SemanticEvidenceRecord> records,
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

  Map<String, String>? _slotForRule(ParsedRule rule, String evidenceType) {
    for (final slot in rule.metadata.evidenceRequirements ?? const []) {
      final type = slot['type'] ?? slot['evidenceType'];
      if (type == evidenceType) return slot;
    }
    return null;
  }

  Map<String, String>? _slotForRequirement(
    WorkspaceDiscoveryResult workspace,
    String requirementId,
    String evidenceType,
  ) {
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (rule.metadata.id != requirementId) continue;
        return _slotForRule(rule, evidenceType);
      }
    }
    return null;
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

  String? _targetForRule(
    ParsedRule rule,
    String evidenceType,
    WorkspaceDiscoveryResult workspace,
  ) {
    for (final slot in rule.metadata.evidenceRequirements ?? const []) {
      final type = slot['type'] ?? slot['evidenceType'];
      if (type == evidenceType && slot['target'] is String) {
        return slot['target'];
      }
    }
    return null;
  }

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
    Iterable<SemanticEvidenceRecord> records,
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
