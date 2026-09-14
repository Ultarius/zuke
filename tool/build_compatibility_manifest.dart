import 'dart:convert';
import 'dart:io';

/// Combines isolated hosted-certification reports into a safe compatibility
/// manifest. The reports are the source of truth; this file is only a
/// generated release artifact and must not be hand-edited.
Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final reports = <Map<String, Object?>>[];
  for (final path in options.inputs) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Certification report does not exist: $path');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw FormatException('Certification report is not an object: $path');
    }
    reports.add(Map<String, Object?>.from(decoded));
  }

  final manifest = buildCompatibilityManifest(reports);
  final output = File(options.output);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(encodeCompatibilityManifest(manifest));
}

Map<String, Object?> buildCompatibilityManifest(
  List<Map<String, Object?>> reports,
) {
  if (reports.isEmpty) {
    throw const FormatException(
      'At least one certification report is required',
    );
  }
  final seen = <String>{};
  Map<String, Object?>? first;
  final certifications = <Map<String, Object?>>[];
  for (final report in reports) {
    if (report['kind'] != 'zuke.hosted-consumer-certification' ||
        report['host'] is! String ||
        report['platform'] is! String ||
        report['passed'] is! bool ||
        report['packageVersions'] is! Map ||
        report['compatibilityIds'] is! Map ||
        report['sdk'] is! Map ||
        report['resolvedPackages'] is! Map ||
        report['lockDigests'] is! Map) {
      throw const FormatException('Malformed hosted-certification report');
    }
    final host = report['host'] as String;
    final platform = report['platform'] as String;
    if (!const {'dart', 'flutter'}.contains(host) ||
        !const {'linux', 'windows'}.contains(platform)) {
      throw FormatException('Unsupported certification tuple: $host/$platform');
    }
    final key = '$host/$platform';
    if (!seen.add(key)) {
      throw FormatException('Duplicate certification tuple: $key');
    }
    first ??= report;
    if (!_sameMap(report['packageVersions'], first['packageVersions']) ||
        !_sameMap(report['compatibilityIds'], first['compatibilityIds'])) {
      throw const FormatException(
        'Certification reports do not use one release tuple',
      );
    }
    certifications.add({
      'host': host,
      'platform': platform,
      'status': report['passed'] == true ? 'pass' : 'fail',
      'sdk': _stringMap(report['sdk'] as Map),
      'resolvedPackages': _stringMap(report['resolvedPackages'] as Map),
      'lockDigests': _stringMap(report['lockDigests'] as Map),
    });
  }
  certifications.sort((left, right) {
    final host = (left['host'] as String).compareTo(right['host'] as String);
    if (host != 0) return host;
    return (left['platform'] as String).compareTo(right['platform'] as String);
  });

  final packageVersions = _stringMap(first!['packageVersions'] as Map);
  final compatibilityIds = _stringMap(first['compatibilityIds'] as Map);
  return {
    'schemaVersion': 1,
    'zuke': {
      'packageVersions': packageVersions,
      'compatibilityIds': compatibilityIds,
    },
    'certifications': certifications,
  };
}

bool _sameMap(Object? left, Object? right) {
  if (left is! Map || right is! Map) return false;
  final leftMap = _stringMap(left);
  final rightMap = _stringMap(right);
  if (leftMap.length != rightMap.length) return false;
  for (final entry in leftMap.entries) {
    if (rightMap[entry.key] != entry.value) return false;
  }
  return true;
}

Map<String, String> _stringMap(Map value) {
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const FormatException(
        'Certification report contains a non-string map value',
      );
    }
    result[entry.key as String] = entry.value as String;
  }
  return result;
}

String encodeCompatibilityManifest(Map<String, Object?> value) {
  final lines = <String>[];
  void write(Object? current, int indent, {String? key}) {
    final prefix = ' ' * indent;
    if (key != null) lines.add('$prefix$key:');
    final contentIndent = key == null ? indent : indent + 2;
    if (current is Map) {
      final entries = current.entries.toList()
        ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()),
        );
      for (final entry in entries) {
        final entryKey = entry.key.toString();
        if (entry.value is Map || entry.value is List) {
          write(entry.value, contentIndent, key: entryKey);
        } else {
          lines.add('${' ' * contentIndent}$entryKey: ${_scalar(entry.value)}');
        }
      }
      return;
    }
    if (current is List) {
      for (final item in current) {
        if (item is Map) {
          lines.add('${' ' * contentIndent}-');
          write(item, contentIndent + 2);
        } else {
          lines.add('${' ' * contentIndent}- ${_scalar(item)}');
        }
      }
    }
  }

  write(value, 0);
  return '${lines.join('\n')}\n';
}

String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString().replaceAll("'", "''");
  return "'$text'";
}

final class _Options {
  const _Options({required this.inputs, required this.output});

  final List<String> inputs;
  final String output;

  static _Options parse(List<String> args) {
    final inputs = <String>[];
    String? output;
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--input':
          if (++index >= args.length) {
            throw const FormatException('--input requires a path');
          }
          inputs.add(args[index]);
        case '--output':
          if (++index >= args.length) {
            throw const FormatException('--output requires a path');
          }
          output = args[index];
        case '--help':
        case '-h':
          stdout.writeln(
            'dart run tool/build_compatibility_manifest.dart '
            '--input <report.json>... --output <manifest.yaml>',
          );
          exit(0);
        default:
          throw FormatException('Unknown option: ${args[index]}');
      }
    }
    if (inputs.isEmpty || output == null) {
      throw const FormatException('--input and --output are required');
    }
    final outputPath = output;
    if (outputPath.isEmpty) {
      throw const FormatException('--input and --output are required');
    }
    return _Options(inputs: inputs, output: outputPath);
  }
}
