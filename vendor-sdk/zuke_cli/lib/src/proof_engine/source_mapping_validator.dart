import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'validator.dart';

/// Validates semantic fragments after source adapters have run.  This pass is
/// intentionally framework-neutral: adapters only emit normalized symbols;
/// cardinality and identity decisions remain here.
class SourceMappingValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace,
    List<IrAdapterOutput> outputs,
  ) {
    final errors = <ValidationMessage>[];
    final rules = <String>{};
    final scenarios = <String>{};
    final controls = workspace.data.controls.keys.toSet();
    final bindings = <String, ParsedBinding>{};
    final bindingProviders = <String, List<ExtractedSymbol>>{};
    final providers = <String, List<ExtractedSymbol>>{};

    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final id = rule.metadata.id;
        if (id != null) rules.add(id);
        for (final scenario in rule.scenarios) {
          for (final tag in scenario.tags.where(
            (t) => t.name.startsWith('SCN-'),
          )) {
            scenarios.add(tag.name);
          }
        }
      }
      for (final binding
          in feature.metadata.bindings ?? const <ParsedBinding>[]) {
        bindings[binding.id] = binding;
      }
    }

    for (final output in outputs) {
      for (final extractionError in output.errors) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-EXTRACT-001',
            message: extractionError,
            severity: Severity.error,
          ),
        );
      }
      if (output.completeness.annotationTargets != CompletenessValue.complete) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-EXTRACT-INCOMPLETE',
            message:
                '${output.adapter.id} produced an incomplete annotation fragment',
            severity: Severity.error,
          ),
        );
      }
      for (final symbol in output.symbols) {
        for (final id in symbol.requirementIds) {
          if (!rules.contains(id) && !scenarios.contains(id)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-MAP-UNKNOWN-REQUIREMENT',
                message:
                    '${symbol.symbolId} references unknown requirement "$id"',
                severity: Severity.error,
              ),
            );
          }
        }
        for (final id in symbol.controlIds) {
          if (!controls.contains(id)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-MAP-UNKNOWN-CONTROL',
                message: '${symbol.symbolId} references unknown control "$id"',
                severity: Severity.error,
              ),
            );
          } else {
            providers.putIfAbsent(id, () => []).add(symbol);
            final definition = workspace.data.controls[id];
            final acceptableKinds =
                (definition?['acceptableProviderKinds'] as List?)
                    ?.map((value) => value.toString())
                    .toSet() ??
                const <String>{};
            final normalizedKind = symbol.providerKind == null
                ? null
                : symbol.providerKind!.replaceAllMapped(
                    RegExp(r'([a-z])([A-Z])'),
                    (match) =>
                        '${match.group(1)}-${match.group(2)!.toLowerCase()}',
                  );
            if (acceptableKinds.isNotEmpty &&
                (normalizedKind == null ||
                    !acceptableKinds.contains(normalizedKind))) {
              errors.add(
                ValidationMessage(
                  code: 'CONTROL-PROVIDER-002',
                  message:
                      '${symbol.symbolId} provides $id with unsupported provider kind "${symbol.providerKind}"',
                  severity: Severity.error,
                  source: SourceLocation(
                    file: symbol.source.uri,
                    line: symbol.source.line,
                  ),
                ),
              );
            }
            final prohibitedTargets =
                (definition?['prohibitedProviderTargets'] as List?)
                    ?.map((value) => value.toString())
                    .toSet() ??
                const <String>{};
            if (prohibitedTargets.contains(symbol.role)) {
              errors.add(
                ValidationMessage(
                  code: 'CONTROL-PROVIDER-003',
                  message:
                      '${symbol.symbolId} is in prohibited provider target "${symbol.role}" for $id',
                  severity: Severity.error,
                  source: SourceLocation(
                    file: symbol.source.uri,
                    line: symbol.source.line,
                  ),
                ),
              );
            }
          }
        }
        if (symbol.bindingId != null) {
          final bindingId = symbol.bindingId!;
          if (!bindings.containsKey(bindingId)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-MAP-UNKNOWN-BINDING',
                message:
                    '${symbol.symbolId} provides unknown binding "$bindingId"',
                severity: Severity.error,
              ),
            );
          } else {
            bindingProviders.putIfAbsent(bindingId, () => []).add(symbol);
          }
        }
      }
    }

    for (final entry in bindings.entries) {
      final binding = entry.value;
      final candidates =
          bindingProviders[entry.key] ?? const <ExtractedSymbol>[];
      final count = candidates.length;
      final cardinality = canonicalBindingCardinality(binding.cardinality);
      final invalid = switch (cardinality) {
        'exactlyOne' => count != 1,
        'zeroOrOne' => count > 1,
        'oneOrMore' => count < 1,
        _ => false,
      };
      if (invalid) {
        final locations = candidates
            .map((c) => '${c.source.uri}:${c.source.line}')
            .join(', ');
        errors.add(
          ValidationMessage(
            code: count == 0
                ? 'ZUKE-MAP-MISSING-BINDING'
                : 'ZUKE-MAP-DUPLICATE-BINDING',
            message:
                'Binding "${entry.key}" requires $cardinality but has $count provider(s)${locations.isEmpty ? '' : ': $locations'}',
            severity: Severity.error,
          ),
        );
      }
    }

    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final ruleId = rule.metadata.id;
        if (ruleId == null) continue;
        for (final control
            in rule.metadata.requires ?? const <ParsedControlRef>[]) {
          final candidates = providers[control.id] ?? const <ExtractedSymbol>[];
          final attestation = _attestation(
            workspace,
            control.id,
            targetScope: control.target,
          );
          final acceptsAttested =
              control.acceptableAssurance?.contains('attested') ?? false;
          final satisfied =
              candidates.isNotEmpty || (acceptsAttested && attestation != null);
          final cardinality = control.cardinality;
          final cardinalityViolation =
              (cardinality == 'exactlyOne' && candidates.length > 1) ||
              (cardinality == 'zeroOrOne' && candidates.length > 1) ||
              (cardinality == 'oneOrMore' && candidates.isEmpty && !satisfied);
          if (cardinalityViolation) {
            errors.add(
              ValidationMessage(
                code: 'CONTROL-CARDINALITY-001',
                message:
                    '$ruleId requires ${control.id} with cardinality $cardinality but found ${candidates.length} providers',
                severity: Severity.error,
                source: rule.metadata.source,
              ),
            );
          }
          if (!satisfied) {
            errors.add(
              ValidationMessage(
                code: 'CONTROL-PROVIDER-001',
                message:
                    '$ruleId requires ${control.id}, but no provider was extracted',
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

  Map<String, dynamic>? _attestation(
    WorkspaceDiscoveryResult workspace,
    String controlId, {
    String? targetScope,
  }) {
    final now = DateTime.now().toUtc();
    for (final policy in workspace.data.policies.values) {
      final providers = policy['providers'];
      if (providers is! List) continue;
      for (final provider in providers) {
        if (provider is! Map || provider['provides'] != controlId) continue;
        final required = [
          'id',
          'owner',
          'reference',
          'attestedAt',
          'expiresAt',
        ];
        if (required.any((key) => provider[key] == null)) return null;
        final expiry = DateTime.tryParse(provider['expiresAt'].toString());
        if (expiry == null || !expiry.isAfter(now)) return null;
        if (provider['assurance'] != 'attested') return null;
        if (targetScope != null &&
            targetScope.isNotEmpty &&
            provider['layer'] != null &&
            provider['layer'] != targetScope &&
            provider['target'] != targetScope) {
          return null;
        }
        return Map<String, dynamic>.from(provider);
      }
    }
    return null;
  }
}
