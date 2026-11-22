import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/zuke_core.dart'
    show canonicalJson, sha256Text, writeBytesReplacing;
import 'package:zuke_frontend/zuke_frontend.dart';

const scenarioIdentityRequirement =
    'Declare one @SCN-* tag on the scenario or one on each Examples block.';

bool scenarioHasValidIdentity(GherkinScenario scenario) {
  int idCount(Iterable<GherkinTag> tags) =>
      tags.where((tag) => tag.name.startsWith('SCN-')).length;

  final scenarioIds = idCount(scenario.tags);
  if (scenarioIds > 1) return false;
  if (scenario.examples.isEmpty) return scenarioIds == 1;
  return scenario.examples.every((examples) {
    final exampleIds = idCount(examples.tags);
    return examples.rows.isNotEmpty &&
        (scenarioIds == 1 ? exampleIds <= 1 : exampleIds == 1);
  });
}

bool scenarioRunsOnTarget(Set<String> tags, String target) => switch (target) {
  'backend' => !tags.contains('ui') || tags.contains('api'),
  'flutter' => !tags.contains('api') || tags.contains('ui'),
  _ => true,
};

/// Resolves the configured profile's tag expression against parsed scenarios.
///
/// The selected stable scenario IDs are passed to runners; a profile is not an
/// evidence label and must not silently execute unrelated scenarios.
class ScenarioSelector {
  const ScenarioSelector();

  List<String> select(WorkspaceDiscoveryResult workspace, String profile) {
    return resolve(workspace, profile).scenarioIds;
  }

  ScenarioSelection resolve(
    WorkspaceDiscoveryResult workspace,
    String profile,
  ) {
    _checkOutlineTargets(workspace);
    final profileConfig = workspace.config.executionConfig[profile];
    if (profileConfig is! Map) {
      // A runner may intentionally own selection when no tag expression is
      // configured. This is a current execution mode, not a legacy format.
      return ScenarioSelection.runnerManaged(profile);
    }
    final expression =
        workspace.config.executionProfiles[profile]?.tagExpression ??
        profileConfig['tagExpression'];
    if (expression is! String || expression.trim().isEmpty) {
      throw FormatException(
        'execution profile "$profile" requires a non-empty tagExpression',
      );
    }
    final predicate = _TagExpression.parse(expression);
    final selected = <String>{};
    for (final feature in workspace.data.features) {
      final featureTags = feature.tags.map((tag) => tag.name).toSet();
      for (final rule in feature.rules) {
        final ruleTags = {...featureTags, ...rule.tags.map((tag) => tag.name)};
        for (final scenario in rule.scenarios) {
          final scenarioTags = {
            ...ruleTags,
            ...scenario.tags.map((tag) => tag.name),
          };
          _selectScenario(scenario, scenarioTags, predicate, selected);
        }
      }
    }
    final ordered = selected.toList()..sort();
    if (ordered.isEmpty) {
      throw FormatException(
        'execution profile "$profile" selected no governed scenarios',
      );
    }
    return ScenarioSelection(
      profile: profile,
      tagExpression: expression,
      scenarioIds: ordered,
    );
  }

  void _selectScenario(
    GherkinScenario scenario,
    Set<String> tags,
    _TagExpression predicate,
    Set<String> selected,
  ) {
    final outlineIds = _scenarioIds(scenario.tags).toList();
    final title = scenario.scenarioElement.title;
    if (scenario.examples.isEmpty) {
      if (!predicate.evaluate(tags)) return;
      if (outlineIds.isEmpty) {
        throw FormatException('Selected scenario "$title" has no @SCN-* tag.');
      }
      selected.addAll(outlineIds);
      return;
    }

    final matching = scenario.examples
        .where(
          (block) => predicate.evaluate({
            ...tags,
            ...block.tags.map((tag) => tag.name),
          }),
        )
        .toList();
    final entireOutline = matching.length == scenario.examples.length;
    if (entireOutline) selected.addAll(outlineIds);
    for (final block in matching) {
      final blockIds = _scenarioIds(block.tags).toList();
      if (blockIds.isEmpty && !(entireOutline && outlineIds.isNotEmpty)) {
        throw FormatException(
          'Selected Examples "${block.title}" in "$title" needs its own @SCN-* tag '
          'to run independently.',
        );
      }
      selected.addAll(blockIds);
    }
  }

