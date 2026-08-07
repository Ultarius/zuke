import 'package:zuke_frontend/zuke_frontend.dart';
import 'validator.dart';

class IdentityValidator {
  // Valid ID formats
  static final _idPatterns = {
    RegExp(r'^EPIC-[A-Z]+-\d{3}$'),
    RegExp(r'^FEAT-[A-Z]+-\d{3}$'),
    RegExp(r'^PBI-[A-Z]+-\d{3}$'),
    RegExp(r'^RULE-[A-Z0-9]+-[A-Z0-9]+(-[A-Z0-9]+)*$'),
    RegExp(r'^SCN-[A-Z0-9]+-[A-Z0-9]+(-[A-Z0-9]+)*$'),
    RegExp(r'^CTRL-[A-Z0-9]+-[A-Z0-9]+(-[A-Z0-9]+)*$'),
    RegExp(r'^PERF-[A-Z0-9]+-[A-Z0-9]+(-[A-Z0-9]+)*$'),
  };

  ValidationResult validate(WorkspaceDiscoveryResult workspace) {
    final errors = <ValidationMessage>[];
    final seenIds = <String, SourceLocation>{};
    final retiredIds = <String>{};

    for (final error in workspace.data.errors) {
      errors.add(
        ValidationMessage(
          code: 'ZUKE-DISCOVERY-001',
          message: error,
          severity: Severity.error,
        ),
      );
    }

    // Collect retired IDs from registries
    for (final entry in workspace.data.registries.entries) {
      if (entry.key.startsWith('retired:')) {
        retiredIds.add(entry.key.substring('retired:'.length));
      }
    }

    // Validate IDs from features
    for (final feature in workspace.data.features) {
      for (final metadataError in feature.metadata.errors) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-SCHEMA-001',
            message: metadataError,
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      }
      if (feature.metadata.schemaVersion != '1') {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-SCHEMA-002',
            message: 'Feature metadata schemaVersion must be "1"',
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      }
      // Feature metadata ID
      final featId = feature.metadata.id;
      if (featId == null || !_isValidIdFormat(featId)) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-ID-006',
            message: 'Feature metadata must contain a valid Feature ID',
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      } else {
        _checkDuplicate(
          featId,
          seenIds,
          retiredIds,
          feature.metadata.source,
          errors,
        );
        if (feature.featureElement.title.contains(featId)) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-ID-010',
              message:
                  'Requirement ID "$featId" should not be duplicated in Feature title text; keep IDs in metadata blocks and tags',
              severity: Severity.warning,
              source: feature.featureElement.source,
            ),
          );
        }
      }

      // Epic reference
      final epicId = feature.metadata.epic;
      if (epicId != null && !_isValidIdFormat(epicId)) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-ID-004',
            message: 'Epic ID "$epicId" has invalid format',
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      }

      // Rule IDs
      for (final rule in feature.rules) {
        for (final metadataError in rule.metadata.errors) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-SCHEMA-001',
              message: metadataError,
              severity: Severity.error,
              source: rule.metadata.source,
            ),
          );
        }
        final ruleId = rule.metadata.id;
        if (ruleId == null || !_isValidIdFormat(ruleId)) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-ID-007',
              message: 'Rule metadata must contain a valid Rule ID',
              severity: Severity.error,
              source: rule.metadata.source,
            ),
          );
        } else {
          _checkDuplicate(
            ruleId,
            seenIds,
            retiredIds,
            rule.metadata.source,
            errors,
          );
          if (rule.ruleElement.title.contains(ruleId)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-ID-010',
                message:
                    'Requirement ID "$ruleId" should not be duplicated in Rule title text; keep IDs in metadata blocks and tags',
                severity: Severity.warning,
                source: rule.ruleElement.source,
              ),
            );
          }

          // Verify @RULE-* tag matches metadata ID
          final ruleTags = rule.tags
              .where((t) => t.name.startsWith('RULE-'))
              .map((t) => t.name)
              .toList();
          if (ruleTags.length != 1 || ruleTags.first != ruleId) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-ID-003',
                message:
                    'Rule must have exactly one @RULE-* tag matching metadata ID "$ruleId"',
                severity: Severity.error,
                source: rule.metadata.source,
              ),
            );
          }
        }

        // Scenario IDs
        for (final scenario in rule.scenarios) {
          final scnIds = scenario.tags
              .where((t) => t.name.startsWith('SCN-'))
              .map((t) => t.name);
          final scenarioIdList = scnIds.toList();
          if (scenarioIdList.length != 1) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-ID-008',
                message: 'Scenario must have exactly one @SCN-* tag',
                severity: Severity.error,
                source: scenario.scenarioElement.source,
              ),
            );
          }
          for (final scnId in scenarioIdList) {
            if (!_isValidIdFormat(scnId)) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-ID-009',
                  message: 'Scenario ID "$scnId" has invalid format',
                  severity: Severity.error,
                  source: scenario.scenarioElement.source,
                ),
              );
            }
            _checkDuplicate(
              scnId,
              seenIds,
              retiredIds,
              scenario.scenarioElement.source,
              errors,
            );
          }
        }
      }
    }

    // Check feature tag matches metadata ID
    for (final feature in workspace.data.features) {
      final featId = feature.metadata.id;
      final featureTags = feature.tags
          .where((t) => t.name.startsWith('FEAT-'))
          .map((t) => t.name)
          .toList();
      if (featureTags.length != 1 ||
          (featId != null && featureTags.firstOrNull != featId)) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-ID-002',
            message:
                'Feature must have exactly one @FEAT-* tag matching metadata ID "$featId"',
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      }
    }

    // Check retired ID reuse
    final activeIds = <String>{...seenIds.keys};
    for (final id in activeIds) {
      if (retiredIds.contains(id)) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-ID-005',
            message: 'ID "$id" is retired and must not be reused',
            severity: Severity.error,
          ),
        );
      }
    }

    return ValidationResult(errors: errors);
  }

  void _checkDuplicate(
    String id,
    Map<String, SourceLocation> seen,
    Set<String> retired,
    SourceLocation source,
    List<ValidationMessage> errors,
  ) {
    final first = seen[id];
    if (first != null) {
      errors.add(
        ValidationMessage(
          code: 'ZUKE-ID-001',
          message:
              'Duplicate ID "$id"; first declared at ${first.file}:${first.line}',
          severity: Severity.error,
          source: source,
        ),
      );
    } else {
      seen[id] = source;
    }
  }

  bool _isValidIdFormat(String id) {
    return _idPatterns.any((p) => p.hasMatch(id));
  }
}
