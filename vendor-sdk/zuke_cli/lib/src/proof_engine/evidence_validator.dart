import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/zuke_core.dart' as ir;

import '../generator.dart';
import 'workspace_digest.dart';
import 'validator.dart';

const _evidenceTargets = <String, String>{
  'domain-unit': 'backend',
  'flutter-widget': 'flutter',
  'api-contract': 'backend',
  'gherkin-api': 'backend',
  'gherkin-ui': 'flutter',
  'security-integration': 'backend',
  'logging-verification': 'backend',
  'accessibility-integration': 'flutter',
  'performance': 'backend',
  'attestation-freshness': 'edge',
};

class EvidenceValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace, {
    List<EvidenceRecord> records = const [],
    List<ControlProofResult> controlProofs = const [],
    List<AdapterOutput> outputs = const [],

    /// The exact scenario IDs selected by the configured execution profile.
    /// A null value retains legacy runner-owned selection behaviour.
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
    final validMappings = <String>{}; // Contains "ruleId|evidenceType|target"
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
          final expectedTarget = _evidenceTargets[type];
          if (expectedTarget == null) continue;
          validMappings.add('$id|$type|$expectedTarget');
        }
      }
    }

    // Iterate and validate records
    for (final record in records) {
      final id = record.requirementId;
      final type = record.evidenceType;
      final target = record.target;

      // ZUKE-EVIDENCE-005: Reject unmapped records
      final mappingKey = '$id|$type|$target';
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
        AdapterOutput? output;
        for (final candidate in outputs) {
          if (candidate.symbols.any(
            (symbol) =>
                (symbol.target == null || symbol.target == target) &&
                (symbol.requirementIds.contains(id) || symbol.bindingId == id),
          )) {
            output = candidate;
            break;
          }
        }
        if (output != null) {
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
    EvidenceRecord record,
    WorkspaceDiscoveryResult workspace,
    String contractDigest,
    String? specificationDigest,
    String? mappingDigest,
    List<AdapterOutput> outputs,
  ) {
    final id = record.requirementId;

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
      AdapterOutput? output;
      for (final candidate in outputs) {
        if (candidate.symbols.any(
          (symbol) =>
              symbol.requirementIds.contains(id) || symbol.bindingId == id,
        )) {
          output = candidate;
          break;
        }
      }
      if (output != null) {
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
    List<AdapterOutput> outputs,
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
    switch (type) {
      case 'domain-unit':
        return _hasPassedEvidence(executionEvidence, id, type, 'backend');
      case 'flutter-widget':
      case 'accessibility-integration':
        return _hasPassedEvidence(executionEvidence, id, type, 'flutter');
      case 'api-contract':
        return _hasPassedEvidence(executionEvidence, id, type, 'backend');
      case 'performance':
        return _hasPassedEvidence(executionEvidence, id, type, 'backend');
      case 'gherkin-api':
        return _hasExecutedEvidence(rule, executionEvidence, 'gherkin-api');
      case 'gherkin-ui':
        return _hasExecutedEvidence(rule, executionEvidence, 'gherkin-ui');
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
            );
      case 'logging-verification':
        return _hasExecutedEvidence(
          rule,
          executionEvidence,
          'logging-verification',
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
    List<EvidenceRecord> records,
    String evidenceType,
  ) {
    final id = rule.metadata.id;
    if (id == null) return false;
    return records.any((record) {
      return record.requirementId == id &&
          record.evidenceType == evidenceType &&
          record.status == EvidenceStatus.passed;
    });
  }

  bool _hasPassedEvidence(
    Iterable<EvidenceRecord> records,
    String? requirementId,
    String evidenceType,
    String target,
  ) => records.any(
    (record) =>
        record.requirementId == requirementId &&
        record.evidenceType == evidenceType &&
        record.target == target &&
        record.status == EvidenceStatus.passed,
  );

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