  void _checkOutlineTargets(WorkspaceDiscoveryResult workspace) {
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        for (final scenario in rule.scenarios) {
          if (_scenarioIds(scenario.tags).isEmpty ||
              scenario.examples.isEmpty) {
            continue;
          }
          final outlineTags = scenario.tags
              .map((tag) => tag.name.toLowerCase())
              .toSet();
          for (final block in scenario.examples) {
            final tags = {
              ...outlineTags,
              ...block.tags.map((tag) => tag.name.toLowerCase()),
            };
            if (['backend', 'flutter'].any(
              (target) =>
                  scenarioRunsOnTarget(tags, target) !=
                  scenarioRunsOnTarget(outlineTags, target),
            )) {
              throw FormatException(
                'Examples "${block.title}" changes the execution target of '
                '"${scenario.scenarioElement.title}". Give each Examples block '
                'its own @SCN-* tag and omit the outline-level ID.',
              );
            }
          }
        }
      }
    }
  }

  Iterable<String> _scenarioIds(Iterable<GherkinTag> tags) =>
      tags.map((tag) => tag.name).where((name) => name.startsWith('SCN-'));
}

/// Immutable, deterministic provenance for a single profile selection. This is
/// written only after all configured runners have succeeded, alongside the
/// evidence observation; it is never an input that can make a later run pass.
class ScenarioSelection {
  static const kind = 'zuke.scenario-selection';

  final String profile;
  final String? tagExpression;
  final List<String> scenarioIds;
  final String digest;

  ScenarioSelection({
    required this.profile,
    required String tagExpression,
    required List<String> scenarioIds,
  }) : tagExpression = tagExpression,
       scenarioIds = List.unmodifiable([...scenarioIds]..sort()),
       digest = _digest(profile, tagExpression, scenarioIds);

  const ScenarioSelection._runnerManaged(this.profile)
    : tagExpression = null,
      scenarioIds = const [],
      digest = 'sha256:runner-managed-selection';

  factory ScenarioSelection.runnerManaged(String profile) =>
      ScenarioSelection._runnerManaged(profile);

  Map<String, Object?> toJson() => {
    'kind': kind,
    'profile': profile,
    if (tagExpression == null) 'selectionMode': 'runner-managed',
    if (tagExpression != null) 'tagExpression': tagExpression,
    'scenarioIds': scenarioIds,
    'digest': digest,
  };

  void writeAtomic(File output) {
    writeBytesReplacing(
      output,
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(toJson())}\n'),
    );
  }

  static String _digest(
    String profile,
    String expression,
    List<String> scenarioIds,
  ) {
    final body = <String, Object?>{
      'kind': kind,
      'profile': profile,
      'tagExpression': expression,
      'scenarioIds': [...scenarioIds]..sort(),
    };
    return sha256Text(canonicalJson(body));
  }
}

class _TagExpression {
  final List<String> _tokens;
  int _offset = 0;

  _TagExpression._(this._tokens);

  static _TagExpression parse(String source) {
    final tokens = <String>[];
    final token = RegExp(
      r'@[A-Za-z0-9_.-]+|\(|\)|\bnot\b|\band\b|\bor\b',
      caseSensitive: false,
    );
    var position = 0;
    for (final match in token.allMatches(source)) {
      if (source.substring(position, match.start).trim().isNotEmpty) {
        throw FormatException(
          'invalid tag expression near "${source.substring(position)}"',
        );
      }
      tokens.add(match.group(0)!);
      position = match.end;
    }
    if (source.substring(position).trim().isNotEmpty || tokens.isEmpty) {
      throw FormatException('invalid tag expression "$source"');
    }
    final result = _TagExpression._(tokens);
    result._parseOr();
    if (result._offset != tokens.length) {
      throw FormatException('unexpected token "${tokens[result._offset]}"');
    }
    return _TagExpression._(tokens);
  }

  bool evaluate(Set<String> tags) {
    _offset = 0;
    final result = _parseOr(tags);
    if (_offset != _tokens.length) {
      throw FormatException('unexpected token "${_tokens[_offset]}"');
    }
    return result;
  }

  bool _parseOr([Set<String>? tags]) {
    var value = _parseAnd(tags);
    while (_consume('or')) {
      final right = _parseAnd(tags);
      // Use non-short-circuit operators: parsing must consume and validate the
      // right operand even when the current value already determines truth.
      value = value | right;
    }
    return value;
  }

  bool _parseAnd([Set<String>? tags]) {
    var value = _parseUnary(tags);
    while (_consume('and')) {
      final right = _parseUnary(tags);
      value = value & right;
    }
    return value;
  }

  bool _parseUnary(Set<String>? tags) {
    if (_consume('not')) return !_parseUnary(tags);
    return _parsePrimary(tags);
  }

  bool _parsePrimary(Set<String>? tags) {
    if (_consume('(')) {
      final value = _parseOr(tags);
      if (!_consume(')')) {
        throw const FormatException('expected closing parenthesis');
      }
      return value;
    }
    if (_offset >= _tokens.length || !_tokens[_offset].startsWith('@')) {
      throw const FormatException('expected a tag or parenthesized expression');
    }
    final tag = _tokens[_offset++].substring(1);
    return tags?.contains(tag) ?? false;
  }

  bool _consume(String expected) {
    if (_offset >= _tokens.length ||
        _tokens[_offset].toLowerCase() != expected.toLowerCase()) {
      return false;
    }
    _offset++;
    return true;
  }
}
