/// A canonical governed control identifier.
///
/// This is an extension type so generated constant control sets remain valid
/// compile-time Dart values while retaining the distinct typed API.
extension type const ControlId(String value) {

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
  int compareTo(ControlId other) => value.compareTo(other.value);
}
