import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/zuke_core.dart' show canonicalJson;
import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

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
    final profileConfig = workspace.config.executionConfig[profile];
    if (profileConfig is! Map) {
      // Older workspaces can have runners without profile declarations. They
      // retain their runner-owned selection semantics until they opt in.
      return ScenarioSelection.legacy(profile);
    }
    final expression = profileConfig['tagExpression'];
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
          final effectiveTagSets = scenario.examples.isEmpty
              ? [scenarioTags]
              : scenario.examples
                    .map(
                      (examples) => {
                        ...scenarioTags,
                        ...examples.tags.map((tag) => tag.name),
                      },
                    )
                    .toList();
          for (final tags in effectiveTagSets) {
            if (!predicate.evaluate(tags)) continue;
            final scenarioIds =
                tags.where((tag) => tag.startsWith('SCN-')).toList()..sort();
            if (scenarioIds.isEmpty) {
              throw FormatException(
                'selected scenario "${scenario.scenarioElement.title}" has no SCN-* tag',
              );
            }
            selected.addAll(scenarioIds);
          }
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
}

/// Immutable, deterministic provenance for a single profile selection. This is
/// written only after all configured runners have succeeded, alongside the
/// evidence observation; it is never an input that can make a later run pass.
class ScenarioSelection {
  static const schemaVersion = 'zuke.scenario-selection.v1';

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

  const ScenarioSelection._legacy(this.profile)
    : tagExpression = null,
      scenarioIds = const [],
      digest = 'sha256:legacy-runner-selection';

  factory ScenarioSelection.legacy(String profile) =>
      ScenarioSelection._legacy(profile);

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'profile': profile,
    if (tagExpression != null) 'tagExpression': tagExpression,
    'scenarioIds': scenarioIds,
    'digest': digest,
  };

  void writeAtomic(File output) {
    output.parent.createSync(recursive: true);
    final temporary = File('${output.path}.tmp-${pid}');
    temporary.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(toJson()) + '\n',
      flush: true,
    );
    temporary.renameSync(output.path);
  }

  static String _digest(
    String profile,
    String expression,
    List<String> scenarioIds,
  ) {
    final body = <String, Object?>{
      'schemaVersion': schemaVersion,
      'profile': profile,
      'tagExpression': expression,
      'scenarioIds': [...scenarioIds]..sort(),
    };
    return 'sha256:${sha256.convert(utf8.encode(canonicalJson(body)))}';
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
      if (!_consume(')'))
        throw const FormatException('expected closing parenthesis');
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
