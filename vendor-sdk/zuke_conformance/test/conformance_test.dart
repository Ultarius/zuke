import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/src/internal_adapter.dart';
import 'package:yaml/yaml.dart' show loadYaml;

/// Locates the workspace from either a package-local or repository-root test
/// invocation. `melos exec` changes the working directory; direct `dart test`
/// does not.
Directory _workspaceRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File(
      '${candidate.path}${Platform.pathSeparator}melos.yaml',
    ).existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not locate the repository workspace root.');
    }
    candidate = parent;
  }
}

void main() {
  group('Adapter Output & Conformance Fixtures', () {
    test('AdapterOutput serializes to conforming IR JSON structure', () {
      const output = AdapterOutput(
        targetId: 'backend',
        packageId: 'conformance_pkg',
        sourceAdapter: 'conformance.test',
        compatibilityId: 'v1',
        completeness: AdapterCompleteness(),
        nodes: [
          TopologyNode(
            id: 'implementation:testSymbol',
            kind: 'implementation',
            name: 'testSymbol',
            attributes: {
              'requirementIds': ['RULE-TEST-001'],
            },
          ),
        ],
      );

      final json = output.toJson();
      expect(json['kind'], equals('zuke.adapter-output'));
      expect(json['sourcePackage'], equals('conformance_pkg'));
      expect(json['target'], equals('backend'));
      expect(json['nodes'], hasLength(1));
    });

    test('adapter output conforms to contract schema', () {
      const output = AdapterOutput(
        targetId: 'backend',
        packageId: 'test_pkg',
        sourceAdapter: 'test.adapter',
        compatibilityId: 'compat-v1',
        completeness: AdapterCompleteness(),
        nodes: [],
      );

      final json = output.toJson();

      expect(json.containsKey('kind'), isTrue);
      expect(json['kind'], equals('zuke.adapter-output'));

      expect(json['target'], equals('backend'));
      expect(json['sourcePackage'], equals('test_pkg'));
      expect(json['sourceAdapter'], equals('test.adapter'));
      expect(json['sourceCompatibilityId'], equals('compat-v1'));

      final completeness = json['completeness'] as Map;
      expect(completeness.containsKey('routeRegistration'), isTrue);
      expect(completeness.containsKey('middlewareOrder'), isTrue);

      expect(json.containsKey('nodes'), isTrue);
      expect(json['nodes'], isA<List>());
    });

    test('incompatible adapter claims fail with stable diagnostic', () {
      expect(
        () => EvidenceRecord.fromJson({
          'kind': 'zuke.evidence-record',
          'requirementId': '',
          'evidenceType': 'domain-unit',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('non-empty'),
          ),
        ),
      );

      expect(
        () => EvidenceRecord.fromJson({
          'kind': 'zuke.evidence-record',
          'requirementId': 'RULE-TEST-001',
          'evidenceType': 'domain-unit',
          'target': '',
          'status': 'unknown',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            anyOf(
              contains('non-empty'),
              contains('Evidence'),
              contains('Unknown evidence status'),
            ),
          ),
        ),
      );
    });

    test('manifest schema validates', () async {
      final workspaceRoot = _workspaceRoot();
      final schemaPaths = <String>[
        'behavioral-assurance-manifest.schema.json',
        'behavioral-assurance-release.schema.json',
        'ed25519-trust.schema.json',
        'zuke.lock.schema.json',
      ];
      expect(schemaPaths, isNotEmpty);

      for (final schemaPath in schemaPaths) {
        final file = File(
          '${workspaceRoot.path}/vendor-sdk/zuke_conformance/lib/schemas/$schemaPath',
        );
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();
        final schema = jsonDecode(content) as Map;

        expect(schema.containsKey('\$schema'), isTrue);
        expect(
          schema['\$schema'],
          equals('https://json-schema.org/draft/2020-12/schema'),
        );
        expect(schema.containsKey('\$id'), isTrue);
        expect(schema.containsKey('type'), isTrue);
        expect(schema['type'], equals('object'));

        if (schema.containsKey('required')) {
          final required = schema['required'] as List;
          expect(required, isNotEmpty);
        }

        if (schema.containsKey('properties')) {
          final properties = schema['properties'] as Map;
          expect(properties, isNotEmpty);
        }
      }
    });
  });

  group('Melos Workspace Coverage', () {
    test('workspace package list covers every active SDK package', () {
      final workspaceRoot = _workspaceRoot();
      final melosFile = File('${workspaceRoot.path}/melos.yaml');
      expect(melosFile.existsSync(), isTrue);

      final melosContent = melosFile.readAsStringSync();
      final melos = loadYaml(melosContent);
      final packages = (melos['packages'] as List)
          .map((p) => p.toString())
          .toList();

      const activeDirectories = <String>{
        'zuke_core',
        'zuke_conformance',
        'zuke_analyzer',
        'zuke_dart_build_hook',
        'zuke_annotations',
        'zuke_frontend',
        'zuke_http_runtime',
        'zuke_runner',
        'zuke_runner_flutter',
        'zuke_test_support',
        'zuke_cli',
        'zuke_verifier',
      };

      for (final dirName in activeDirectories) {
        final covered = packages.any(
          (p) => p == 'vendor-sdk/$dirName' || p.startsWith('vendor-sdk/*'),
        );
        expect(
          covered,
          isTrue,
          reason: '$dirName is not covered by any melos package pattern',
        );
      }
    });
  });

  group('workflow profile progression', () {
    test('each assurance workflow invokes its owning profile', () {
      final root = _workspaceRoot();
      const expected = {
        'pr.yml': 'pullRequest',
        'merge.yml': 'merge',
        'nightly.yml': 'nightly',
        'release.yml': 'release',
      };
      for (final entry in expected.entries) {
        final workflow = File('${root.path}/.github/workflows/${entry.key}');
        expect(workflow.existsSync(), isTrue, reason: 'Missing ${entry.key}');
        final content = workflow.readAsStringSync();
        // Workflows may invoke the profile directly, or pass it to a
        // reusable workflow through a `with:` input. Accept both forms so
        // workflow refactors do not weaken the profile contract.
        final profileInvocation = RegExp(
          r'(?:--profile\s+|\bprofile:\s*)' + RegExp.escape(entry.value),
        );
        expect(
          profileInvocation.hasMatch(content),
          isTrue,
          reason: '${entry.key} must invoke ${entry.value}',
        );
      }
    });
  });

  group('Diagnostic registry', () {
    test('registers every stable diagnostic emitted by Dart tooling', () {
      final workspaceRoot = _workspaceRoot();
      final registryFile = File(
        '${workspaceRoot.path}/docs/diagnostic-registry.json',
      );
      expect(registryFile.existsSync(), isTrue);
      final registry = jsonDecode(registryFile.readAsStringSync()) as Map;
      expect(registry['kind'], 'zuke.diagnostic-registry');
      final defaults = registry['defaults'] as Map;
      expect(defaults['owner'], 'unknown');
      expect((defaults['remediation'] as String).trim(), isNotEmpty);
      final entries = (registry['diagnostics'] as List).cast<Map>();
      final codes = <String>{};
      final codePattern = RegExp(r'^(?:ZUKE|ZK)-[A-Z0-9]+(?:-[A-Z0-9]+)*$');
      for (final entry in entries) {
        final code = entry['code'];
        expect(code, isA<String>());
        expect(codePattern.hasMatch(code as String), isTrue);
        expect(codes.add(code), isTrue, reason: 'Duplicate diagnostic $code');
        expect(entry['severity'], anyOf('error', 'warning', 'info'));
        expect((entry['summary'] as String?)?.trim(), isNotEmpty);
      }

      final emitted = <String>{};
      final tooling = Directory('${workspaceRoot.path}/vendor-sdk');
      for (final file in tooling.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path.contains('.dart_tool')) {
          continue;
        }
        emitted.addAll(
          RegExp(
            r'(?:ZUKE|ZK)-[A-Z0-9]+(?:-[A-Z0-9]+)+',
          ).allMatches(file.readAsStringSync()).map((match) => match.group(0)!),
        );
      }
      expect(codes, containsAll(emitted));
    });
  });

  group('adversarial conformance catalog', () {
    test('references existing executable owner tests with unique IDs', () {
      final root = _workspaceRoot();
      final catalogFile = File(
        '${root.path}/vendor-sdk/zuke_conformance/fixtures/catalog.json',
      );
      expect(catalogFile.existsSync(), isTrue);
      final catalog = jsonDecode(catalogFile.readAsStringSync()) as Map;
      expect(catalog['schemaVersion'], 'zuke.conformance-catalog.v1');
      final ids = <String>{};
      for (final value in (catalog['cases'] as List).cast<Map>()) {
        final id = value['id'] as String;
        expect(ids.add(id), isTrue, reason: 'Duplicate catalog ID $id');
        expect(value['blocksRelease'], isTrue);
        final owner = value['owner'] as String;
        expect(
          File('${root.path}/vendor-sdk/$owner').existsSync(),
          isTrue,
          reason: 'Catalog owner missing: $owner',
        );
      }
    });
  });

  group('Checked-in schema instances', () {
    test('merge lock and trust instances satisfy their structural contracts', () {
      final root = _workspaceRoot();
      final lock =
          jsonDecode(
                File(
                  '${root.path}/examples/calculator-product/assurance/locks/merge.lock.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(lock['kind'], 'zuke.lock');
      final controls = lock['controls'] as Map;
      final assurances = controls.values
          .whereType<Map>()
          .map((value) => value['assurance'])
          .whereType<String>()
          .toSet();
      expect(assurances, contains('proven'));
      expect(assurances, contains('missing'));
      // Coverage runs on merge/PR profiles. Release attestations are
      // generated and verified by the authorized signing workflow, so they
      // must not be required in this checked-in merge lock.
      expect(lock['attestations'], isEmpty);
      // A proof-bearing lock scopes a control to its governing rule, while a
      // missing proof remains control-scoped. Both forms must describe the
      // active application-owned rate-limit semantic.
      final rateLimitControls = controls.entries
          .where(
            (entry) =>
                entry.key == 'CTRL-CALC-RATE-LIMIT' ||
                entry.key.toString().contains('|CTRL-CALC-RATE-LIMIT|'),
          )
          .map((entry) => entry.value)
          .whereType<Map>()
          .toList();
      expect(rateLimitControls, isNotEmpty);
      expect(
        rateLimitControls.any(
          (control) =>
              control['semantics'] == 'ingress-dominance' ||
              control['coverageSemantics'] == 'ingress-dominance',
        ),
        isTrue,
      );
      final provenErrorRedaction =
          controls['RULE-CALC-DIVISION|CTRL-CALC-ERROR-REDACTION|backend|default']
              as Map;
      expect(provenErrorRedaction['assurance'], 'proven');
      expect(
        provenErrorRedaction['providerIds'],
        contains('provider:PublicCalculatorErrorMapper'),
      );
      for (final field in [
        'policyHash',
        'evidenceRequirementsHash',
        'specificationDigest',
        'generatedManifestDigest',
      ]) {
        expect(lock[field], matches(RegExp(r'^sha256:[a-f0-9]{64}$')));
      }

      final trust =
          jsonDecode(
                File(
                  '${root.path}/examples/calculator-product/assurance-history/trust/ed25519.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(trust['kind'], 'zuke.ed25519-trust');
      final identities = <String>{};
      for (final key in (trust['keys'] as List).cast<Map>()) {
        expect(key['algorithm'], 'Ed25519');
        expect(base64Decode(key['publicKey'] as String), hasLength(32));
        expect(key['fingerprint'], matches(RegExp(r'^sha256:[a-f0-9]{64}$')));
        expect(key['status'], anyOf('active', 'revoked'));
        expect(identities.add('${key['signerId']}|${key['keyId']}'), isTrue);
      }
    });
  });

  group('attestation and evidence adversarial boundaries', () {
    test('fails malformed or unsigned external attestations', () async {
      const trust = TrustBundle([]);
      final verifier = SignedAttestationVerifier();
      expect(await verifier.verify(const {}, trust), isFalse);
      expect(
        await verifier.verify({
          'schemaVersion': 'zuke.external-attestation.v1',
          'signer': {'signerId': 'unknown', 'keyId': 'unknown'},
          'body': const {},
          'signature': 'not-base64',
        }, trust),
        isFalse,
      );
    });

    test('fails evidence records with an invalid digest envelope', () {
      expect(
        () => EvidenceRecord.fromJson({
          'schemaVersion': 'zuke.evidence-record.v1',
          'requirementId': 'RULE-TEST-001',
          'evidenceType': 'domain-unit',
          'target': 'backend',
          'status': 'passed',
          'digest': 'sha256:not-hex',
        }),
        throwsFormatException,
      );
    });
  });

  group('trace instance contract', () {
    test('canonical fragment emits the stable trace envelope', () {
      const output = IrAdapterOutput(
        adapter: AdapterInfo(
          id: 'trace.fixture',
          version: '1',
          compatibilityId: 'v1',
        ),
        completeness: IrAdapterCompleteness(),
        symbols: [],
        inputDigest: '0123456789abcdef',
        packageName: 'fixture',
        packageRoot: '/workspace/fixture',
      );
      final trace = CanonicalFragment.fromOutput(
        output,
        workspaceRoot: '/workspace',
      ).toJson();
      expect(trace['kind'], 'zuke.adapter-fragment');
      expect(trace['package'], {'name': 'fixture', 'root': 'fixture'});
      expect((trace['inputs'] as Map)['digest'], 'sha256:0123456789abcdef');
      expect(trace['completeness'], isA<Map>());
      expect(trace['symbols'], isA<List>());
    });
  });
}
