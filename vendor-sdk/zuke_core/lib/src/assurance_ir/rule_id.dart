/// A canonical governed requirement identifier.
final class RuleId implements Comparable<RuleId> {
  final String value;
  const RuleId(this.value) : assert(value != '');

  factory RuleId.parse(String value) {
    if (!_isCanonical(value)) throw FormatException('Invalid RuleId: $value');
    return RuleId(value);
  }
  static RuleId? tryParse(String value) =>
      _isCanonical(value) ? RuleId(value) : null;
  static bool _isCanonical(String value) => _pattern.hasMatch(value);
  static final RegExp _pattern = RegExp(
    r'^RULE-[A-Z0-9]+-[A-Z0-9]+(?:-[A-Z0-9]+)*$',
  );
  @override
  int compareTo(RuleId other) => value.compareTo(other.value);
  @override
  bool operator ==(Object other) => other is RuleId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}
