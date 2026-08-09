import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_cli/src/attestation_verification.dart';
import 'package:zuke_cli/src/extraction_service.dart';
import 'package:test/test.dart';

import 'cli_test_helper.dart';
import 'helpers/eligible_workspace.dart';

void main() {
  group('LF vs CRLF Line Ending Digest Parity', () {
    late Directory lfWorkspace;
    late Directory crlfWorkspace;
    final fixedIssued = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final fixedExpires = DateTime.utc(2026, 12, 31, 12, 0, 0);

    setUp(() {
      lfWorkspace = Directory.systemTemp.createTempSync('parity-lf-');
      crlfWorkspace = Directory.systemTemp.createTempSync('parity-crlf-');
    });

    tearDown(() {
      if (lfWorkspace.existsSync()) lfWorkspace.deleteSync(recursive: true);
      if (crlfWorkspace.existsSync()) crlfWorkspace.deleteSync(recursive: true);
    });

    Future<void> populate(Directory dir, String lineEnding) async {
      await createEligibleWorkspace(
        dir,
        attestationIssuedAt: fixedIssued,
        attestationExpiresAt: fixedExpires,
      );
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path;
          if (path.contains('/attestations/') ||
              path.contains(r'\attestations\'))
            continue;
          if (path.endsWith('.dart') ||
              path.endsWith('.feature') ||
              path.endsWith('.yaml') ||
              path.endsWith('.yml') ||
              path.endsWith('.json')) {
            final text = entity.readAsStringSync();
            final normalized = text
                .replaceAll('\r\n', '\n')
                .replaceAll('\n', lineEnding);
            entity.writeAsStringSync(normalized);
          }
        }
      }
    }

    Future<void> addExtractionFixture(Directory dir, String lineEnding) async {
      final zuke = File('${dir.path}/zuke.yaml');
      final zukeText = zuke
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceFirst(
            '  backend:\n    language: dart\n',
            '  backend:\n'
                '    language: dart\n'
                '    packages:\n'
                '      - path: .\n'
                '        roots: [lib]\n',
          );
      zuke.writeAsStringSync(zukeText.replaceAll('\n', lineEnding));
      final repositoryRoot = _repositoryRoot().path.replaceAll('\\', '/');
      File('${dir.path}/pubspec.yaml').writeAsStringSync(
        '''name: parity_fixture
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  zuke_annotations:
    path: '$repositoryRoot/vendor-sdk/zuke_annotations'
  zuke_http_runtime:
    path: '$repositoryRoot/vendor-sdk/zuke_http_runtime'
dependency_overrides:
  zuke_core:
    path: '$repositoryRoot/vendor-sdk/zuke_core'
'''
            .replaceAll('\n', lineEnding),
      );
      final lib = Directory('${dir.path}/lib')..createSync(recursive: true);
      File('${lib.path}/service.dart').writeAsStringSync(
        '''import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

@PresentsRequirement(['RULE-PARITY-001'])
void present() {}

@ImplementsRequirement(['RULE-PARITY-001'], variant: 'preview')
class Controller implements ZukeController {
  @override
  String get id => 'controller';

  @override
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request) async =>
      const ZukeHttpResponse(200);
}

class Egress implements ZukePublicEgress {
  @override
  String get id => 'egress';

  @override
  Future<void> write(Object response) async {}
}

final application = ZukeHttpApplication(
  routes: [
    ZukeRouteRegistration(
      endpointId: 'endpoint.parity',
      method: 'GET',
      path: '/parity',
      middleware: const [],
      controller: Controller(),
      publicEgress: Egress(),
    ),
  ],
);

'''
            .replaceAll('\n', lineEnding),
      );
      final pubGet = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'pub',
        'get',
        '--offline',
      ], workingDirectory: dir.path);
      expect(
        pubGet.exitCode,
        0,
        reason: 'pub get failed: ${pubGet.stdout}\n${pubGet.stderr}',
      );
      final generatedLock = File('${dir.path}/pubspec.lock');
      if (generatedLock.existsSync()) generatedLock.deleteSync();
    }

    test(
      'lock feature sourceHash is identical between LF and CRLF checkouts',
      () async {
        await populate(lfWorkspace, '\n');
        await populate(crlfWorkspace, '\r\n');

        await runInProcessCli(['generate', '--root', lfWorkspace.path]);
        await runInProcessCli(['generate', '--root', crlfWorkspace.path]);

        final lfLockRes = await runInProcessCli([
          'lock',
          '--root',
          lfWorkspace.path,
        ]);
        final crlfLockRes = await runInProcessCli([
          'lock',
          '--root',
          crlfWorkspace.path,
        ]);

        expect(lfLockRes.exitCode, 0, reason: lfLockRes.stderr);
        expect(crlfLockRes.exitCode, 0, reason: crlfLockRes.stderr);

        final lfLock =
            jsonDecode(
                  File('${lfWorkspace.path}/zuke.lock.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final crlfLock =
            jsonDecode(
                  File(
                    '${crlfWorkspace.path}/zuke.lock.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;

        final lfFeatures = lfLock['features'] as Map<String, dynamic>;
        final crlfFeatures = crlfLock['features'] as Map<String, dynamic>;

        expect(lfFeatures, isNotEmpty);
        expect(crlfFeatures, isNotEmpty);

        for (final key in lfFeatures.keys) {
          expect(crlfFeatures.containsKey(key), isTrue);
          final lfSourceHash = (lfFeatures[key] as Map)['sourceHash'];
          final crlfSourceHash = (crlfFeatures[key] as Map)['sourceHash'];
          expect(
            crlfSourceHash,
            equals(lfSourceHash),
            reason:
                'feature sourceHash for $key must match between LF and CRLF',
          );
        }
      },
    );

    test(
      'ExtractionService extracts equivalent semantic IR between LF and CRLF checkouts',
      () async {
        await populate(lfWorkspace, '\n');
        await populate(crlfWorkspace, '\r\n');
        await addExtractionFixture(lfWorkspace, '\n');
        await addExtractionFixture(crlfWorkspace, '\r\n');

        final discovery = WorkspaceDiscovery();
        final lfDiscovery = discovery.discover(lfWorkspace.path);
        final crlfDiscovery = discovery.discover(crlfWorkspace.path);

        final service = ExtractionService();
        final lfExtraction = await service.extract(lfDiscovery);
        final crlfExtraction = await service.extract(crlfDiscovery);

        expect(lfExtraction.errors, isEmpty);
        expect(crlfExtraction.errors, isEmpty);
        expect(lfExtraction.outputs, hasLength(1));
        expect(crlfExtraction.outputs, hasLength(1));

        final lfOutput = lfExtraction.outputs.single;
        final crlfOutput = crlfExtraction.outputs.single;
        expect(crlfOutput.inputDigest, equals(lfOutput.inputDigest));
        expect(
          lfOutput.symbols.any(
            (symbol) => symbol.requirementIds.contains('RULE-PARITY-001'),
          ),
          isTrue,
          reason: 'fixture must exercise an extracted requirement binding',
        );
        expect(
          lfOutput.graph!.nodes.map((node) => node.id),
          contains('route:endpoint.parity'),
          reason: 'fixture must exercise extracted route topology',
        );
        final lfJson = _normalizedOutputJson(lfOutput, lfWorkspace);
        final crlfJson = _normalizedOutputJson(crlfOutput, crlfWorkspace);
        expect(
          lfJson['packageRoot'],
          equals('<workspace>'),
          reason: 'the retained package root must be workspace-relative',
        );
        expect(
          crlfJson['packageRoot'],
          equals('<workspace>'),
          reason: 'the retained package root must be workspace-relative',
        );
        expect(crlfJson, equals(lfJson));
      },
    );

    test(
      'canonicalDigestBytes behavior across supported and unsupported extensions',
      () {
        const lfContent = 'line1\nline2\n';
        const crlfContent = 'line1\r\nline2\r\n';

        const textExtensions = ['.dart', '.feature', '.json', '.yaml', '.yml'];
        for (final ext in textExtensions) {
          final path = 'test$ext';
          final lfBytes = canonicalDigestBytes(path, utf8.encode(lfContent));
          final crlfBytes = canonicalDigestBytes(
            path,
            utf8.encode(crlfContent),
          );
          expect(
            crlfBytes,
            equals(lfBytes),
            reason:
                'Extension $ext must normalize CRLF to LF in canonical bytes',
          );
        }

        const rawExtensions = ['.bin', '.txt', '.custom', '.md'];
        for (final ext in rawExtensions) {
          final path = 'test$ext';
          final lfBytes = canonicalDigestBytes(path, utf8.encode(lfContent));
          final crlfBytes = canonicalDigestBytes(
            path,
            utf8.encode(crlfContent),
          );
          expect(
            crlfBytes,
            isNot(equals(lfBytes)),
            reason:
                'Extension $ext is not in the text allowlist, so raw bytes are preserved',
          );
        }
      },
    );

    test('lock file specificationDigest reflects normalized inputs', () async {
      await populate(lfWorkspace, '\n');
      await populate(crlfWorkspace, '\r\n');

      final discovery = WorkspaceDiscovery();
      final lfWorkspaceData = discovery.discover(lfWorkspace.path);
      final crlfWorkspaceData = discovery.discover(crlfWorkspace.path);

      final lfResolved = Directory(
        Directory(lfWorkspace.path).resolveSymbolicLinksSync(),
      );
      final crlfResolved = Directory(
        Directory(crlfWorkspace.path).resolveSymbolicLinksSync(),
      );

      final lfDigest = WorkspaceDigest.computeInputContents(
        lfResolved,
        lfWorkspaceData.inputContents,
      );
      final crlfDigest = WorkspaceDigest.computeInputContents(
        crlfResolved,
        crlfWorkspaceData.inputContents,
      );

      expect(
        crlfDigest,
        equals(lfDigest),
        reason: 'specificationDigest must be LF/CRLF agnostic',
      );
    });

    test(
      'signed attestation verification tolerates JSON line endings',
      () async {
        await populate(lfWorkspace, '\n');
        final attestation = File(
          '${lfWorkspace.path}/attestations/gateway.json',
        );
        final crlf = attestation
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .replaceAll('\n', '\r\n');
        attestation.writeAsStringSync(crlf);

        final verification = await AttestationVerification().verify(
          WorkspaceDiscovery().discover(lfWorkspace.path),
        );
        expect(verification, hasLength(1));
        expect(verification.single.status, ProofStatus.attested);
      },
    );

    test(
      'manifest create payload digests are identical between LF and CRLF checkouts',
      () async {
        await populate(lfWorkspace, '\n');
        await populate(crlfWorkspace, '\r\n');

        final lfRootPath = Directory(
          lfWorkspace.path,
        ).resolveSymbolicLinksSync();
        final crlfRootPath = Directory(
          crlfWorkspace.path,
        ).resolveSymbolicLinksSync();

        final algo = Ed25519();
        final releaseKeyPair = await algo.newKeyPair();
        final releasePublicKey = await releaseKeyPair.extractPublicKey();
        final releasePubBytes = releasePublicKey.bytes;
        final releasePubB64 = base64Encode(releasePubBytes);
        final releaseFingerprint = 'sha256:${sha256.convert(releasePubBytes)}';

        final attestationKeyPair = await algo.newKeyPair();
        final attestationPublicKey = await attestationKeyPair
            .extractPublicKey();
        final attestationPubBytes = attestationPublicKey.bytes;
        final attestationPubB64 = base64Encode(attestationPubBytes);
        final attestationFingerprint =
            'sha256:${sha256.convert(attestationPubBytes)}';

        for (final wsPath in [lfRootPath, crlfRootPath]) {
          File(
            '$wsPath/assurance-history/trust/ed25519-v2.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert({
              'schemaVersion': 'zuke.ed25519-trust.v2',
              'keys': [
                {
                  'signerId': 'attestation-signer',
                  'keyId': 'default',
                  'algorithm': 'Ed25519',
                  'publicKey': attestationPubB64,
                  'fingerprint': attestationFingerprint,
                  'usages': ['attestation'],
                  'status': 'active',
                },
                {
                  'signerId': 'release-signer',
                  'keyId': 'default',
                  'algorithm': 'Ed25519',
                  'publicKey': releasePubB64,
                  'fingerprint': releaseFingerprint,
                  'usages': ['release'],
                  'status': 'active',
                },
              ],
            }),
          );

          final scopeMap = {'endpoint': '/add', 'method': 'POST'};
          final scopeHash =
              'sha256:${sha256.convert(utf8.encode(canonicalJson(scopeMap)))}';
          const evidenceDigest =
              'sha256:1111111111111111111111111111111111111111111111111111111111111111';
          final issuedAt = fixedIssued.toIso8601String();
          final expiresAt = fixedExpires.toIso8601String();
          final attestationBody = <String, Object?>{
            'providerId': 'external-gateway',
            'controlId': 'CTRL-GATEWAY-RATE-LIMIT',
            'target': 'backend',
            'variant': 'default',
            'kind': 'rate-limit',
            'layer': 'edge',
            'owner': 'platform-team',
            'system': 'gateway',
            'reference':
                'https://gateway.example/control/CTRL-GATEWAY-RATE-LIMIT',
            'scopeHash': scopeHash,
            'evidenceType': 'signed-attestation',
            'evidenceDigest': evidenceDigest,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
          };
          final attestationUnsigned = <String, Object?>{
            'schemaVersion': 'zuke.external-attestation.v1',
            'signer': {
              'signerId': 'attestation-signer',
              'keyId': 'default',
              'algorithm': 'Ed25519',
            },
            'body': attestationBody,
          };
          const domain = 'Zuke external control attestation v1\u0000';
          final bytesToSign = utf8.encode(
            '$domain${canonicalJson(attestationUnsigned)}',
          );
          final sig = await algo.sign(bytesToSign, keyPair: attestationKeyPair);
          File('$wsPath/attestations/gateway.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert({
              ...attestationUnsigned,
              'signature': base64Encode(sig.bytes),
            }),
          );
        }

        final server = await _SigningServer.start(
          keyPair: releaseKeyPair,
          fingerprint: releaseFingerprint,
        );
        addTearDown(server.close);

        for (final wsPath in [lfRootPath, crlfRootPath]) {
          await Process.run(Platform.resolvedExecutable, [
            '--suppress-analytics',
            'run',
            'zuke_cli:zuke',
            'generate',
            '--root',
            wsPath,
          ]);
          final lres = await Process.run(Platform.resolvedExecutable, [
            '--suppress-analytics',
            'run',
            'zuke_cli:zuke',
            'lock',
            '--root',
            wsPath,
            '--profile',
            'release',
          ]);
          expect(lres.exitCode, 0, reason: lres.stderr);

          final dir = Directory(wsPath);
          _git(dir, ['init']);
          _git(dir, ['config', 'user.name', 'Zuke Test']);
          _git(dir, ['config', 'user.email', 'zuke@example.test']);
          _git(dir, ['add', '.']);
          _git(dir, ['commit', '-m', 'release fixture', '--no-gpg-sign']);
        }

        final signerEnv = {
          ...Platform.environment,
          'ZUKE_SIGNING_PROVIDER_URL':
              'http://${server.address.address}:${server.port}/v1/sign',
          'ZUKE_SIGNING_PROVIDER_BEARER_TOKEN': 'local-test-token',
        };

        final lfManifestRes = await Process.run(Platform.resolvedExecutable, [
          '--suppress-analytics',
          'run',
          'zuke_cli:zuke',
          'manifest',
          'create',
          '--root',
          lfRootPath,
          '--signer-id',
          'release-signer',
        ], environment: signerEnv);

        final crlfManifestRes = await Process.run(Platform.resolvedExecutable, [
          '--suppress-analytics',
          'run',
          'zuke_cli:zuke',
          'manifest',
          'create',
          '--root',
          crlfRootPath,
          '--signer-id',
          'release-signer',
        ], environment: signerEnv);

        expect(lfManifestRes.exitCode, 0, reason: lfManifestRes.stderr);
        expect(crlfManifestRes.exitCode, 0, reason: crlfManifestRes.stderr);

        final lfRecordPath = _lastLine(lfManifestRes.stdout.toString());
        final crlfRecordPath = _lastLine(crlfManifestRes.stdout.toString());

        final lfRecord =
            jsonDecode(File(lfRecordPath).readAsStringSync())
                as Map<String, dynamic>;
        final crlfRecord =
            jsonDecode(File(crlfRecordPath).readAsStringSync())
                as Map<String, dynamic>;

        final lfBody = lfRecord['body'] as Map<String, dynamic>;
        final crlfBody = crlfRecord['body'] as Map<String, dynamic>;

        for (final key in ['policyHash', 'evidenceRequirementsHash']) {
          expect(lfBody[key], isA<String>(), reason: '$key must be present');
          expect(crlfBody[key], isA<String>(), reason: '$key must be present');
          expect(
            crlfBody[key],
            equals(lfBody[key]),
            reason: '$key must be portable',
          );
        }
      },
    );
  });
}

