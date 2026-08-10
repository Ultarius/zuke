import 'dart:async';

/// A typed transformation used by generated Gherkin step support.
final class StepParameterType<T> {
  /// Stable parameter type name.
  final String name;

  /// Regular expressions accepted by the type.
  final List<RegExp> expressions;

  /// Whether this type may be used for snippets.
  final bool useForSnippets;

  /// Whether this type is preferred for regular-expression matches.
  final bool preferForRegexpMatch;

  /// Ordering priority used during snippet generation.
  final int snippetPriority;

  /// Converts captured text to a typed value.
  final FutureOr<T> Function(List<String?> captures) transform;

  /// Creates a parameter type.
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

  /// Creates a registry populated with the standard parameter types.
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

  /// Registers [type], rejecting duplicate names.
  void define<T>(StepParameterType<T> type) {
    if (type.name.isEmpty || _types.containsKey(type.name)) {
      throw ArgumentError.value(type.name, 'name', 'Duplicate parameter type');
    }
    if (type.snippetPriority < 0) {
      throw ArgumentError.value(type.snippetPriority, 'snippetPriority');
    }
    _types[type.name] = type as StepParameterType<Object?>;
  }

  /// Returns the registered type named [name].
  StepParameterType<T> type<T>(String name) {
    final value = _types[name];
    if (value == null) {
      throw ArgumentError.value(name, 'name', 'Unknown parameter type');
    }
    return value as StepParameterType<T>;
  }

  /// Registered types in declaration order.
  Iterable<StepParameterType<Object?>> get types => _types.values;
}

/// A compiled Cucumber Expression.  It deliberately keeps the feature text
/// plain: placeholders are automation glue, not feature metadata.
final class CucumberExpression {
  /// Original expression text.
  final String source;

  /// Compiled regular expression.
  final RegExp pattern;

  /// Parameter types used by the expression.
  final List<StepParameterType<Object?>> parameterTypes;
  final List<_CaptureRange> _captureRanges;

  CucumberExpression._({
    required this.source,
    required this.pattern,
    required this.parameterTypes,
    required List<_CaptureRange> captureRanges,
  }) : _captureRanges = captureRanges;

  /// Compiles [expression] using [registry].
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

  /// Transforms [match] captures into typed parameter values.
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

/// A Gherkin step doc string.
final class StepDocString {
  /// Doc string content.
  final String content;

  /// Optional declared media type.
  final String? mediaType;

  /// Creates a doc string value.
  const StepDocString(this.content, {this.mediaType});
}

/// A Gherkin step data table.
final class StepDataTable {
  /// Table rows in source order.
  final List<List<String>> rows;

  /// Creates a data table.
  const StepDataTable(this.rows);

  /// Flattens all cells into a list.
  List<String> asList() => [for (final row in rows) ...row];

  /// Returns immutable table rows.
  List<List<String>> asLists() => rows.map(List<String>.unmodifiable).toList();

  /// Converts rows after the header into maps.
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

  /// Converts two-column rows into a key-value map.
  Map<String, String> asKeyValueMap() => {
    for (final row in rows)
      if (row.length >= 2) row.first: row[1],
  };
}
