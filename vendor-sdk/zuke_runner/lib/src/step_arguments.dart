import 'dart:async';

/// A typed transformation used by generated Gherkin step support.
final class StepParameterType<T> {
  final String name;
  final List<RegExp> expressions;
  final bool useForSnippets;
  final bool preferForRegexpMatch;
  final int snippetPriority;
  final FutureOr<T> Function(List<String?> captures) transform;

  const StepParameterType({
    required this.name,
    required this.expressions,
    required this.transform,
    this.useForSnippets = false,
    this.preferForRegexpMatch = false,
    this.snippetPriority = 0,
  });
}

/// Registry for Cucumber-style parameter transformations.
final class StepParameterTypeRegistry {
  final Map<String, StepParameterType<Object?>> _types = {};

  StepParameterTypeRegistry.standard() {
    define<String>(
      StepParameterType(
        name: 'string',
        expressions: [
          RegExp(r'^"((?:[^"\\]|\\.)*)"$'),
          RegExp("^'((?:[^'\\\\]|\\\\.)*)'\$"),
        ],
        useForSnippets: true,
        transform: (captures) => (captures.first ?? '')
            .replaceAll(r'\"', '"')
            .replaceAll(r"\'", "'"),
      ),
    );
    define<int>(
      StepParameterType(
        name: 'int',
        expressions: [RegExp(r'^[-+]?\d+$')],
        useForSnippets: true,
        snippetPriority: 20,
        transform: (captures) => int.parse(captures.first!),
      ),
    );
    define<double>(
      StepParameterType(
        name: 'double',
        expressions: [
          RegExp(r'^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$'),
        ],
        useForSnippets: true,
        snippetPriority: 10,
        transform: (captures) => double.parse(captures.first!),
      ),
    );
    define<double>(
      StepParameterType(
        name: 'float',
        expressions: [
          RegExp(r'^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$'),
        ],
        useForSnippets: true,
        snippetPriority: 10,
        transform: (captures) => double.parse(captures.first!),
      ),
    );
    define<String>(
      StepParameterType(
        name: 'word',
        expressions: [RegExp(r'^\S+$')],
        transform: (captures) => captures.first ?? '',
      ),
    );
  }

  void define<T>(StepParameterType<T> type) {
    if (type.name.isEmpty || _types.containsKey(type.name)) {
      throw ArgumentError.value(type.name, 'name', 'Duplicate parameter type');
    }
    if (type.snippetPriority < 0) {
      throw ArgumentError.value(type.snippetPriority, 'snippetPriority');
    }
    _types[type.name] = type as StepParameterType<Object?>;
  }

  StepParameterType<T> type<T>(String name) {
    final value = _types[name];
    if (value == null)
      throw ArgumentError.value(name, 'name', 'Unknown parameter type');
    return value as StepParameterType<T>;
  }

  Iterable<StepParameterType<Object?>> get types => _types.values;
}

/// A compiled Cucumber Expression.  It deliberately keeps the feature text
/// plain: placeholders are automation glue, not feature metadata.
final class CucumberExpression {
  final String source;
  final RegExp pattern;
  final List<StepParameterType<Object?>> parameterTypes;
  final List<_CaptureRange> _captureRanges;

  CucumberExpression._({
    required this.source,
    required this.pattern,
    required this.parameterTypes,
    required List<_CaptureRange> captureRanges,
  }) : _captureRanges = captureRanges;

  factory CucumberExpression(
    String expression,
    StepParameterTypeRegistry registry,
  ) {
    final types = <StepParameterType<Object?>>[];
    final ranges = <_CaptureRange>[];
    return CucumberExpression._(
      source: expression,
      pattern: _compile(expression, registry, ranges, types),
      parameterTypes: types,
      captureRanges: ranges,
    );
  }

  static RegExp _compile(
    String expression,
    StepParameterTypeRegistry registry,
    List<_CaptureRange> ranges,
    List<StepParameterType<Object?>> types,
  ) {
    final output = StringBuffer('^');
    var offset = 0;
    var groupOffset = 0;
    final placeholder = RegExp(r'\{([^}]*)\}');
    for (final match in placeholder.allMatches(expression)) {
      output.write(RegExp.escape(expression.substring(offset, match.start)));
      final name = match.group(1)!;
      final type = name.isEmpty
          ? registry.type<String>('word')
          : registry.type<Object?>(name);
      // Cucumber permits a type to provide alternatives. Runtime resolution
      // selects the first matching one, while the generated regular expression
      // keeps the alternatives grouped as one parameter.
      final alternatives = type.expressions.map(_withoutAnchors).join('|');
      final captureCount = _countCaptures(alternatives);
      output.write('($alternatives)');
      final start = groupOffset + 1;
      ranges.add(_CaptureRange(start, start + captureCount + 1));
      groupOffset += captureCount + 1;
      types.add(type);
      offset = match.end;
    }
    output.write(RegExp.escape(expression.substring(offset)));
    output.write(r'$');
    return RegExp(output.toString());
  }

  Future<List<Object?>> transform(RegExpMatch match) async {
    final values = <Object?>[];
    for (var i = 0; i < parameterTypes.length; i++) {
      final range = _captureRanges[i];
      // A parameter regex may itself include captures. Prefer those captures;
      // otherwise use the wrapper capture for a conventional custom regexp.
      final captures = <String?>[
        for (var group = range.start; group < range.end; group++)
          match.group(group),
      ];
      final nonNullCaptures = captures.skip(1).any((value) => value != null)
          ? captures.skip(1).toList()
          : <String?>[captures.first];
      values.add(await parameterTypes[i].transform(nonNullCaptures));
    }
    return values;
  }
}

final class _CaptureRange {
  final int start;
  final int end;
  const _CaptureRange(this.start, this.end);
}

String _withoutAnchors(RegExp expression) {
  var source = expression.pattern;
  if (source.startsWith('^')) source = source.substring(1);
  if (source.endsWith(r'$')) source = source.substring(0, source.length - 1);
  return source;
}

int _countCaptures(String source) {
  var count = 0;
  var escaped = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
    } else if (char == r'\') {
      escaped = true;
    } else if (char == '(' &&
        !(i + 1 < source.length && source[i + 1] == '?')) {
      count++;
    }
  }
  return count;
}

final class StepDocString {
  final String content;
  final String? mediaType;
  const StepDocString(this.content, {this.mediaType});
}

final class StepDataTable {
  final List<List<String>> rows;
  const StepDataTable(this.rows);

  List<String> asList() => [for (final row in rows) ...row];
  List<List<String>> asLists() => rows.map(List<String>.unmodifiable).toList();
  List<Map<String, String>> asMaps() {
    if (rows.isEmpty) return const [];
    final headers = rows.first;
    return [
      for (final row in rows.skip(1))
        {
          for (var i = 0; i < headers.length && i < row.length; i++)
            headers[i]: row[i],
        },
    ];
  }

  Map<String, String> asKeyValueMap() => {
    for (final row in rows)
      if (row.length >= 2) row.first: row[1],
  };
}