Directory _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(
          '${current.path}${Platform.pathSeparator}melos.yaml',
        ).existsSync() ||
        Directory(
          '${current.path}${Platform.pathSeparator}.git',
        ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the repository root');
    }
    current = parent;
  }
}

Map<String, Object?> _normalizedOutputJson(
  AdapterOutput output,
  Directory workspace,
) {
  final json = <String, Object?>{
    ...output.toJson(),
    if (output.graph != null) 'graph': output.graph!.toJson(),
  };
  // packageRoot is a temporary, machine-specific path rather than extracted
  // semantics. Canonicalize it and the workspace before normalizing so
  // Windows long and 8.3 spellings compare the same way without dropping the
  // field entirely.
  final canonicalWorkspace = Directory(_canonicalDirectoryPath(workspace));
  final packageRoot = json['packageRoot'];
  if (packageRoot is String &&
      packageRoot.isNotEmpty &&
      Directory(packageRoot).existsSync()) {
    json['packageRoot'] = _canonicalDirectoryPath(Directory(packageRoot));
  }
  return _normalizeJson(json, canonicalWorkspace);
}

String _canonicalDirectoryPath(Directory directory) {
  try {
    return directory.resolveSymbolicLinksSync();
  } on FileSystemException {
    return directory.absolute.path;
  }
}

