import 'package:zuke_core/zuke_core.dart';
import 'scenario_contract.dart';

/// Matches generated scenario contracts without repeating raw IDs.
sealed class ZukeScenarioPattern {
  const ZukeScenarioPattern();

  factory ZukeScenarioPattern.regExp(RegExp expression) = _RegExpPattern;
  factory ZukeScenarioPattern.glob(String expression) = _GlobPattern;
  factory ZukeScenarioPattern.exact(ScenarioId id) = _ExactPattern;
  factory ZukeScenarioPattern.prefix(String value) = _PrefixPattern;
  factory ZukeScenarioPattern.ruleId(String id) = _RulePattern;

  factory ZukeScenarioPattern.from(Object pattern) => switch (pattern) {
    ZukeScenarioPattern() => pattern,
    RegExp() => ZukeScenarioPattern.regExp(pattern),
    String() => ZukeScenarioPattern.glob(pattern),
    _ => throw ArgumentError.value(
      pattern,
      'pattern',
      'Only String globs, RegExp patterns, and ZukeScenarioPattern instances are supported',
    ),
  };

  bool matches(ZukeScenarioContract contract);
}

final class _RegExpPattern extends ZukeScenarioPattern {
  final RegExp expression;
  const _RegExpPattern(this.expression);
  @override
  bool matches(ZukeScenarioContract contract) =>
      expression.hasMatch(contract.id.value);
}

final class _GlobPattern extends ZukeScenarioPattern {
  final RegExp _expression;
  _GlobPattern(String glob) : _expression = _compile(glob);

  static RegExp _compile(String glob) {
    if (glob.isEmpty)
      throw ArgumentError.value(glob, 'glob', 'Must not be empty');
    final buffer = StringBuffer('^');
    for (final rune in glob.runes) {
      final character = String.fromCharCode(rune);
      if (character == '*') {
        buffer.write('.*');
      } else if (character == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(character));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  @override
  bool matches(ZukeScenarioContract contract) =>
      _expression.hasMatch(contract.id.value);
}

final class _ExactPattern extends ZukeScenarioPattern {
  final ScenarioId id;
  const _ExactPattern(this.id);
  @override
  bool matches(ZukeScenarioContract contract) => contract.id == id;
}

final class _PrefixPattern extends ZukeScenarioPattern {
  final String value;
  _PrefixPattern(this.value) : assert(value.isNotEmpty);
  @override
  bool matches(ZukeScenarioContract contract) =>
      contract.id.value.startsWith(value);
}

final class _RulePattern extends ZukeScenarioPattern {
  final String id;
  const _RulePattern(this.id);
  @override
  bool matches(ZukeScenarioContract contract) => contract.requirementId == id;
}
