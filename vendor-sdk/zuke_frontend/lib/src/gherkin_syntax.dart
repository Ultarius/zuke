/// The Gherkin vocabulary shared by the parser and every structural projection
/// of a specification.
///
/// The parser is English-keyword-only, and every place that classifies a line —
/// the parser's block scanning and the evidence/lock projections — reads these
/// tokens. A keyword therefore exists once; adding a synonym here (and to the
/// group it belongs to) teaches both the parser and the projections at the same
/// time.
abstract final class GherkinSyntax {
  /// `Feature:` opens the document.
  static const feature = 'Feature:';

  /// `Rule:` opens a business-rule block.
  static const rule = 'Rule:';

  /// `Scenario:` opens a plain scenario.
  static const scenario = 'Scenario:';

  /// `Scenario Outline:` opens a scenario with an example table.
  static const scenarioOutline = 'Scenario Outline:';

  /// `Background:` opens the shared steps of its container.
  static const background = 'Background:';

  /// `Examples:` opens an example table.
  static const examples = 'Examples:';

  /// The stem every scenario keyword starts with, used for source columns.
  static const scenarioStem = 'Scenario';

  /// Every structural keyword, as the projections scan them.
  static const keywords = <String>[
    feature,
    rule,
    scenarioOutline,
    scenario,
    background,
    examples,
  ];

  /// Keywords that open a scenario, including outline synonyms.
  static const scenarioKeywords = <String>[scenario, scenarioOutline];

  /// Keywords that end a feature description or a rule body.
  static const blockOpeners = <String>[
    rule,
    background,
    scenario,
    scenarioOutline,
  ];

  /// Keywords the backward tag scan is allowed to step over.
  static const tagScanOpeners = <String>[rule, scenario];

  /// Step keywords the parser accepts.
  static const stepKeywords = <String>['Given', 'When', 'Then', 'And', 'But'];

  /// A line that opens a step: a step keyword followed by whitespace.
  static final stepPrefix = RegExp('^(${stepKeywords.join('|')})\\s+');

  /// A complete step line, capturing its text.
  static final step = RegExp('^(${stepKeywords.join('|')})\\s+(.+)\$');

  /// The structural keyword [line] opens, or null when it opens none.
  static String? keywordOf(String line) {
    for (final keyword in keywords) {
      if (line.startsWith(keyword)) return keyword;
    }
    return null;
  }

  /// Whether [line] opens one of [openers].
  static bool opens(String line, Iterable<String> openers) =>
      openers.any(line.startsWith);
}
