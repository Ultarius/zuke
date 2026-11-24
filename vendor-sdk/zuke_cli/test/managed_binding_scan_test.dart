import 'package:test/test.dart';

import 'support/managed_binding_fixture.dart';

void main() {
  final fixture = ManagedBindingFixture();
  final source = fixture.source;
  final contract = fixture.contract;
  final scan = fixture.scan;
  final kindsOf = fixture.kindsOf;

  group('registration provenance', () {
    test('two targets registering one scenario stay two claims', () async {
      // The defect this pins: merging by scenario ID kept the first file and
      // target, so a backend widget registration merged into an app claim and
      // published a kind the app target never declared.
      contract();
      source('app/test/app_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['unit']);
}
''');
      source('api/test/api_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['flutter-widget']);
}
''');

      final claims = (await scan()).managedScenarios
          .where((claim) => claim.scenarioId == 'SCN-DEMO-001')
          .toList();

      expect(claims, hasLength(2), reason: 'one claim per registration site');
      expect(claims.map((claim) => claim.target).toSet(), {
        'app',
        'backend',
      }, reason: 'each claim keeps the target its own file resolved to');
      expect(claims.map((claim) => claim.evidenceTypes!.single).toSet(), {
        'unit',
        'flutter-widget',
      }, reason: "neither claim absorbs the other's kinds");
    });

    test('a claim carries the package its own file belongs to', () async {
      contract();
      source('api/test/api_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['api-contract']);
}
''');

      final claim = (await scan()).managedScenarios.single;
      expect(claim.target, 'backend');
      expect(claim.packageId, 'api-pkg');
    });

    test('a file outside every configured package has no target', () async {
      contract();
      source('test/loose_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['unit']);
}
''');

      final claim = (await scan()).managedScenarios.single;
      // Null, not a guess: an unattributable registration cannot satisfy a slot
      // that names a target, and must not be reported as absent either.
      expect(claim.target, isNull);
      expect(claim.packageId, isNull);
    });
  });

  group('reading declared evidence kinds', () {
    test('a literal list reads completely', () async {
      expect(await kindsOf("const ['a', 'b']"), ['a', 'b']);
    });

    test('a constant reference reads through the constant', () async {
      expect(await kindsOf('more'), ['domain-unit']);
    });

    test('a spread is unknown, not the elements around it', () async {
      // Returning ['unit'] here would report a complete reading of a list that
      // may also publish other kinds, which could invent a gap or hide one.
      expect(await kindsOf("const ['unit', ...more]"), isNull);
    });

    test('a collection-if is unknown, not the elements around it', () async {
      expect(await kindsOf("const ['unit', if (false) 'x']"), isNull);
    });

    test('a nonconstant expression is unknown', () async {
      expect(await kindsOf('buildKinds()'), isNull);
    });
  });
}
