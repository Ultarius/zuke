/// A stable governed scenario identifier.
///
/// JSON artifacts continue to encode this value as its [value] string. Use
/// [ScenarioId.parse] at untyped boundaries so non-scenario candidates cannot
/// accidentally satisfy scenario-selection evidence.
final class ScenarioId implements Comparable<ScenarioId> {
  final String value;

  const ScenarioId(this.value) : assert(value != '');

  /// Validates an ID read from an untyped boundary.
  factory ScenarioId.parse(String value) {
    if (!_isCanonical(value)) {
      throw FormatException('Invalid scenario ID: $value');
    }
    return ScenarioId(value);
  }

  static ScenarioId? tryParse(String value) =>
      _isCanonical(value) ? ScenarioId(value) : null;

  static bool _isCanonical(String value) =>
      RegExp(r'^SCN-[A-Z0-9]+-[A-Z0-9]+(?:-[A-Z0-9]+)*$').hasMatch(value);

  @override
  int compareTo(ScenarioId other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is ScenarioId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
