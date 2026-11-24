import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  String feature(String table) =>
      '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end
Feature: One
  # rule-spec-begin
  # id: RULE-ONE-001
  # rule-spec-end
  Rule: Does things
    Scenario Outline: Adds <value>
      Given a value <value>
      @SCN-ONE-001
      Examples:
$table
''';

  GherkinScenario scenarioOf(String table) {
    final parsed = GherkinParser().parseFile(feature(table), 'one.feature');
    expect(parsed.errors, isEmpty);
    return parsed.features.single.rules.single.scenarios.single;
  }

  List<List<String>> rowsOf(String table) =>
      scenarioOf(table).examples.single.rows;

  test('a comment between rows does not drop later cases', () {
    expect(
      rowsOf('''
        | value |
        | 1     |
        # a reviewer note
        | 2     |
        | 3     |'''),
      [
        ['1'],
        ['2'],
        ['3'],
      ],
    );
  });

  test('a blank line between rows does not drop later cases', () {
    expect(
      rowsOf('''
        | value |

        | 1     |

        | 2     |'''),
      [
        ['1'],
        ['2'],
      ],
    );
  });

  test('a commented-out row is not a case', () {
    expect(
      rowsOf('''
        | value |
        # | 1   |
        | 2     |'''),
      [
        ['2'],
      ],
    );
  });

  test('other content ends the table', () {
    expect(
      rowsOf('''
        | value |
        | 1     |
        stray text
        | 2     |'''),
      [
        ['1'],
      ],
    );
  });

  test('accepts readable caseId values across Examples blocks', () {
    final scenario = scenarioOf('''
        | caseId      | value |
        | first-case  | 1     |
        | second-case | 2     |
      @SCN-ONE-002
      Examples: Another block
        | caseId     | value |
        | third-case | 3     |''');

    expect(scenario.examples.map((block) => block.rows.length), [2, 1]);
  });

  for (final (name, table, message) in const [
    (
      'a duplicate',
      '''
        | caseId | value |
        | same   | 1     |
        | same   | 2     |''',
      'more than once',
    ),
    (
      'a duplicate in another block',
      '''
        | caseId | value |
        | same   | 1     |
      @SCN-ONE-002
      Examples: Another block
        | caseId | value |
        | same   | 2     |''',
      'more than once',
    ),
    (
      'a value that is not kebab-case',
      '''
        | caseId    | value |
        | Not Valid | 1     |''',
      'lowercase kebab-case',
    ),
    (
      'an empty value',
      '''
        | caseId | value |
        |        | 1     |''',
      'lowercase kebab-case',
    ),
    (
      'a reserved positional value',
      '''
        | caseId           | value |
        | examples-1-row-2 | 1     |''',
      'reserved',
    ),
    (
      'a repeated column',
      '''
        | caseId | caseId | value |
        | one    | two    | 1     |''',
      'more than one caseId column',
    ),
    (
      'a row without every cell',
      '''
        | caseId | value |
        | one    |''',
      'cells',
    ),
  ]) {
    test('rejects $name in a caseId column', () {
      final source = feature(table);
      final parsed = GherkinParser().parseFile(source, 'one.feature');

      expect(parsed.features, isEmpty);
      final error = parsed.errors.single;
      expect(error.message, contains(message));
      expect(
        source.split('\n')[error.source.line - 1].trim(),
        startsWith('Examples:'),
      );
    });
  }

  test('declaredTags includes tags on Examples blocks', () {
    final scenario = scenarioOf('''
        | value |
        | 1     |''');
    expect(scenario.tags, isEmpty);
    expect(scenario.declaredTags.map((tag) => tag.name), ['SCN-ONE-001']);
  });

  for (final delimiter in ['"""', "'''"]) {
    test('a typed $delimiter doc string can mention Examples and tags', () {
      const payload = [
        'Examples: this is payload text',
        '@not-a-tag',
        '| not | a | table |',
        'Scenario: not a scenario',
        'Rule: not a rule',
        'Background: not a background',
        '# spec-begin',
        '# spec-end',
        '# rule-spec-begin',
        '# rule-spec-end',
      ];
      final source =
          '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end
Feature: One
  # rule-spec-begin
  # id: RULE-ONE-001
  # rule-spec-end
  Rule: Does things
    @SCN-ONE-001
    Scenario: Carries a document
      Given a document
        ${delimiter}application/json
        ${payload.join('\n        ')}
        $delimiter
      Then it is stored
''';

      for (final content in [
        source,
        source.replaceAll('\n', '\r\n'),
        source.replaceAll('\n', '\r'),
      ]) {
        final parsed = GherkinParser().parseFile(content, 'one.feature');
        expect(parsed.errors, isEmpty);
        final scenario = parsed.features.single.rules.single.scenarios.single;
        expect(scenario.examples, isEmpty);
        expect(scenario.declaredTags.map((tag) => tag.name), ['SCN-ONE-001']);
        expect(scenario.steps.map((step) => step.text), [
          'a document',
          'it is stored',
        ]);
        final step = scenario.steps.first;
        expect(step.docStringMediaType, 'application/json');
        expect(step.docStringIndent, 8);
        expect(step.docString, payload.map((line) => '        $line\n').join());
      }
    });

    test('reports an unclosed typed $delimiter doc string where it opens', () {
      final source =
          '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end
Feature: One
  # rule-spec-begin
  # id: RULE-ONE-001
  # rule-spec-end
  Rule: Does things
    @SCN-ONE-001
    Scenario: Never closes its document
      Given a document
        ${delimiter}json
        text
    @SCN-ONE-002
    Scenario: Would be hidden
      Then it is stored
''';
      final parsed = GherkinParser().parseFile(source, 'one.feature');

      expect(parsed.features, isEmpty);
      final error = parsed.errors.single;
      expect(error.message, contains('never closed'));
      expect(error.source.line, 13);
      expect(
        source.split('\n')[error.source.line - 1].trim(),
        '${delimiter}json',
      );
    });
  }

  test('reports a second doc string on one step where it opens', () {
    const source = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end
Feature: One
  # rule-spec-begin
  # id: RULE-ONE-001
  # rule-spec-end
  Rule: Does things
    @SCN-ONE-001
    Scenario: Carries two documents
      Given a document
        """
        first
        """
        \'\'\'
        second
        \'\'\'
      Then it is stored
        """
        allowed on the next step
        """
''';
    final parsed = GherkinParser().parseFile(source, 'one.feature');

    expect(parsed.features, isEmpty);
    final error = parsed.errors.single;
    expect(error.message, contains('already has a doc string'));
    expect(error.source.line, 16);
  });

  test('step-like feature prose does not open a doc string', () {
    final parsed = GherkinParser().parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end
Feature: One
  Given is the keyword for a precondition.
  """json
  # rule-spec-begin
  # id: RULE-ONE-001
  # rule-spec-end
  Rule: Stores a document
    Scenario: Carries a document
      Given a document
''', 'one.feature');

    expect(parsed.errors, isEmpty);
    final step =
        parsed.features.single.rules.single.scenarios.single.steps.single;
    expect(step.text, 'a document');
    expect(step.docString, isNull);
  });

  test(
    'reports a missing or header-only table at the Examples declaration',
    () {
      for (final table in ['', '        | value |']) {
        final source = feature('''
$table
      @SCN-ONE-002
      Examples: Another block
        | value |
        | 2     |''');
        final parsed = GherkinParser().parseFile(source, 'one.feature');
        expect(parsed.features, isEmpty);
        final error = parsed.errors.single;
        expect(error.message, contains('at least one data row'));
        expect(source.split('\n')[error.source.line - 1].trim(), 'Examples:');
      }
    },
  );
}
