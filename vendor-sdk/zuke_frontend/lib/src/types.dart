/// Source coordinates for a parsed element.
class SourceLocation {
  /// Source file path.
  final String file;

  /// One-based start line.
  final int line;

  /// One-based start column, when known.
  final int column;

  /// One-based end line, when known.
  final int endLine;

  /// One-based end column, when known.
  final int endColumn;

  /// Creates a source location.
  const SourceLocation({
    required this.file,
    required this.line,
    this.column = 0,
    this.endLine = 0,
    this.endColumn = 0,
  });
}

/// Metadata extracted from a `# spec-begin` block.
class ParsedMetadata {
  /// Declared metadata schema version.
  final String? schemaVersion;

  /// Governed identifier declared by the block.
  final String? id;

  /// Owning epic identifier.
  final String? epic;

  /// Owning team or person.
  final String? owner;

  /// Lifecycle status.
  final String? status;

  /// Declared execution targets.
  final List<String>? targets;

  /// Product backlog item identifiers.
  final List<String>? pbis;

  /// UI binding metadata.
  final List<ParsedBinding>? bindings;

  /// Logical endpoint metadata.
  final List<ParsedEndpoint>? endpoints;

  /// Declared event identifiers.
  final List<String>? events;

  /// Declared feature flags.
  final List<String>? featureFlags;

  /// Performance thresholds.
  final List<ParsedPerformance>? performance;

  /// Referenced controls.
  final List<ParsedControlRef>? requires;

  /// Required evidence types.
  final List<String>? requiredEvidence;

  /// V3 exact evidence slots. Each map is validated by the proof engine.
  final List<Map<String, String>>? evidenceRequirements;

  /// Security profile name.
  final String? securityProfile;

  /// Forward-compatible metadata extensions.
  final Map<String, Object?> extensions;

  /// Source location of the metadata block.
  final SourceLocation source;

  /// Metadata parsing errors.
  final List<String> errors;

  /// Creates parsed metadata with [source] as its origin.
  const ParsedMetadata({
    this.schemaVersion,
    this.id,
    this.epic,
    this.owner,
    this.status,
    this.targets,
    this.pbis,
    this.bindings,
    this.endpoints,
    this.events,
    this.featureFlags,
    this.performance,
    this.requires,
    this.requiredEvidence,
    this.evidenceRequirements,
    this.securityProfile,
    this.extensions = const {},
    this.errors = const [],
    required this.source,
  });
}

/// Metadata describing a generated UI binding.
class ParsedBinding {
  /// Stable binding identifier.
  final String id;

  /// Binding execution target.
  final String target;

  /// Provider cardinality.
  final String cardinality;

  /// Runtime multiplicity of widgets represented by this logical binding.
  ///
  /// This intentionally differs from [cardinality], which is the number of
  /// annotated proof providers.  The stored vocabulary uses `many`; the
  /// `zeroOrMore` spelling is accepted as an input alias.
  final String instanceCardinality;

  /// Variant selected by the binding.
  final String variant;

  /// Binding slot selected by the binding.
  final String slot;

  /// Declares how a Flutter scenario driver uses this binding.
  ///
  /// `input` values are entered, `action` values are tapped, and `output`
  /// values are read. It is intentionally nullable for backwards-compatible
  /// parsing of existing feature metadata.
  final String? interaction;

  /// Creates parsed binding metadata.
  const ParsedBinding({
    required this.id,
    required this.target,
    this.cardinality = 'exactlyOne',
    this.instanceCardinality = 'exactlyOne',
    this.variant = 'default',
    this.slot = 'primary',
    this.interaction,
  });
}

/// Canonicalizes accepted binding-cardinality spellings.
///
/// `many` is the stored vocabulary. `zeroOrMore` is accepted for callers
/// familiar with regular-expression cardinality terminology.
String canonicalBindingCardinality(String cardinality) => switch (cardinality) {
  'zeroOrMore' => 'many',
  _ => cardinality,
};

/// Canonicalizes accepted runtime-widget cardinality spellings.
String canonicalBindingInstanceCardinality(String cardinality) =>
    canonicalBindingCardinality(cardinality);

/// Metadata describing a logical endpoint.
class ParsedEndpoint {
  /// Stable endpoint identifier.
  final String id;

  /// Endpoint execution target.
  final String target;

  /// HTTP method, when declared.
  final String? method;

  /// Endpoint contract name.
  final String? contract;

  /// Endpoint usage description.
  final String? usage;

  /// Creates parsed endpoint metadata.
  const ParsedEndpoint({
    required this.id,
    this.target = 'backend',
    this.method,
    this.contract,
    this.usage,
  });
}

/// A performance threshold declared by a specification.
class ParsedPerformance {
  /// Stable performance profile identifier.
  final String id;

  /// Profile execution target.
  final String target;

  /// Human-readable threshold expression.
  final String threshold;

  /// Percentile at which the threshold applies.
  final int percentile;

  /// Profile name.
  final String profile;

  /// Creates a performance threshold.
  const ParsedPerformance({
    required this.id,
    required this.target,
    required this.threshold,
    required this.percentile,
    required this.profile,
  });
}

