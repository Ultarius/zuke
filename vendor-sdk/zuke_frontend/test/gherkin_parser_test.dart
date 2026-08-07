import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  group('Path confinement', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuke_path_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('rejects paths that escape workspace root with ../ prefix', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
specifications:
  features:
    - ../specs/features/**/*.feature
''');
      Directory('${tempDir.path}/specs/features').createSync(recursive: true);
      File('${tempDir.path}/specs/features/test.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-TEST-001
# spec-end
Feature: Test
''');
      final result = WorkspaceDiscovery().discover(tempDir.path);
      expect(
        result.data.errors.any((e) => e.contains('escapes workspace root')),
        isTrue,
      );
    });

    test('rejects absolute path patterns', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
specifications:
  features:
    - /absolute/path/**/*.feature
''');
      Directory('${tempDir.path}/specs/features').createSync(recursive: true);
      File('${tempDir.path}/specs/features/test.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-TEST-001
# spec-end
Feature: Test
''');
      final result = WorkspaceDiscovery().discover(tempDir.path);
      expect(
        result.data.errors.any((e) => e.contains('escapes workspace root')),
        isTrue,
      );
    });

    test('rejects Windows absolute drive path patterns', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
specifications:
  features:
    - C:\\path\\**\\*.feature
''');
      Directory('${tempDir.path}/specs/features').createSync(recursive: true);
      File('${tempDir.path}/specs/features/test.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-TEST-001
# spec-end
Feature: Test
''');
      final result = WorkspaceDiscovery().discover(tempDir.path);
      expect(
        result.data.errors.any((e) => e.contains('escapes workspace root')),
        isTrue,
      );
    });
  });

  group('Symlink overlap', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuke_overlap_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'reports file matched by multiple patterns with all patterns listed',
      () {
        File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
specifications:
  features:
    - specs/features/**/*.feature
    - specs/features/*.feature
''');
        Directory('${tempDir.path}/specs/features').createSync(recursive: true);
        File('${tempDir.path}/specs/features/test.feature').writeAsStringSync(
          '''
# spec-begin
# schemaVersion: 1
# id: FEAT-TEST-001
# spec-end
Feature: Test
''',
        );
        final result = WorkspaceDiscovery().discover(tempDir.path);
        expect(
          result.data.errors.any(
            (e) => e.contains('matched by multiple patterns'),
          ),
          isTrue,
        );
      },
    );
  });

  group('Metadata validation', () {
    test('rejects duplicate feature metadata blocks without throwing', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-FIRST
# spec-end
# spec-begin
# schemaVersion: 1
# id: FEAT-SECOND
# spec-end
Feature: Duplicate feature metadata
''';

      final result = GherkinParser().parseFile(content, 'duplicate.feature');

      expect(result.features, isEmpty);
      expect(
        result.errors.single.message,
        contains('requires exactly one # spec-begin/# spec-end block'),
      );
    });

    test('rejects unterminated feature metadata blocks without throwing', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-UNTERMINATED
Feature: Unterminated metadata
''';

      final result = GherkinParser().parseFile(content, 'unterminated.feature');

      expect(result.features, isEmpty);
      expect(
        result.errors.single.message,
        contains('requires exactly one # spec-begin/# spec-end block'),
      );
    });

    test('reports malformed metadata YAML as a stable metadata error', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: [
# spec-end
Feature: Invalid YAML
''';

      final result = GherkinParser().parseFile(content, 'invalid-yaml.feature');

      expect(result.features, isEmpty);
      expect(result.errors.single.message, startsWith('Failed to parse:'));
    });

    test('reports a non-mapping metadata document without throwing', () {
      const content = '''
# spec-begin
# - not-a-map
# spec-end
Feature: List metadata
''';

      final result = GherkinParser().parseFile(content, 'list-yaml.feature');

      expect(result.features, isEmpty);
      expect(
        result.errors.single.message,
        contains('metadata must be a YAML mapping'),
      );
    });

    test('requires a non-empty feature id and schemaVersion 1', () {
      const content = '''
# spec-begin
# schemaVersion: 2
# id: ''
# spec-end
Feature: Invalid identity
''';

      final result = GherkinParser().parseFile(content, 'identity.feature');

      expect(result.errors, isEmpty);
      expect(
        result.features.single.metadata.errors,
        containsAll([
          'metadata requires a non-empty id',
          'feature metadata requires schemaVersion 1; found "2"',
        ]),
      );
    });

    test('rejects duplicate rule metadata blocks before one Rule', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-DUPLICATE-RULE-META
# spec-end
Feature: Duplicate rule metadata
  # rule-spec-begin
  # id: RULE-FIRST
  # rule-spec-end
  # rule-spec-begin
  # id: RULE-SECOND
  # rule-spec-end
  Rule: Duplicate metadata
''';

      final result = GherkinParser().parseFile(content, 'test.feature');

      expect(result.features, isEmpty);
      expect(
        result.errors.single.message,
        contains('requires exactly one # rule-spec-begin/# rule-spec-end'),
      );
    });

    test('rejects an orphan rule metadata block after the final Rule', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ORPHAN-RULE-META
# spec-end
Feature: Orphan rule metadata
  # rule-spec-begin
  # id: RULE-ONE
  # rule-spec-end
  Rule: Valid rule
  # rule-spec-begin
  # id: RULE-ORPHAN
  # rule-spec-end
''';

      final result = GherkinParser().parseFile(content, 'test.feature');

      expect(result.features, isEmpty);
      expect(result.errors.single.message, contains('orphan rule-spec block'));
    });

    test('rejects likely secret-bearing metadata values', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-SECRET-001
# x-deployment:
#   apiToken: super-secret-value
# spec-end
Feature: Secret metadata
''';

      final result = GherkinParser().parseFile(content, 'test.feature');

      expect(
        result.features.single.metadata.errors,
        contains('metadata may contain a secret at "x-deployment.apiToken"'),
      );
    });

    test('rejects private-key material even in an extension list', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-SECRET-002
# x-values:
#   - -----BEGIN PRIVATE KEY-----
# spec-end
Feature: Secret metadata
''';

      final result = GherkinParser().parseFile(content, 'test.feature');

      expect(result.features.single.metadata.errors, isNotEmpty);
    });

    test('allows nested x-* properties at any depth', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-X
# x-experimental:
#   nested: true
# spec-end
Feature: Experimental
''';
      final result = GherkinParser().parseFile(content, 'test.feature');
      expect(result.errors, isEmpty);
      expect(result.features.single.metadata.errors, isEmpty);
      expect(
        result.features.single.metadata.extensions['x-experimental'],
        equals({'nested': true}),
      );
    });

    test('rejects nested non-x- properties with full dotted path', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-ERR
# spec-end
Feature: Invalid
  # rule-spec-begin
  # id: RULE-CALC-ERR
  # typo: 1
  # rule-spec-end
  Rule: Invalid rule
''';
      final result = GherkinParser().parseFile(content, 'test.feature');
      final rule = result.features.single.rules.single;
      expect(rule.metadata.errors, isNotEmpty);
      expect(
        rule.metadata.errors.any(
          (e) => e.contains('unknown metadata field') && e.contains('typo'),
        ),
        isTrue,
      );
    });
  });

  group('Multiple Examples blocks', () {
    test('preserves multiple Examples blocks with titles', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-EXEC-001
# spec-end
Feature: Multi examples
  # rule-spec-begin
  # id: RULE-EXEC-001
  # rule-spec-end
  Rule: Test
    Scenario Outline: Adding values
      Given <left> and <right>
      Then result is <sum>
    Examples:
      | left | right | sum |
      | 2 | 3 | 5 |
      | 4 | 5 | 9 |
    Examples:
      | left | right | sum |
      | 10 | 20 | 30 |
''';
      final result = GherkinParser().parseFile(content, 'test.feature');
      expect(result.errors, isEmpty);
      final scenario = result.features.single.rules.single.scenarios.single;
      expect(scenario.examples, hasLength(2));
      expect(scenario.examples[0].title, equals('examples_0'));
      expect(scenario.examples[1].title, equals('examples_1'));
      expect(scenario.examples[0].rows, hasLength(2));
      expect(scenario.examples[1].rows, hasLength(1));
    });

    test('expands each row as a distinct instance in IR', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-EXEC-002
# spec-end
Feature: Multi examples IR
  # rule-spec-begin
  # id: RULE-EXEC-002
  # rule-spec-end
  Rule: Test
    Scenario Outline: Adding values
      Given <left> and <right>
      Then result is <sum>
    Examples:
      | left | right | sum |
      | 2 | 3 | 5 |
    Examples:
      | left | right | sum |
      | 10 | 20 | 30 |
      | 100 | 200 | 300 |
''';
      final result = GherkinParser().parseFile(content, 'test.feature');
      final scenario = result.features.single.rules.single.scenarios.single;
      final totalRows = scenario.examples.fold<int>(
        0,
        (sum, e) => sum + e.rows.length,
      );
      expect(totalRows, equals(3));
    });
  });

  group('GherkinParser', () {
    test(
      'parses metadata blocks and strips comment headers preserving YAML indent',
      () {
        const gherkinContent = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-001
# owner: platform-team
# targets:
#   - backend
#   - flutter
# spec-end

@EPIC-CALC-001 @FEAT-CALC-001
Feature: Basic calculator operations
  As a user I want to perform addition

  # rule-spec-begin
  # id: RULE-CALC-ADDITION
  # requires:
  #   - kind: control
  #     id: CTRL-CALC-INPUT-VALIDATION
  # rule-spec-end
  @PBI-CALC-001 @RULE-CALC-ADDITION
  Rule: Addition of two integers
''';

        final result = GherkinParser().parseFile(
          gherkinContent,
          'specs/features/test.feature',
        );
        expect(
          result.errors,
          isEmpty,
          reason: result.errors.map((error) => error.message).join('\n'),
        );
        expect(result.features, hasLength(1));

        final feature = result.features.first;
        expect(feature.metadata.id, equals('FEAT-CALC-001'));
        expect(feature.metadata.owner, equals('platform-team'));
        expect(feature.metadata.targets, containsAll(['backend', 'flutter']));

        expect(feature.rules, hasLength(1));
        final rule = feature.rules.first;
        expect(rule.metadata.id, equals('RULE-CALC-ADDITION'));
        expect(rule.metadata.requires, hasLength(1));
        expect(
          rule.metadata.requires!.first.id,
          equals('CTRL-CALC-INPUT-VALIDATION'),
        );
      },
    );

    test('uses the YAML AST for flow-style typed metadata', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-FLOW-001
# targets: [flutter, backend]
# bindings: {required: [{id: calculator.calculateAction, target: flutter, interaction: action}]}
# endpoints: [{id: calculator.evaluate, target: backend, method: POST, usage: reference}]
# spec-end
Feature: Flow metadata
''';

      final result = GherkinParser().parseFile(content, 'flow.feature');

      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((error) => error.message).join('\n'),
      );
      final metadata = result.features.single.metadata;
      expect(metadata.targets, ['flutter', 'backend']);
      expect(metadata.bindings, hasLength(1));
      expect(metadata.bindings!.single.interaction, 'action');
      expect(metadata.endpoints!.single.usage, 'reference');
    });

    test('rejects unknown metadata keys in spec blocks', () {
      const gherkinContent = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-INVALID
# unknownKeyHere: true
# spec-end

Feature: Feature with unknown metadata key
''';

      final result = GherkinParser().parseFile(
        gherkinContent,
        'specs/features/invalid.feature',
      );
      expect(result.features, hasLength(1));
      final feature = result.features.first;
      expect(feature.metadata.errors, isNotEmpty);
      expect(
        feature.metadata.errors.any(
          (e) => e.contains('unknown metadata field'),
        ),
        isTrue,
      );
    });

    test(
      'parses steps, background, tables, doc strings, outlines, and x extensions',
      () {
        const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-EXEC-001
# x-owner-system: calculator
# spec-end

Feature: Executable feature
  Background:
    Given the application is open
  # rule-spec-begin
  # id: RULE-EXEC-001
  # rule-spec-end
  Rule: Execute a calculation
    Background:
      Given the calculator is ready
    Scenario Outline: adds values
      When I submit <left> and <right>
      Then the result is <sum>
      """
      {"redacted": true}
      """
      And the request has:
        | name | value |
        | left | <left> |
    Examples:
      | left | right | sum |
      | 2 | 3 | 5 |
''';
        final result = GherkinParser().parseFile(
          content,
          'features/exec.feature',
        );
        expect(result.errors, isEmpty);
        final feature = result.features.single;
        expect(feature.metadata.extensions['x-owner-system'], 'calculator');
        expect(feature.backgroundSteps.single.text, 'the application is open');
        final rule = feature.rules.single;
        expect(rule.backgroundSteps.single.text, 'the calculator is ready');
        final scenario = rule.scenarios.single;
        expect(scenario.steps, hasLength(3));
        expect(scenario.steps[1].docString, contains('redacted'));
        expect(scenario.steps[2].table.first, ['name', 'value']);
        expect(scenario.examples.first.headers, ['left', 'right', 'sum']);
        expect(scenario.examples.first.rows.single, ['2', '3', '5']);
      },
    );

    test('preserves tags attached to each Examples block', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-EXAMPLES-TAGS
# spec-end

Feature: Example tags
  # rule-spec-begin
  # id: RULE-EXAMPLES-TAGS
  # rule-spec-end
  Rule: Tagged examples
    @SCN-EXAMPLES-TAGS
    Scenario Outline: selected by example tag
      Given a value <value>
      @release
      Examples: release values
        | value |
        | 1 |
      @nightly
      Examples: nightly values
        | value |
        | 2 |
''';
      final result = GherkinParser().parseFile(content, 'examples.feature');
      expect(result.errors, isEmpty);
      final examples =
          result.features.single.rules.single.scenarios.single.examples;
      expect(examples, hasLength(2));
      expect(examples[0].tags.map((tag) => tag.name), ['release']);
      expect(examples[1].tags.map((tag) => tag.name), ['nightly']);
    });

    test('keeps tags between scenarios with the following scenario', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-SCENARIO-TAGS
# spec-end

Feature: Scenario tags
  # rule-spec-begin
  # id: RULE-SCENARIO-TAGS
  # rule-spec-end
  Rule: Tagged scenarios
    @SCN-FIRST
    Scenario: first scenario
      Given a first value

    @SCN-SECOND
    Scenario: second scenario
      Given a second value
''';
      final result = GherkinParser().parseFile(content, 'scenarios.feature');
      expect(result.errors, isEmpty);
      final scenarios = result.features.single.rules.single.scenarios;
      expect(scenarios.map((scenario) => scenario.scenarioElement.title), [
        'first scenario',
        'second scenario',
      ]);
      expect(scenarios[0].tags.map((tag) => tag.name), ['SCN-FIRST']);
      expect(scenarios[1].tags.map((tag) => tag.name), ['SCN-SECOND']);
    });

    test('normalizes zeroOrMore binding cardinality to many', () {
      const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-CARDINALITY-ALIAS
# bindings:
#   required:
#     - id: list.item
#       target: flutter
#       cardinality: zeroOrMore
#       instanceCardinality: zeroOrMore
#       interaction: output
# spec-end

Feature: Cardinality alias
  # rule-spec-begin
  # id: RULE-CARDINALITY-ALIAS
  # rule-spec-end
  Rule: Alias support
    @SCN-CARDINALITY-ALIAS
    Scenario: parses the alias
      Given a list item
''';
      final result = GherkinParser().parseFile(content, 'cardinality.feature');
      expect(result.errors, isEmpty);
      expect(
        result.features.single.metadata.bindings!.single.cardinality,
        'many',
      );
      expect(
        result.features.single.metadata.bindings!.single.instanceCardinality,
        'many',
      );
    });
  });

  group('WorkspaceDiscovery', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuke_discovery_');
      for (final path in [
        'specs/features',
        'specs/epics',
        'specs/controls',
        'specs/registry',
        'specs/policies',
      ]) {
        Directory('${tempDir.path}/$path').createSync(recursive: true);
      }
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'loads every configured input and reports duplicate or invalid data',
      () {
        File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
specifications:
  features: [specs/features/**/*.feature]
  epics: [specs/epics/**/*.yaml]
  controls: [specs/controls/**/*.yaml]
  registries: [specs/registry/**/*.yaml]
policies:
  project: specs/policies/project.yaml
  profiles: [specs/policies/profile-*.yaml]
targets:
  flutter:
    contractOutput: packages/contracts/lib/src/generated
    contractExport: packages/contracts/lib/contracts.dart
lock:
  file: zuke.lock.json
evidence:
  output: generated/evidence
trust:
  bundle: trust/bundle.json
execution:
  runners: []
''');
        File('${tempDir.path}/specs/features/valid.feature').writeAsStringSync(
          '''
# spec-begin
# schemaVersion: 1
# id: FEAT-DISCOVERY
# spec-end
Feature: Discovery
''',
        );
        File(
          '${tempDir.path}/specs/features/invalid.feature',
        ).writeAsStringSync('Feature: Missing metadata');
        File(
          '${tempDir.path}/specs/epics/one.yaml',
        ).writeAsStringSync('id: EPIC-DUPLICATE\n');
        File(
          '${tempDir.path}/specs/epics/two.yaml',
        ).writeAsStringSync('id: EPIC-DUPLICATE\n');
        File(
          '${tempDir.path}/specs/epics/invalid.yaml',
        ).writeAsStringSync('id: [\n');
        File('${tempDir.path}/specs/controls/one.yaml').writeAsStringSync('''
controls:
  - id: CTRL-DUPLICATE
  - id: CTRL-DUPLICATE
''');
        File(
          '${tempDir.path}/specs/controls/invalid.yaml',
        ).writeAsStringSync('controls: [\n');
        File('${tempDir.path}/specs/registry/one.yaml').writeAsStringSync('''
schemaVersion: 1
endpoints:
  - id: ENDPOINT-DUPLICATE
    target: backend
    method: POST
events:
  - id: EVENT-ONE
featureFlags:
  - id: FLAG-ONE
pbis:
  - id: PBI-ONE
    title: PBI One
    owner: team
    feature: FEAT-CALC-001
    status: active
performanceProfiles:
  - id: PERF-ONE
retiredIds:
  - RULE-RETIRED
''');
        File('${tempDir.path}/specs/registry/two.yaml').writeAsStringSync('''
schemaVersion: 1
endpoints:
  - id: ENDPOINT-DUPLICATE
    target: backend
    method: POST
''');
        File(
          '${tempDir.path}/specs/registry/invalid.yaml',
        ).writeAsStringSync('endpoints: [\n');
        File(
          '${tempDir.path}/specs/policies/project.yaml',
        ).writeAsStringSync('id: project\n');
        File(
          '${tempDir.path}/specs/policies/profile-valid.yaml',
        ).writeAsStringSync('id: pullRequest\n');
        File(
          '${tempDir.path}/specs/policies/profile-invalid.yaml',
        ).writeAsStringSync('id: [\n');

        final result = WorkspaceDiscovery().discover(tempDir.path);

        expect(result.config.contractOutput, contains('generated'));
        expect(result.config.contractExport, contains('contracts.dart'));
        expect(result.config.lockFile, 'zuke.lock.json');
        expect(result.config.evidenceOutput, 'generated/evidence');
        expect(result.config.trustBundle, 'trust/bundle.json');
        expect(result.config.executionConfig['runners'], isEmpty);
        expect(result.data.features, hasLength(1));
        expect(result.data.epics, contains('EPIC-DUPLICATE'));
        expect(result.data.controls, contains('CTRL-DUPLICATE'));
        expect(
          result.data.registries.keys,
          containsAll([
            'ENDPOINT-DUPLICATE',
            'EVENT-ONE',
            'FLAG-ONE',
            'PBI-ONE',
            'PERF-ONE',
            'retired:RULE-RETIRED',
          ]),
        );
        expect(result.data.policies, hasLength(2));
        expect(
          result.data.errors,
          containsAll([
            contains('requires exactly one'),
            contains('Duplicate Epic ID'),
            contains('Duplicate Control ID'),
            contains('Duplicate registry entry'),
            contains('Failed to parse YAML'),
          ]),
        );
      },
    );

    test('uses defaults for a missing or malformed configuration', () {
      final missing = WorkspaceDiscovery().discover(tempDir.path);
      expect(missing.config.featurePatterns, ['specs/features/**/*.feature']);

      File('${tempDir.path}/zuke.yaml').writeAsStringSync('[');
      final malformed = WorkspaceDiscovery().discover(tempDir.path);
      expect(malformed.config.featurePatterns, ['specs/features/**/*.feature']);
    });

    test(
      'rejects legacy version key and missing schemaVersion in registry files',
      () {
        final regDir = Directory('${tempDir.path}/specs/registry');
        File('${regDir.path}/legacy.yaml').writeAsStringSync('''
version: zuke.pbi.v1
pbis:
  - id: PBI-LEGACY
''');
        final result = WorkspaceDiscovery().discover(tempDir.path);
        expect(
          result.data.errors,
          contains(
            contains('Legacy "version:" key is unsupported in registry YAML'),
          ),
        );
      },
    );
    test('rejects malformed registry lists and incomplete entries', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: registry-test
  root: .
specifications:
  registry: [specs/registry/**/*.yaml]
targets: {}
''');
      File('${tempDir.path}/specs/registry/invalid.yaml').writeAsStringSync('''
schemaVersion: 1
endpoints: not-a-list
events:
  - title: missing id
featureFlags:
  - id: ''
pbis:
  - id: PBI-INCOMPLETE
    title: PBI
    owner: team
performanceProfiles:
  - 42
retiredIds: [RULE-RETIRED, '', 99]
''');

      final result = WorkspaceDiscovery().discover(tempDir.path);

      expect(
        result.data.errors,
        containsAll([
          contains('Registry "endpoints" must be a list'),
          contains('events entry at index 0 is missing required field "id"'),
          contains(
            'featureFlags entry at index 0 is missing required field "id"',
          ),
          contains(
            'pbis entry "PBI-INCOMPLETE" is missing required field "feature"',
          ),
          contains(
            'pbis entry "PBI-INCOMPLETE" is missing required field "status"',
          ),
          contains('performanceProfiles entry at index 0 must be a mapping'),
          contains('retiredIds entry at index 1 must be a non-empty string'),
          contains('retiredIds entry at index 2 must be a non-empty string'),
        ]),
      );
      expect(result.data.registries, contains('retired:RULE-RETIRED'));
      expect(result.data.registries, isNot(contains('PBI-INCOMPLETE')));
    });
  });
}
