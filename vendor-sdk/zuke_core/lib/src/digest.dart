/// Canonical SHA-256 digest used by current evidence and ledger contracts.
final class Sha256Digest {
  final String value;

  const Sha256Digest._(this.value);

  factory Sha256Digest.parse(String value) {
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('Digest must be sha256:<64 lowercase hex>');
    }
    return Sha256Digest._(value);
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is Sha256Digest && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