/// A control reference required by a specification.
class ParsedControlRef {
  /// Control reference kind.
  final String kind;

  /// Stable control identifier.
  final String id;

  /// Control execution target.
  final String target;

  /// Required provider cardinality.
  final String cardinality;

  /// Acceptable assurance states.
  final List<String>? acceptableAssurance;

  /// Provider variant.
  final String variant;

  /// Provider slot.
  final String slot;

  /// Creates a control reference.
  const ParsedControlRef({
    this.kind = 'control',
    required this.id,
    this.target = 'backend',
    this.cardinality = 'oneOrMore',
    this.acceptableAssurance,
    this.variant = 'default',
    this.slot = 'primary',
  });
}

/// A tag attached to a Gherkin element.
class GherkinTag {
  /// Tag name without its leading `@`.
  final String name;

  /// Location of the tag in the source file.
  final SourceLocation source;

  /// Creates a parsed tag.
  const GherkinTag({required this.name, required this.source});
}

/// Gherkin element kinds recognized by the parser.
enum GherkinKeyword {
  /// A feature declaration.
  feature,

  /// A rule declaration.
  rule,

  /// A scenario declaration.
  scenario,

  /// A background declaration.
  background,

  /// A scenario outline declaration.
  scenarioOutline,
}

/// A parsed feature, rule, or scenario element.
class GherkinElement {
  /// Element keyword.
  final GherkinKeyword keyword;

  /// Human-readable element title.
  final String title;

  /// Element source location.
  final SourceLocation source;

  /// Tags attached to the element.
  final List<GherkinTag> tags;

  /// Nested parsed elements.
  final List<GherkinElement> children;

  /// Background description, when present.
  final String? backgroundDescription;

  /// Free-form element description.
  final String? description;

  /// Creates a parsed Gherkin element.
  const GherkinElement({
    required this.keyword,
    required this.title,
    required this.source,
    this.tags = const [],
    this.children = const [],
    this.backgroundDescription,
    this.description,
  });
}

/// A complete parsed Gherkin feature.
class ParsedFeature {
  /// Feature metadata.
  final ParsedMetadata metadata;

  /// Feature tags.
  final List<GherkinTag> tags;

  /// Parsed feature element.
  final GherkinElement featureElement;

  /// Rules declared by the feature.
  final List<ParsedRule> rules;

  /// Feature background steps.
  final List<GherkinStep> backgroundSteps;

  /// Creates a parsed feature.
  const ParsedFeature({
    required this.metadata,
    required this.tags,
    required this.featureElement,
    required this.rules,
    this.backgroundSteps = const [],
  });
}

/// A parsed Gherkin rule and its scenarios.
class ParsedRule {
  /// Rule metadata.
  final ParsedMetadata metadata;

  /// Rule tags.
  final List<GherkinTag> tags;

  /// Parsed rule element.
  final GherkinElement ruleElement;

  /// Scenarios owned by the rule.
  final List<GherkinScenario> scenarios;

  /// Rule background steps.
  final List<GherkinStep> backgroundSteps;

  /// Creates a parsed rule.
  const ParsedRule({
    required this.metadata,
    required this.tags,
    required this.ruleElement,
    required this.scenarios,
    this.backgroundSteps = const [],
  });
}

/// A parsed executable Gherkin scenario.
class GherkinScenario {
  /// Scenario tags.
  final List<GherkinTag> tags;

  /// Parsed scenario element.
  final GherkinElement scenarioElement;

  /// Executable scenario steps.
  final List<GherkinStep> steps;

  /// Examples blocks for a scenario outline.
  final List<GherkinExamples> examples;

  /// Creates a parsed scenario.
  const GherkinScenario({
    required this.tags,
    required this.scenarioElement,
    this.steps = const [],
    this.examples = const [],
  });

  /// Alias for [examples] retained for parser consumers.
  List<GherkinExamples> get examplesBlocks => examples;
}

/// One executable step in a Gherkin scenario.
class GherkinStep {
  /// Step keyword, such as `Given` or `When`.
  final String keyword;

  /// Keyword inherited from a preceding `And` or `But` step.
  final String inheritedKeyword;

  /// Step text without its keyword.
  final String text;

  /// Step source location.
  final SourceLocation source;

  /// Attached doc string content.
  final String? docString;

  /// Media type declared for [docString].
  final String? docStringMediaType;

  /// Indentation of the doc string.
  final int docStringIndent;

  /// Parsed data table rows.
  final List<List<String>> table;

  /// Creates a parsed step.
  const GherkinStep({
    required this.keyword,
    this.inheritedKeyword = '',
    required this.text,
    required this.source,
    this.docString,
    this.docStringMediaType,
    this.docStringIndent = 0,
    this.table = const [],
  });
}

/// An Examples table attached to a scenario outline.
class GherkinExamples {
  /// Examples block title.
  final String title;

  /// Examples tags.
  final List<GherkinTag> tags;

  /// Column headers.
  final List<String> headers;

  /// Example data rows.
  final List<List<String>> rows;

  /// Examples source location.
  final SourceLocation source;

  /// Creates an Examples block.
  const GherkinExamples({
    required this.title,
    this.tags = const [],
    required this.headers,
    required this.rows,
    required this.source,
  });
}
