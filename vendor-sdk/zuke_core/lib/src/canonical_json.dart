import 'dart:convert';

/// Deterministic JSON encoding used for hashes, signatures, and lock files.
String canonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final entries = <MapEntry<String, Object?>>[];
      for (final entry in input.entries) {
        if (entry.key is! String) {
          throw FormatException(
            'JSON object keys must be strings, got ${entry.key.runtimeType}',
          );
        }
        entries.add(MapEntry(entry.key as String, normalize(entry.value)));
      }
      entries.sort((a, b) => a.key.compareTo(b.key));
      return <String, Object?>{
        for (final entry in entries) entry.key: entry.value,
      };
    }
    if (input is Iterable) return input.map(normalize).toList(growable: false);
    if (input is String || input is num || input is bool || input == null) {
      return input;
    }
    throw FormatException('Value is not JSON-compatible: ${input.runtimeType}');
  }

  return jsonEncode(normalize(value));
}
