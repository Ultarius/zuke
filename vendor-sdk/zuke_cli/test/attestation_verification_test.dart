import 'dart:convert';
import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_cli/src/proof_engine.dart';
import 'package:zuke_cli/src/attestation_verification.dart';
import 'package:test/test.dart';

void main() {
  group('AttestationVerification', () {
    late Directory root;
    late _SignerFixture signer;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('attestation-verification-');
      signer = await _SignerFixture.create(root);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'distinguishes missing providers, documents, and trust metadata',
      () async {
        final missingProvider = await AttestationVerification().verify(
          _workspace(root, providers: const []),
        );
        expect(missingProvider.single.status, ProofStatus.missing);
        expect(missingProvider.single.diagnostics.single, contains('provider'));

        final incomplete = await AttestationVerification().verify(
          _workspace(root, providers: [_provider()..remove('document')]),
        );
        expect(incomplete.single.status, ProofStatus.failed);
        expect(incomplete.single.diagnostics.single, contains('document'));

        final missingDocument = await AttestationVerification().verify(
          _workspace(root, providers: [_provider()]),
        );
        expect(missingDocument.single.status, ProofStatus.missing);
        expect(missingDocument.single.providerIds, ['external-gateway']);

        final document = File('${root.path}/attestations/gateway.json');
        document.parent.createSync(recursive: true);
        document.writeAsStringSync('{}');
        signer.trustFile.deleteSync();
        final missingTrust = await AttestationVerification().verify(
          _workspace(root, providers: [_provider()]),
        );
        expect(missingTrust.single.status, ProofStatus.missing);
        expect(
          missingTrust.single.diagnostics.single,
          contains('trust bundle'),
        );
      },
    );

    test(
      'fails closed for malformed, untrusted, and mismatched records',
      () async {
        final document = File('${root.path}/attestations/gateway.json');
        document.parent.createSync(recursive: true);
        document.writeAsStringSync('[]');
        var result = await AttestationVerification().verify(
          _workspace(root, providers: [_provider()]),
        );
        expect(result.single.status, ProofStatus.failed);
        expect(result.single.diagnostics.single, contains('verify'));

        document.writeAsStringSync(
          jsonEncode({
            'schemaVersion': 'unknown',
            'signer': {},
            'body': {},
            'signature': '',
          }),
        );
        result = await AttestationVerification().verify(
          _workspace(root, providers: [_provider()]),
        );
        expect(result.single.diagnostics.single, contains('signature'));

        final body = _body(_provider())..['owner'] = 'different-owner';
        await signer.writeRecord(document, body);
        result = await AttestationVerification().verify(
          _workspace(root, providers: [_provider()]),
        );
        expect(result.single.status, ProofStatus.failed);
        expect(result.single.diagnostics.single, contains('owner'));
      },
    );

    test(
      'validates temporal boundaries and accepts a current signed record',
      () async {
        final provider = _provider();
        final document = File('${root.path}/attestations/gateway.json');
        document.parent.createSync(recursive: true);
        final now = DateTime.now().toUtc();
        final cases = [
          (
            issued: now,
            expires: now.subtract(const Duration(days: 1)),
            status: ProofStatus.failed,
            diagnostic: 'issue or expiry',
          ),
          (
            issued: now.add(const Duration(days: 1)),
            expires: now.add(const Duration(days: 30)),
            status: ProofStatus.failed,
            diagnostic: 'future',
          ),
          (
            issued: now.subtract(const Duration(days: 30)),
            expires: now.subtract(const Duration(days: 1)),
            status: ProofStatus.expired,
            diagnostic: 'expired',
          ),
          (
            issued: now.subtract(const Duration(days: 1)),
            expires: now.add(const Duration(days: 2)),
            status: ProofStatus.failed,
            diagnostic: '14 days',
          ),
        ];
        for (final testCase in cases) {
          final body = _body(
            provider,
            issuedAt: testCase.issued,
            expiresAt: testCase.expires,
          );
          await signer.writeRecord(document, body);
          final result = await AttestationVerification().verify(
            _workspace(root, providers: [provider]),
          );
          expect(result.single.status, testCase.status);
          expect(
            result.single.diagnostics.single,
            contains(testCase.diagnostic),
          );
        }

        await signer.writeRecord(
          document,
          _body(
            provider,
            issuedAt: now.subtract(const Duration(days: 1)),
            expiresAt: now.add(const Duration(days: 30)),
          ),
        );
        final accepted = await AttestationVerification().verify(
          _workspace(root, providers: [provider]),
        );
        expect(accepted.single.status, ProofStatus.attested);
        expect(accepted.single.providerIds, ['external-gateway']);
      },
    );

    test(
      'rejects drifted source scopes and duplicate proof identities',
      () async {
        final provider = _provider()
          ..['scope'] = {
            'path': '/api',
            'sourceFiles': ['lib/missing.dart'],
            'sourceDigest': 'sha256:${List.filled(64, '0').join()}',
          };
        final document = File('${root.path}/attestations/gateway.json');
        document.parent.createSync(recursive: true);
        await signer.writeRecord(document, _body(provider));
        final drifted = await AttestationVerification().verify(
          _workspace(root, providers: [provider]),
        );
        expect(drifted.single.status, ProofStatus.failed);
        expect(drifted.single.diagnostics.single, contains('source scope'));

        final duplicateWorkspace = _workspace(root, providers: [provider]);
        final feature = duplicateWorkspace.data.features.single;
        final duplicated = WorkspaceDiscoveryResult(
          config: duplicateWorkspace.config,
          data: MetadataExtractorResult(
            controls: duplicateWorkspace.data.controls,
            policies: duplicateWorkspace.data.policies,
            features: [feature, feature],
          ),
        );
        expect(
          AttestationVerification().verify(duplicated),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('normalizes source-scope text line endings', () async {
      final source = File('${root.path}/lib/source.dart')
        ..createSync(recursive: true);
      final provider = _provider()
        ..['scope'] = {
          'path': '/api',
          'sourceFiles': ['lib/source.dart'],
          'sourceDigest': '',
        };
      final document = File('${root.path}/attestations/gateway.json');
      document.parent.createSync(recursive: true);

      source.writeAsStringSync('const value = 1;\n');
      final digestInput = <int>[
        ...utf8.encode('lib/source.dart\u0000'),
        ...canonicalDigestBytes(source.path, source.readAsBytesSync()),
        0,
      ];
      final digest = 'sha256:${sha256.convert(digestInput)}';
      (provider['scope'] as Map)['sourceDigest'] = digest;
      await signer.writeRecord(document, _body(provider));
      expect(
        (await AttestationVerification().verify(
          _workspace(root, providers: [provider]),
        )).single.status,
        ProofStatus.attested,
      );

      source.writeAsStringSync('const value = 1;\r\n');
      expect(
        (await AttestationVerification().verify(
          _workspace(root, providers: [provider]),
        )).single.status,
        ProofStatus.attested,
      );
    });

    test('expired proofs cannot make validation eligible', () {
      final report = ValidationResult(
        hasExpectedProofs: true,
        controlProofs: [
          const ControlProofResult(
            controlId: 'CTRL-GATEWAY',
            status: ProofStatus.expired,
            semantics: CoverageSemantics.externalAttestation,
            diagnostics: ['External attestation has expired'],
          ),
        ],
      ).toReport();

      expect(report.eligible, isFalse);
      expect(report.ineligibilityReasons, contains(contains('expired')));
    });
  });
}

WorkspaceDiscoveryResult _workspace(
  Directory root, {
  required List<Map<String, Object?>> providers,
}) {
  const source = SourceLocation(file: 'gateway.feature', line: 1);
  return WorkspaceDiscoveryResult(
    config: ZukeConfig(
      root: root.path,
      trustBundle: 'assurance-history/trust/ed25519-v2.json',
    ),
    data: MetadataExtractorResult(
      controls: const {
        'CTRL-GATEWAY': {
          'id': 'CTRL-GATEWAY',
          'coverageSemantics': 'external-attestation',
        },
      },
      policies: {
        'attestations': {'providers': providers},
      },
      features: const [
        ParsedFeature(
          tags: [],
          featureElement: GherkinElement(
            keyword: GherkinKeyword.feature,
            title: 'Gateway',
            source: source,
          ),
          metadata: ParsedMetadata(id: 'FEAT-GATEWAY', source: source),
          rules: [
            ParsedRule(
              tags: [],
              ruleElement: GherkinElement(
                keyword: GherkinKeyword.rule,
                title: 'Gateway rule',
                source: source,
              ),
              metadata: ParsedMetadata(
                id: 'RULE-GATEWAY',
                requires: [ParsedControlRef(id: 'CTRL-GATEWAY')],
                source: source,
              ),
              scenarios: [],
            ),
          ],
        ),
      ],
    ),
  );
}

Map<String, Object?> _provider() => {
  'id': 'external-gateway',
  'assurance': 'attested',
  'document': 'attestations/gateway.json',
  'provides': 'CTRL-GATEWAY',
  'target': 'backend',
  'variant': 'default',
  'kind': 'gateway-policy',
  'layer': 'edge',
  'owner': 'platform-team',
  'system': 'apim',
  'reference': 'EDGE-2841',
  'scope': {'path': '/api'},
  'evidence': {
    'type': 'gateway-export',
    'digest': 'sha256:${List.filled(64, 'a').join()}',
  },
};

Map<String, Object?> _body(
  Map<String, Object?> provider, {
  DateTime? issuedAt,
  DateTime? expiresAt,
}) {
  final now = DateTime.now().toUtc();
  return {
    'providerId': provider['id'],
    'controlId': provider['provides'],
    'target': provider['target'],
    'variant': provider['variant'],
    'kind': provider['kind'],
    'layer': provider['layer'],
    'owner': provider['owner'],
    'system': provider['system'],
    'reference': provider['reference'],
    'scopeHash':
        'sha256:${sha256.convert(utf8.encode(canonicalJson(provider['scope'])))}',
    'evidenceType': (provider['evidence'] as Map)['type'],
    'evidenceDigest': (provider['evidence'] as Map)['digest'],
    'issuedAt': (issuedAt ?? now.subtract(const Duration(days: 1)))
        .toIso8601String(),
    'expiresAt': (expiresAt ?? now.add(const Duration(days: 30)))
        .toIso8601String(),
  };
}

class _SignerFixture {
  static const _domain = 'Zuke external control attestation v1\u0000';
  static final _seed = _hex(
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
  );

  final Ed25519 algorithm;
  final KeyPair keyPair;
  final File trustFile;

  const _SignerFixture(this.algorithm, this.keyPair, this.trustFile);

  static Future<_SignerFixture> create(Directory root) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(_seed);
    final publicKey = await keyPair.extractPublicKey();
    final trustFile = File(
      '${root.path}/assurance-history/trust/ed25519-v2.json',
    );
    trustFile.parent.createSync(recursive: true);
    trustFile.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 'zuke.ed25519-trust.v2',
        'keys': [
          {
            'signerId': 'attestation-signer',
            'keyId': 'default',
            'algorithm': 'Ed25519',
            'publicKey': base64Encode(publicKey.bytes),
            'fingerprint': 'sha256:${sha256.convert(publicKey.bytes)}',
            'usages': ['attestation'],
            'status': 'active',
          },
        ],
      }),
    );
    return _SignerFixture(algorithm, keyPair, trustFile);
  }

  Future<void> writeRecord(File target, Map<String, Object?> body) async {
    final unsigned = <String, Object?>{
      'schemaVersion': 'zuke.external-attestation.v1',
      'signer': {
        'signerId': 'attestation-signer',
        'keyId': 'default',
        'algorithm': 'Ed25519',
      },
      'body': body,
    };
    final payload = utf8.encode('$_domain${canonicalJson(unsigned)}');
    final signature = await algorithm.sign(payload, keyPair: keyPair);
    target.writeAsStringSync(
      jsonEncode({...unsigned, 'signature': base64Encode(signature.bytes)}),
    );
  }
}

List<int> _hex(String value) => [
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
];