Map<String, Object?> _normalizeJson(
  Map<String, Object?> value,
  Directory workspace,
) => _normalizeValue(value, workspace) as Map<String, Object?>;

Object? _normalizeValue(Object? value, Directory workspace) {
  if (value is String) {
    final root = workspace.absolute.path.replaceAll('\\', '/');
    return value
        .replaceAll(root, '<workspace>')
        .replaceAll(workspace.absolute.path, '<workspace>');
  }
  if (value is Map) {
    // UTF-8 byte offsets and lengths legitimately differ when CRLF is used;
    // parity here concerns extracted semantics, bindings, and graph topology.
    return {
      for (final entry in value.entries)
        if (entry.key != 'offset' && entry.key != 'length')
          entry.key.toString(): _normalizeValue(entry.value, workspace),
    };
  }
  if (value is List) {
    return value.map((item) => _normalizeValue(item, workspace)).toList();
  }
  return value;
}

String _lastLine(String text) {
  final lines = text
      .trim()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.last;
}

void _git(
  Directory directory,
  List<String> arguments, {
  String? workingDirectory,
}) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: workingDirectory ?? directory.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(" ")} failed: ${result.stderr}');
  }
}

final class _SigningServer {
  _SigningServer(this._server, this.keyPair, this.fingerprint);

  final HttpServer _server;
  final SimpleKeyPair keyPair;
  final String fingerprint;
  final requests = <Map<String, dynamic>>[];

  InternetAddress get address => _server.address;
  int get port => _server.port;

  static Future<_SigningServer> start({
    required SimpleKeyPair keyPair,
    required String fingerprint,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _SigningServer(server, keyPair, fingerprint);
    server.listen(instance._handle);
    return instance;
  }

  Future<void> close() => _server.close(force: true);

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
      await request.response.close();
    }
  }
}
