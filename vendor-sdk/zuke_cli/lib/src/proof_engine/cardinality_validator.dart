import 'package:zuke_frontend/zuke_frontend.dart';
import '../ir.dart';
import 'validator.dart';

class CardinalityValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace, {
    List<ExtractedSymbol> extractedSymbols = const [],
  }) {
    final messages = <ValidationMessage>[];
    final byBindingKey = <String, List<ExtractedSymbol>>{};

    // Index extracted symbols by binding ID
    for (final sym in extractedSymbols) {
      if (sym.bindingId != null) {
        final target = sym.target;
        if (target == null || target.isEmpty) {
          messages.add(
            ValidationMessage(
              code: 'ZK-BINDING-IDENTITY-MISSING',
              message:
                  'Binding provider "${sym.bindingId}" is missing an '
                  'explicit extraction target.',
              severity: Severity.error,
            ),
          );
          continue;
        }
        final key = '${sym.bindingId}|$target|${sym.variant}';
        byBindingKey.putIfAbsent(key, () => []).add(sym);
      }
    }

    for (final feature in workspace.data.features) {
      if (feature.metadata.bindings == null) continue;

      final declared = <String>{};
      for (final binding in feature.metadata.bindings!) {
        if (workspace.config.targetsConfig.isNotEmpty &&
            !workspace.config.targetsConfig.containsKey(binding.target)) {
          messages.add(
            ValidationMessage(
              code: 'ZUKE-CARD-009',
              message:
                  'Binding "${binding.id}" uses unknown target "${binding.target}"',
              severity: Severity.error,
              source: feature.metadata.source,
            ),
          );
        }
        final identity = '${binding.id}|${binding.target}|${binding.variant}';
        if (!declared.add(identity)) {
          messages.add(
            ValidationMessage(
              code: 'ZUKE-CARD-008',
              message:
                  'Duplicate binding declaration "${binding.id}" for target '
                  '"${binding.target}" and variant "${binding.variant}"',
              severity: Severity.error,
              source: feature.metadata.source,
            ),
          );
        }
        final key = identity;
        final providers = byBindingKey[key] ?? [];

        final instanceCardinality = canonicalBindingInstanceCardinality(
          binding.instanceCardinality,
        );
        if (!const {
          'exactlyOne',
          'zeroOrOne',
          'oneOrMore',
          'many',
        }.contains(instanceCardinality)) {
          messages.add(
            ValidationMessage(
              code: 'ZUKE-CARD-010',
              message:
                  'Binding "${binding.id}" has unknown instanceCardinality '
                  '"${binding.instanceCardinality}". Supported values: '
                  'exactlyOne, zeroOrOne, oneOrMore, many (zeroOrMore is '
                  'accepted as an alias for many)',
              severity: Severity.error,
              source: feature.metadata.source,
            ),
          );
        }

        final cardinality = canonicalBindingCardinality(binding.cardinality);
        switch (cardinality) {
          case 'exactlyOne':
            if (providers.isEmpty) {
              messages.add(
                ValidationMessage(
                  code: 'ZUKE-CARD-001',
                  message:
                      'Binding "${binding.id}" requires exactly one provider but none found. '
                      'Declared by ${feature.metadata.id ?? "unknown"}',
                  severity: Severity.error,
                  source: feature.metadata.source,
                ),
              );
            } else if (providers.length > 1) {
              final locations = providers
                  .map((p) => '${p.source.uri}:${p.source.line}')
                  .join(', ');
              messages.add(
                ValidationMessage(
                  code: 'ZUKE-CARD-002',
                  message:
                      'Binding "${binding.id}" requires exactly one provider but ${providers.length} found: $locations',
                  severity: Severity.error,
                  source: feature.metadata.source,
                ),
              );
            } else {
              messages.add(
                ValidationMessage(
                  code: 'ZUKE-CARD-OK',
                  message:
                      'Binding "${binding.id}" has exactly one provider (${providers.first.symbolId})',
                  severity: Severity.info,
                ),
              );
            }
            break;

          case 'oneOrMore':
            if (providers.isEmpty) {
              messages.add(
                ValidationMessage(
                  code: 'ZUKE-CARD-003',
                  message:
                      'Binding "${binding.id}" requires at least one provider but none found',
                  severity: Severity.error,
                  source: feature.metadata.source,
                ),
              );
            }
            break;

          case 'zeroOrOne':
            if (providers.length > 1) {
              messages.add(
                ValidationMessage(
                  code: 'ZUKE-CARD-004',
                  message:
                      'Binding "${binding.id}" allows at most one provider but ${providers.length} found',
                  severity: Severity.error,
                  source: feature.metadata.source,
                ),
              );
            }
            break;

          case 'many':
            // No constraint
            break;

          default:
            messages.add(
              ValidationMessage(
                code: 'ZUKE-CARD-005',
                message:
                    'Binding "${binding.id}" has unknown cardinality "${binding.cardinality}". '
                    'Supported values: exactlyOne, zeroOrOne, oneOrMore, many '
                    '(zeroOrMore is accepted as an alias for many)',
                severity: Severity.warning,
                source: feature.metadata.source,
              ),
            );
        }
      }

      // Check that every Feature has at least one Rule
      if (feature.rules.isEmpty) {
        messages.add(
          ValidationMessage(
            code: 'ZUKE-CARD-006',
            message: 'Feature "${feature.metadata.id}" has no Rules',
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      }

      // Check every Rule has at least one Scenario
      for (final rule in feature.rules) {
        if (rule.scenarios.isEmpty) {
          messages.add(
            ValidationMessage(
              code: 'ZUKE-CARD-007',
              message: 'Rule "${rule.metadata.id}" has no Scenarios',
              severity: Severity.error,
              source: rule.metadata.source,
            ),
          );
        }
      }
    }

    return ValidationResult(
      errors: messages.where((m) => m.severity == Severity.error).toList(),
      warnings: messages.where((m) => m.severity == Severity.warning).toList(),
      infos: messages.where((m) => m.severity == Severity.info).toList(),
    );
  }
}
