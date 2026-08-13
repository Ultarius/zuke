import 'package:zuke_frontend/zuke_frontend.dart';
import '../ir.dart';
import 'validator.dart';

class ReferenceResolver {
  ValidationResult validate(WorkspaceDiscoveryResult workspace) {
    final errors = <ValidationMessage>[];

    final knownEpics = workspace.data.epics.keys.toSet();
    final knownControls = workspace.data.controls.keys.toSet();
    final knownRegistries = workspace.data.registries.keys.toSet();

    _validateReferenceCycles(workspace, errors);
    _validateProviderClaims(workspace, errors);

    for (final feature in workspace.data.features) {
      for (final target in feature.metadata.targets ?? const <String>[]) {
        if (!workspace.config.targetsConfig.containsKey(target)) {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-REF-009',
              message:
                  'Unknown target "$target" referenced by ${feature.metadata.id}',
              severity: Severity.error,
              source: feature.metadata.source,
            ),
          );
        }
      }
      // Target validation requires config.targets parsing — stubbed until ZukeConfig is extended.
      // Check epic reference
      if (feature.metadata.epic != null &&
          !knownEpics.contains(feature.metadata.epic)) {
        errors.add(
          ValidationMessage(
            code: 'ZUKE-REF-001',
            message:
                'Unknown Epic "${feature.metadata.epic}" referenced by ${feature.metadata.id}',
            severity: Severity.error,
            source: feature.metadata.source,
          ),
        );
      }

