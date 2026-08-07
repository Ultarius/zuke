class SourceLocation {
  final String file;
  final int line;
  final int column;
  final int endLine;
  final int endColumn;

  const SourceLocation({
    required this.file,
    required this.line,
    this.column = 0,
    this.endLine = 0,
    this.endColumn = 0,
  });
}

class ParsedMetadata {
  final String? schemaVersion;
  final String? id;
  final String? epic;
  final String? owner;
  final String? status;
  final List<String>? targets;
  final List<String>? pbis;
  final List<ParsedBinding>? bindings;
  final List<ParsedEndpoint>? endpoints;
  final List<String>? events;
  final List<String>? featureFlags;
  final List<ParsedPerformance>? performance;
  final List<ParsedControlRef>? requires;
  final List<String>? requiredEvidence;
  final String? securityProfile;
  final Map<String, Object?> extensions;
  final SourceLocation source;
  final List<String> errors;

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
    this.securityProfile,
    this.extensions = const {},
    this.errors = const [],
    required this.source,
  });
}

class ParsedBinding {
  final String id;
  final String target;
  final String cardinality;

  /// Runtime multiplicity of widgets represented by this logical binding.
  ///
  /// This intentionally differs from [cardinality], which is the number of
  /// annotated proof providers.  The stored vocabulary uses `many`; the
  /// `zeroOrMore` spelling is accepted as an input alias.
  final String instanceCardinality;
  final String variant;
  final String slot;

  /// Declares how a Flutter scenario driver uses this binding.
  ///
  /// `input` values are entered, `action` values are tapped, and `output`
  /// values are read. It is intentionally nullable for backwards-compatible
  /// parsing of existing feature metadata.
  final String? interaction;

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

class ParsedEndpoint {
  final String id;
  final String target;
  final String? method;
  final String? contract;
  final String? usage;

  const ParsedEndpoint({
    required this.id,
    this.target = 'backend',
    this.method,
    this.contract,
    this.usage,
  });
}

class ParsedPerformance {
  final String id;
  final String target;
  final String threshold;
  final int percentile;
  final String profile;

  const ParsedPerformance({
    required this.id,
    required this.target,
    required this.threshold,
    required this.percentile,
    required this.profile,
  });
}

class ParsedControlRef {
  final String kind;
  final String id;
  final String target;
  final String cardinality;
  final List<String>? acceptableAssurance;
  final String variant;
  final String slot;

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

class GherkinTag {
  final String name;
  final SourceLocation source;

  const GherkinTag({required this.name, required this.source});
}

enum GherkinKeyword { feature, rule, scenario, background, scenarioOutline }

class GherkinElement {
  final GherkinKeyword keyword;
  final String title;
  final SourceLocation source;
  final List<GherkinTag> tags;
  final List<GherkinElement> children;
  final String? backgroundDescription;
  final String? description;

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

class ParsedFeature {
  final ParsedMetadata metadata;
  final List<GherkinTag> tags;
  final GherkinElement featureElement;
  final List<ParsedRule> rules;
  final List<GherkinStep> backgroundSteps;

  const ParsedFeature({
    required this.metadata,
    required this.tags,
    required this.featureElement,
    required this.rules,
    this.backgroundSteps = const [],
  });
}

class ParsedRule {
  final ParsedMetadata metadata;
  final List<GherkinTag> tags;
  final GherkinElement ruleElement;
  final List<GherkinScenario> scenarios;
  final List<GherkinStep> backgroundSteps;

  const ParsedRule({
    required this.metadata,
    required this.tags,
    required this.ruleElement,
    required this.scenarios,
    this.backgroundSteps = const [],
  });
}

class GherkinScenario {
  final List<GherkinTag> tags;
  final GherkinElement scenarioElement;
  final List<GherkinStep> steps;
  final List<GherkinExamples> examples;

  const GherkinScenario({
    required this.tags,
    required this.scenarioElement,
    this.steps = const [],
    this.examples = const [],
  });

  List<GherkinExamples> get examplesBlocks => examples;
}

class GherkinStep {
  final String keyword;
  final String inheritedKeyword;
  final String text;
  final SourceLocation source;
  final String? docString;
  final String? docStringMediaType;
  final int docStringIndent;
  final List<List<String>> table;

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

class GherkinExamples {
  final String title;
  final List<GherkinTag> tags;
  final List<String> headers;
  final List<List<String>> rows;
  final SourceLocation source;

  const GherkinExamples({
    required this.title,
    this.tags = const [],
    required this.headers,
    required this.rows,
    required this.source,
  });
}
