import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart' show canonicalJson;
import 'package:crypto/crypto.dart';

/// Produces a stable, non-secret APIM policy-evidence envelope from a raw
/// export collected by the protected Azure workflow. The raw export is never
/// checked into Git; only this canonical, content-addressed representation is
/// passed to the external attestation command.
class GatewayCanonicalizeCommand {
  final ArgResults args;

  GatewayCanonicalizeCommand(this.args);

  int execute() {
    final input = File(args['input'] as String);
    final output = File(args['output'] as String);
    final route = args['route'] as String;
    final reference = args['reference'] as String;
    if (!input.existsSync()) {
      throw FormatException('Gateway export does not exist: ${input.path}');
    }
    if (input.lengthSync() == 0) {
      throw const FormatException('Gateway export must not be empty');
    }
    final decoded = jsonDecode(input.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('Gateway export root must be a JSON object');
    }
    final raw = Map<String, Object?>.from(decoded);
    final policies = raw['policies'];
    if (policies is! Map) {
      throw const FormatException('Gateway export must contain policy scopes');
    }
    const scopes = ['service', 'product', 'api', 'operation'];
    final normalizedPolicies = <String, String>{};
    for (final scope in scopes) {
      final value = policies[scope];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Gateway export is missing $scope policy');
      }
      final index = scopes.indexOf(scope);
      final parent = index == 0 ? null : normalizedPolicies[scopes[index - 1]];
      normalizedPolicies[scope] = _resolveInheritance(
        _normalizeXml(value),
        parent,
        scope,
      );
    }
    final allPolicies = normalizedPolicies.values.join('\n');
    if (!RegExp(r'<rate-limit(?:-by-key)?(?:\s|>)').hasMatch(allPolicies)) {
      throw const FormatException(
        'Gateway export has no effective rate-limit or rate-limit-by-key policy',
      );
    }
    if (raw['route'] != route) {
      throw FormatException('Gateway export route does not match $route');
    }
    if (raw['verification'] is! Map ||
        (raw['verification'] as Map)['policyAttached'] != true ||
        (raw['verification'] as Map)['currentRevision'] != true) {
      throw const FormatException('Gateway export verification is incomplete');
    }
    final verification = Map<String, Object?>.from(raw['verification'] as Map)
      ..['inheritanceResolved'] = true;

    final canonical = _sanitize(<String, Object?>{
      ...raw,
      'kind': 'zuke.gateway-evidence',
      'reference': reference,
      'route': route,
      'policies': normalizedPolicies,
      'verification': verification,
    });
    final bytes = utf8.encode('${canonicalJson(canonical)}\n');
    if (bytes.isEmpty) {
      throw const FormatException('Canonical gateway export is empty');
    }
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes, flush: true);
    stdout.writeln('sha256:${sha256.convert(bytes)}');
    return 0;
  }

  String _normalizeXml(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');

  String _resolveInheritance(String policy, String? parent, String scope) {
    final base = RegExp(r'<base\s*/>', caseSensitive: false);
    if (!base.hasMatch(policy)) return policy;
    if (parent == null) {
      throw FormatException('Gateway export has unresolved <base/> in $scope');
    }

    var resolved = policy;
    for (final section in ['inbound', 'backend', 'outbound', 'on-error']) {
      final childSection = RegExp(
        '<$section(?:\\s[^>]*)?>([\\s\\S]*?)</$section>',
        caseSensitive: false,
      );
      final parentMatch = childSection.firstMatch(parent);
      final parentContents = parentMatch?.group(1) ?? '';
      resolved = resolved.replaceAllMapped(childSection, (match) {
        final contents = match.group(1)!;
        return base.hasMatch(contents)
            ? match.group(0)!.replaceFirst(base, parentContents)
            : match.group(0)!;
      });
    }
    if (base.hasMatch(resolved)) {
      throw FormatException('Gateway export has unresolved <base/> in $scope');
    }
    return resolved;
  }

  Object? _sanitize(Object? value) {
    const blocked = {
      'accessToken',
      'authorization',
      'requestId',
      'sasUrl',
      'temporaryUrl',
      'secret',
      'secretValue',
    };
    if (value is Map) {
      final result = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        if (!blocked.contains(key)) result[key] = _sanitize(value[key]);
      }
      return result;
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }
}
