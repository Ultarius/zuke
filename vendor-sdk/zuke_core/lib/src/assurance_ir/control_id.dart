/// A canonical governed control identifier.
final class ControlId implements Comparable<ControlId> {
  final String value;
  const ControlId(this.value) : assert(value != '');

  factory ControlId.parse(String value) {
    if (!_isCanonical(value)) {
      throw FormatException('Invalid ControlId: $value');
    }
    return ControlId(value);
  }
  static ControlId? tryParse(String value) =>
      _isCanonical(value) ? ControlId(value) : null;
  static bool _isCanonical(String value) => _pattern.hasMatch(value);
  static final RegExp _pattern = RegExp(
    r'^CTRL-[A-Z0-9]+-[A-Z0-9]+(?:-[A-Z0-9]+)*$',
  );
  @override
  int compareTo(ControlId other) => value.compareTo(other.value);
  @override
  bool operator ==(Object other) => other is ControlId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}
