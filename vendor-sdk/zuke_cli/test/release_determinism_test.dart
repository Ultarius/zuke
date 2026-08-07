import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'helpers/eligible_workspace.dart';

/// Exercises the real `manifest create` command against a local signing
/// service. This verifies deterministic release material without pretending
/// that a local signer is production signing infrastructure.
void main() {
  test(
    'manifest create is deterministic across identical clean release roots',
    () async {
      final base = Directory.systemTemp.createTempSync(
        'zuke-release-determinism-',
      );
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      final source = Directory('${base.path}/source/release-workspace')
        ..createSync(recursive: true);
      await createEligibleWorkspace(source);
      // Match the repository checkout contract. Without this, a Windows
      // core.autocrlf checkout changes the lock bytes before release creation.
      File(
        '${source.path}/.gitattributes',
      ).writeAsStringSync('* text=auto eol=lf\n');

      final algorithm = Ed25519();
      final releaseKeyPair = await algorithm.newKeyPair();
      final releasePublicKey = await releaseKeyPair.extractPublicKey();
      _replaceReleaseTrustKey(source, releasePublicKey.bytes);

      final generate = await _runZuke(['generate', '--root', source.path]);
      expect(
        generate.exitCode,
        0,
        reason: '${generate.stdout}\n${generate.stderr}',
      );
      final lock = await _runZuke([
        'lock',
        '--root',
        source.path,
        '--profile',
        'release',
      ]);
      expect(lock.exitCode, 0, reason: '${lock.stdout}\n${lock.stderr}');
      _git(source, ['init']);
      _git(source, ['config', 'user.name', 'Zuke Test']);
      _git(source, ['config', 'user.email', 'zuke@example.test']);
      _git(source, ['add', '.']);
      _git(source, ['commit', '-m', 'release fixture', '--no-gpg-sign']);

      final clone = Directory('${base.path}/clone/release-workspace');
      clone.parent.createSync(recursive: true);
      _git(source, [
        'clone',
        source.path,
        clone.path,
      ], workingDirectory: base.path);

      final server = await _SigningServer.start(
        keyPair: releaseKeyPair,
        fingerprint: 'sha256:${sha256.convert(releasePublicKey.bytes)}',
      );
      addTearDown(server.close);

      final childLockCheck = await _runZuke([
        'lock',
        '--root',
        source.path,
        '--profile',
        'release',
        '--check',
      ]);
      expect(
        childLockCheck.exitCode,
        0,
        reason: '${childLockCheck.stdout}\n${childLockCheck.stderr}',
      );

      final first = await _runManifestCreate(source, server);
      final second = await _runManifestCreate(clone, server);

      expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');
      expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');

      final firstPath = _lastNonEmptyLine(first.stdout);
      final secondPath = _lastNonEmptyLine(second.stdout);
      final firstRecord = File(firstPath).readAsStringSync();
      final secondRecord = File(secondPath).readAsStringSync();
      expect(secondRecord, equals(firstRecord));
      expect(server.requests, hasLength(2));
      expect(
        server.requests[0]['payloadDigest'],
        server.requests[1]['payloadDigest'],
      );
      expect(
        server.requests[0]['payloadBase64'],
        server.requests[1]['payloadBase64'],
      );

      final verify = await _runManifestVerify(clone);
      expect(verify.exitCode, 0, reason: '${verify.stdout}\n${verify.stderr}');
      expect(verify.stdout, contains('V2 release chain valid.'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _replaceReleaseTrustKey(Directory root, List<int> publicKey) {
  final file = File('${root.path}/assurance-history/trust/ed25519-v2.json');
  final bundle = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final keys = (bundle['keys'] as List).cast<Map<String, dynamic>>();
  final release = keys.firstWhere((key) => key['signerId'] == 'release-signer');
  release['publicKey'] = base64Encode(publicKey);
  release['fingerprint'] = 'sha256:${sha256.convert(publicKey)}';
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(bundle));
}

void _git(Directory root, List<String> args, {String? workingDirectory}) {
  final result = Process.runSync(
    'git',
    args,
    workingDirectory: workingDirectory ?? root.path,
  );
  expect(
    result.exitCode,
    0,
    reason: 'git ${args.join(' ')} failed:\n${result.stdout}\n${result.stderr}',
  );
}

Future<ProcessResult> _runManifestCreate(
  Directory root,
  _SigningServer server,
) {
  return _runZuke([
    'manifest',
    'create',
    '--root',
    root.path,
    '--signer-id',
    'release-signer',
  ], server: server);
}

Future<ProcessResult> _runManifestVerify(Directory root) {
  return _runZuke(['manifest', 'verify-v2', '--root', root.path, '--current']);
}

Future<ProcessResult> _runZuke(List<String> args, {_SigningServer? server}) {
  final environment = Map<String, String>.from(Platform.environment);
  if (server != null) {
    environment['ZUKE_SIGNING_PROVIDER_URL'] = server.url;
    environment['ZUKE_SIGNING_PROVIDER_BEARER_TOKEN'] = 'local-test-token';
  }
  return Process.run(
    Platform.resolvedExecutable,
    ['--suppress-analytics', 'run', 'zuke_cli:zuke', ...args],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
}

String _lastNonEmptyLine(String value) => value
    .split(RegExp(r'\r?\n'))
    .map((line) => line.trim())
    .lastWhere((line) => line.isNotEmpty);

final class _SigningServer {
  final HttpServer _server;
  final SimpleKeyPair keyPair;
  final String fingerprint;
  final List<Map<String, dynamic>> requests = [];

  _SigningServer(this._server, this.keyPair, this.fingerprint);

  String get url => 'http://${_server.address.address}:${_server.port}/v1/sign';

  static Future<_SigningServer> start({
    required SimpleKeyPair keyPair,
    required String fingerprint,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final signingServer = _SigningServer(server, keyPair, fingerprint);
    server.listen(signingServer._handle);
    return signingServer;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer local-test-token') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      requests.add(body);
      final payload = base64Decode(body['payloadBase64'] as String);
      final signature = await Ed25519().sign(payload, keyPair: keyPair);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'signerId': body['signerId'],
          'keyId': body['keyId'],
          'algorithm': 'Ed25519',
          'publicKeyFingerprint': fingerprint,
          'signature': base64Encode(signature.bytes),
        }),
      );
      await request.response.close();
    } catch (error) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('$error');
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}
