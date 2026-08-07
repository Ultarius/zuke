import 'dart:convert';
import 'package:crypto/crypto.dart';

class ManifestEntry {
  final String path;
  final String contentHash;

  const ManifestEntry({required this.path, required this.contentHash});

  Map<String, dynamic> toJson() => {
    'path': path.replaceAll('\\', '/'),
    'contentHash': contentHash,
  };
}

class Manifest {
  final List<ManifestEntry> entries;

  const Manifest({this.entries = const []});

  String toJson() {
    final data = entries.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'files': data, 'hash': hash()});
  }

  String hash() {
    final content = entries.map((e) => '${e.path}|${e.contentHash}').join('\n');
    return sha256.convert(utf8.encode(content)).toString();
  }

  String get hashValue => hash();
}