      // Check PBI references
      if (feature.metadata.pbis != null) {
        for (final pbi in feature.metadata.pbis!) {
          final registered = workspace.data.registries[pbi];
          if (registered == null) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-002',
                message:
                    'Unknown PBI "$pbi" referenced by ${feature.metadata.id}',
                severity: Severity.error,
                source: feature.metadata.source,
              ),
            );
          } else {
            final targetFeature = registered['feature']?.toString();
            if (targetFeature != null && targetFeature != feature.metadata.id) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-REF-004',
                  message:
                      'PBI "$pbi" registry back-reference "$targetFeature" does not match declaring feature "${feature.metadata.id}"',
                  severity: Severity.error,
                  source: feature.metadata.source,
                ),
              );
            }
          }
        }
      }

      // Check endpoint references
      if (feature.metadata.endpoints != null) {
        for (final ep in feature.metadata.endpoints!) {
          final registered = workspace.data.registries[ep.id];
          if (registered == null) {
            // Check if it's defined in the feature itself (ownership)
            // Feature defines its own endpoints, the registry is canonical
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-003',
                message:
                    'Endpoint "${ep.id}" referenced by ${feature.metadata.id} is not registered',
                severity: Severity.error,
                source: feature.metadata.source,
              ),
            );
          } else {
            final owner =
                registered['ownerFeature'] ??
                registered['owningFeature'] ??
                registered['feature'];
            if (ep.usage != 'reference' &&
                owner != null &&
                owner != feature.metadata.id) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-REF-010',
                  message:
                      'Endpoint "${ep.id}" is owned by "$owner"; declare usage: reference when reusing it',
                  severity: Severity.error,
                  source: feature.metadata.source,
                ),
              );
            }
            for (final pair in <String, String?>{
              'target': ep.target,
              'method': ep.method,
              'contract': ep.contract,
            }.entries) {
              final expected = pair.value;
              if (expected != null &&
                  registered[pair.key] != null &&
                  registered[pair.key].toString() != expected) {
                errors.add(
                  ValidationMessage(
                    code: 'ZUKE-REF-011',
                    message:
                        'Endpoint "${ep.id}" ${pair.key} "$expected" does not match registry value "${registered[pair.key]}"',
                    severity: Severity.error,
                    source: feature.metadata.source,
                  ),
                );
              }
            }
          }
        }
      }

      if (feature.metadata.endpoints != null) {
        for (final endpoint in feature.metadata.endpoints!) {
          if (!workspace.config.targetsConfig.containsKey(endpoint.target)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-009',
                message: 'Unknown endpoint target "${endpoint.target}"',
                severity: Severity.error,
                source: feature.metadata.source,
              ),
            );
          }
        }
      }

      // Check event references
      if (feature.metadata.events != null) {
        for (final eventId in feature.metadata.events!) {
          if (!knownRegistries.contains(eventId)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-004',
                message:
                    'Unknown event "$eventId" referenced by ${feature.metadata.id}',
                severity: Severity.error,
                source: feature.metadata.source,
              ),
            );
          }
        }
      }

      // Check feature flag references
      if (feature.metadata.featureFlags != null) {
        for (final flagId in feature.metadata.featureFlags!) {
          if (!knownRegistries.contains(flagId)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-005',
                message:
                    'Unknown feature flag "$flagId" referenced by ${feature.metadata.id}',
                severity: Severity.error,
                source: feature.metadata.source,
              ),
            );
          }
        }
      }

      // Check performance profile references
      if (feature.metadata.performance != null) {
        for (final perf in feature.metadata.performance!) {
          if (!knownRegistries.contains(perf.profile)) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-006',
                message:
                    'Unknown performance profile "${perf.profile}" referenced by ${feature.metadata.id}',
                severity: Severity.error,
                source: feature.metadata.source,
              ),
            );
          }
        }
      }

      // Check control references in rules
      for (final rule in feature.rules) {
        if (rule.metadata.requires != null) {
          for (final ctrlRef in rule.metadata.requires!) {
            if (!knownControls.contains(ctrlRef.id)) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-REF-007',
                  message:
                      'Unknown control "${ctrlRef.id}" required by ${rule.metadata.id}',
                  severity: Severity.error,
                  source: rule.metadata.source,
                ),
              );
            }
            try {
              Cardinality.parse(ctrlRef.cardinality);
            } catch (_) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-REF-012',
                  message:
                      'Invalid control cardinality "${ctrlRef.cardinality}"',
                  severity: Severity.error,
                  source: rule.metadata.source,
                ),
              );
            }
            if (!workspace.config.targetsConfig.containsKey(ctrlRef.target)) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-REF-009',
                  message:
                      'Unknown control target "${ctrlRef.target}" for ${ctrlRef.id}',
                  severity: Severity.error,
                  source: rule.metadata.source,
                ),
              );
            }
          }
        }

        // Check security profile
        if (rule.metadata.securityProfile != null) {
          final profileName = rule.metadata.securityProfile;
          // Security profiles are defined in policies
          final found = workspace.data.policies.values.any((p) {
            final profiles = p['securityProfiles'] as Map?;
            return profiles != null && profiles.containsKey(profileName);
          });
          if (!found) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-REF-008',
                message:
                    'Unknown security profile "$profileName" referenced by ${rule.metadata.id}',
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

  void _validateReferenceCycles(
    WorkspaceDiscoveryResult workspace,
    List<ValidationMessage> errors,
  ) {
    final graph = <String, Set<String>>{};
    void addEdge(String from, String to) {
      graph.putIfAbsent(from, () => {}).add(to);
    }

    String nodeIdFor(String id) {
      if (id.startsWith('EPIC-')) return 'epic:$id';
      if (id.startsWith('FEAT-')) return 'feature:$id';
      if (id.startsWith('PBI-')) return 'pbi:$id';
      if (id.startsWith('RULE-')) return 'rule:$id';
      if (id.startsWith('SCN-')) return 'scenario:$id';
      if (id.startsWith('CTRL-')) return 'control:$id';
      if (id.startsWith('PERF-')) return 'performance:$id';
      return 'unknown:$id';
    }

    void addYamlDeps(
      String defaultPrefix,
      Map<String, Map<String, dynamic>> values,
    ) {
      for (final entry in values.entries) {
        final fromNode = nodeIdFor(entry.key);
        for (final field in ['dependsOn', 'supersedes', 'requires']) {
          final raw = entry.value[field];
          final refs = raw is List
              ? raw.cast<Object>()
              : raw is String
              ? [raw]
              : const <Object>[];
          for (final refObj in refs) {
            String? refStr;
            if (refObj is String) {
              refStr = refObj;
            } else if (refObj is Map && refObj.containsKey('id')) {
              refStr = refObj['id']?.toString();
            }
            if (refStr != null && refStr.isNotEmpty) {
              addEdge(fromNode, nodeIdFor(refStr));
            }
          }
        }
      }
    }

    addYamlDeps('epic', workspace.data.epics);
    addYamlDeps('control', workspace.data.controls);
    addYamlDeps('registry', workspace.data.registries);
    addYamlDeps('policy', workspace.data.policies);

    for (final feature in workspace.data.features) {
      final featureId = feature.metadata.id;
      if (featureId == null) continue;
      final featureNode = nodeIdFor(featureId);

      if (feature.metadata.epic != null) {
        addEdge(featureNode, nodeIdFor(feature.metadata.epic!));
      }

      if (feature.metadata.pbis != null) {
        for (final pbi in feature.metadata.pbis!) {
          addEdge(featureNode, nodeIdFor(pbi));
        }
      }

      for (final rule in feature.rules) {
        final ruleId = rule.metadata.id;
        if (ruleId == null) continue;
        final ruleNode = nodeIdFor(ruleId);

        addEdge(ruleNode, featureNode);

        if (rule.metadata.pbis != null) {
          for (final pbi in rule.metadata.pbis!) {
            addEdge(ruleNode, nodeIdFor(pbi));
          }
        }
        for (final tag in rule.tags) {
          if (tag.name.startsWith('PBI-')) {
            addEdge(ruleNode, nodeIdFor(tag.name));
          }
        }

        if (rule.metadata.requires != null) {
          for (final ctrlRef in rule.metadata.requires!) {
            addEdge(ruleNode, nodeIdFor(ctrlRef.id));
          }
        }
        final profile = rule.metadata.securityProfile;
        if (profile != null) {
          for (final policy in workspace.data.policies.values) {
            final profiles = policy['securityProfiles'];
            final definition = profiles is Map ? profiles[profile] : null;
            final requires = definition is Map ? definition['requires'] : null;
            if (requires is! List) continue;
            for (final raw in requires.whereType<Map>()) {
              final controlId = raw['id']?.toString();
              if (controlId != null && controlId.isNotEmpty) {
                addEdge(ruleNode, nodeIdFor(controlId));
              }
            }
          }
        }

        for (final scenario in rule.scenarios) {
          final scenarioId = scenario.tags
              .where((t) => t.name.startsWith('SCN-'))
              .map((t) => t.name)
              .firstOrNull;
          if (scenarioId != null) {
            final scenarioNode = nodeIdFor(scenarioId);
            addEdge(scenarioNode, ruleNode);
          }
        }
      }
    }

    for (final entry in workspace.data.registries.entries) {
      if (entry.key.startsWith('PBI-') ||
          entry.value['_sourceList'] == 'pbis') {
        final pbiNode = nodeIdFor(entry.key);
        final feat = entry.value['feature'];
        if (feat != null) {
          addEdge(nodeIdFor(feat.toString()), pbiNode);
        }
      }
    }

    final visiting = <String>{};
    final visited = <String>{};
    void visit(String node, List<String> path) {
      if (visiting.contains(node)) {
        final cyclePath = [...path, node];
        final cleanPath = cyclePath.map((n) {
          final idx = n.indexOf(':');
          return idx >= 0 ? n.substring(idx + 1) : n;
        }).toList();
        errors.add(
          ValidationMessage(
            code: 'ZUKE-REF-CYCLE',
            message: 'Reference cycle detected: ${cleanPath.join(' -> ')}',
            severity: Severity.error,
          ),
        );
        return;
      }
      if (!visited.add(node)) return;
      visiting.add(node);
      for (final next in graph[node] ?? const <String>{}) {
        visit(next, [...path, node]);
      }
      visiting.remove(node);
    }

    for (final node in graph.keys) {
      visit(node, const []);
    }
  }

  void _validateProviderClaims(
    WorkspaceDiscoveryResult workspace,
    List<ValidationMessage> errors,
  ) {
    for (final policy in workspace.data.policies.values) {
      final providers = policy['providers'];
      if (providers is! List) continue;
      for (final provider in providers.whereType<Map>()) {
        final id = provider['id']?.toString() ?? '<unnamed-provider>';
        final assurance = provider['assurance']?.toString();
        if (assurance != 'proven' && assurance != 'attested') {
          errors.add(
            ValidationMessage(
              code: 'ZUKE-PROVIDER-001',
              message: 'Provider "$id" has invalid assurance "$assurance"',
              severity: Severity.error,
            ),
          );
        }
        if (assurance == 'attested') {
          for (final field in ['owner', 'reference', 'evidence', 'expiresAt']) {
            if (!provider.containsKey(field)) {
              errors.add(
                ValidationMessage(
                  code: 'ZUKE-PROVIDER-002',
                  message: 'Attested provider "$id" is missing $field',
                  severity: Severity.error,
                ),
              );
            }
          }
          final expiry = DateTime.tryParse(
            provider['expiresAt']?.toString() ?? '',
          );
          if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
            errors.add(
              ValidationMessage(
                code: 'ZUKE-PROVIDER-003',
                message:
                    'Attested provider "$id" is expired or has an invalid expiry',
                severity: Severity.error,
              ),
            );
          }
        }
      }
    }
  }
}
