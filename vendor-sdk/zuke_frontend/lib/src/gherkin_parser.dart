import 'types.dart';
import 'package:yaml/yaml.dart';

/// Result of parsing one feature document.
class GherkinParseResult {
  /// Features parsed from the document.
  final List<ParsedFeature> features;

  /// Errors encountered while parsing.
  final List<ParseError> errors;

  /// Creates a parse result.
  const GherkinParseResult({this.features = const [], this.errors = const []});
}

/// A parser error with its source location.
class ParseError {
  /// Human-readable error message.
  final String message;

  /// Location at which the error was detected.
  final SourceLocation source;

  /// Creates a parse error.
  const ParseError({required this.message, required this.source});
}

/// Parses Zuke's metadata-aware Gherkin dialect.
class GherkinParser {
  String? _lastFile;

  /// Parses [content] as the feature at [file].
  GherkinParseResult parseFile(String content, String file) {
    _lastFile = file;
    final lines = content.split('\n');
    final errors = <ParseError>[];
    final features = <ParsedFeature>[];

    try {
      final parsed = _parseDocument(lines, file);
      if (parsed != null) {
        features.add(parsed);
      }
    } catch (e) {
      errors.add(
        ParseError(
          message: 'Failed to parse: $e',
          source: SourceLocation(file: file, line: 1),
        ),
      );
    }

    return GherkinParseResult(features: features, errors: errors);
  }

  ParsedFeature? _parseDocument(List<String> lines, String file) {
    final beginCount = lines
        .where((line) => line.trim() == '# spec-begin')
        .length;
    final endCount = lines.where((line) => line.trim() == '# spec-end').length;
    if (beginCount != 1 || endCount != 1) {
      throw FormatException(
        'feature metadata requires exactly one # spec-begin/# spec-end block',
      );
    }
    final MetadataBlock? featureMeta = _extractMetadataBlock(
      lines,
      'spec-begin',
      'spec-end',
    );
    final featureTags = <GherkinTag>[];
    int? featureLine;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('@')) {
        for (final tag in trimmed.split(RegExp(r'\s+'))) {
          if (tag.startsWith('@')) {
            featureTags.add(
              GherkinTag(
                name: tag.substring(1),
                source: SourceLocation(
                  file: file,
                  line: i + 1,
                  column: lines[i].indexOf('@') + 1,
                ),
              ),
            );
          }
        }
      }
      if (trimmed.startsWith('Feature:')) {
        featureLine = i;
        break;
      }
    }

    if (featureLine == null) return null;

    final featureTitle = lines[featureLine]
        .trim()
        .substring('Feature:'.length)
        .trim();
    final description = <String>[];
    int? ruleStart;

    for (int i = featureLine + 1; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('@') ||
          trimmed.startsWith('Rule:') ||
          trimmed.startsWith('Background:') ||
          trimmed.startsWith('Scenario:') ||
          trimmed.startsWith('Scenario Outline:')) {
        ruleStart = i;
        break;
      }
      if (!trimmed.startsWith('#')) {
        description.add(trimmed);
      }
    }

    final rules = <ParsedRule>[];

    // Find all Rule: positions
    final rulePositions = <int>[];
    for (int i = ruleStart ?? featureLine + 1; i < lines.length; i++) {
      if (lines[i].trim().startsWith('Rule:')) {
        rulePositions.add(i);
      }
    }

    final featureBackgroundPositions = <int>[];
    final featureBodyEnd = rulePositions.isEmpty
        ? lines.length
        : rulePositions.first;
    for (var i = featureLine + 1; i < featureBodyEnd; i++) {
      if (lines[i].trim().startsWith('Background:')) {
        featureBackgroundPositions.add(i);
      }
    }
    if (featureBackgroundPositions.length > 1) {
      throw FormatException(
        'feature "$featureTitle" declares more than one Background',
      );
    }
    final featureBackgroundStart = featureBackgroundPositions.isEmpty
        ? null
        : featureBackgroundPositions.single;

    for (int ri = 0; ri < rulePositions.length; ri++) {
      final rp = rulePositions[ri];
      final nextRp = ri + 1 < rulePositions.length
          ? rulePositions[ri + 1]
          : lines.length;
      final metadataStart = ri == 0
          ? featureLine + 1
          : rulePositions[ri - 1] + 1;
      final ruleBlocks = _ruleMetadataBlocks(
        lines,
        start: metadataStart,
        end: rp,
        file: file,
      );
      if (ruleBlocks.length != 1) {
        throw FormatException(
          'rule metadata before line ${rp + 1} requires exactly one '
          '# rule-spec-begin/# rule-spec-end block; found ${ruleBlocks.length}',
        );
      }
      final ruleMeta = ruleBlocks.single;

      // Extract tags from just before the Rule: line
      final ruleTags = <GherkinTag>[];
      for (int j = rp - 1; j >= 0; j--) {
        final t = lines[j].trim();
        if (t.startsWith('@')) {
          for (final tag in t.split(RegExp(r'\s+'))) {
            if (tag.startsWith('@')) {
              ruleTags.add(
                GherkinTag(
                  name: tag.substring(1),
                  source: SourceLocation(
                    file: file,
                    line: j + 1,
                    column: lines[j].indexOf('@') + 1,
                  ),
                ),
              );
            }
          }
        } else if (t.isEmpty ||
            t.startsWith('#') ||
            t.startsWith('Rule:') ||
            t.startsWith('Scenario:') ||
            t.startsWith('@')) {
          if (t.startsWith('@')) continue;
          // Continue scanning — might be more tags or a rule-spec end
          if (t == '# rule-spec-end') break;
        } else {
          break;
        }
      }
      // Reverse tags to maintain source order
      ruleTags.sort((a, b) => a.source.line.compareTo(b.source.line));

      final ruleSection = lines.sublist(rp, nextRp);
      final rule = _parseRule(
        ruleSection,
        ruleMeta,
        ruleTags,
        file,
        lineOffset: rp,
      );
      if (rule != null) rules.add(rule);
    }

    if (rulePositions.isNotEmpty) {
      final trailing = _ruleMetadataBlocks(
        lines,
        start: rulePositions.last + 1,
        end: lines.length,
        file: file,
      );
      if (trailing.isNotEmpty) {
        throw const FormatException(
          'orphan rule-spec block after the final Rule',
        );
      }
    }

    final featureElement = GherkinElement(
      keyword: GherkinKeyword.feature,
      title: featureTitle,
      source: SourceLocation(
        file: file,
        line: featureLine + 1,
        column: lines[featureLine].indexOf('Feature:') + 1,
      ),
      tags: featureTags,
      description: description.isNotEmpty ? description.join('\n') : null,
    );

    final featureMetadata = featureMeta != null
        ? _metadataFromYaml(
            featureMeta.content,
            featureMeta.source,
            requireSchemaVersion: true,
          )
        : ParsedMetadata(source: SourceLocation(file: file, line: 1));

    return ParsedFeature(
      metadata: featureMetadata,
      tags: featureTags,
      featureElement: featureElement,
      rules: rules,
      backgroundSteps: featureBackgroundStart == null
          ? const []
          : _parseSteps(
              lines.sublist(featureBackgroundStart, featureBodyEnd),
              file,
              lineOffset: featureBackgroundStart,
            ),
    );
  }

  ParsedRule? _parseRule(
    List<String> lines,
    MetadataBlock? ruleMeta,
    List<GherkinTag> tags,
    String file, {
    required int lineOffset,
  }) {
    int ruleLine = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('Rule:')) {
        ruleLine = i;
        break;
      }
    }
    if (ruleLine < 0) return null;
    final source = SourceLocation(
      file: file,
      line: lineOffset + ruleLine + 1,
      column: lines[ruleLine].indexOf('Rule:') + 1,
    );

    final ruleTitle = lines[ruleLine].trim().substring('Rule:'.length).trim();
    final ruleElement = GherkinElement(
      keyword: GherkinKeyword.rule,
      title: ruleTitle,
      source: source,
      tags: tags,
    );

    final scenarios = <GherkinScenario>[];
    List<String>? backgroundLines;
    int? backgroundStart;
    List<String>? scenarioLines;
    int? scenarioStart;
    final pendingScenarioTags = <String>[];

    for (int i = ruleLine + 1; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('@')) {
        if (scenarioLines != null && _tagsApplyToExamples(lines, i)) {
          scenarioLines.add(lines[i]);
        } else {
          pendingScenarioTags.add(lines[i]);
        }
        continue;
      }
      if (trimmed.startsWith('Background:') && scenarioLines == null) {
        backgroundLines = [lines[i]];
        backgroundStart = i;
        continue;
      }
      if (trimmed.startsWith('Scenario:') ||
          trimmed.startsWith('Scenario Outline:')) {
        if (scenarioLines != null) {
          final scenario = _parseScenario(
            scenarioLines,
            file,
            lineOffset: lineOffset + scenarioStart!,
          );
          if (scenario != null) scenarios.add(scenario);
        }
        scenarioLines = [...pendingScenarioTags, lines[i]];
        scenarioStart = i - pendingScenarioTags.length;
        pendingScenarioTags.clear();
      } else if (scenarioLines != null) {
        scenarioLines.add(lines[i]);
      } else if (backgroundLines != null) {
        backgroundLines.add(lines[i]);
      }
    }
    if (scenarioLines != null) {
      final scenario = _parseScenario(
        scenarioLines,
        file,
        lineOffset: lineOffset + scenarioStart!,
      );
      if (scenario != null) scenarios.add(scenario);
    }

    ParsedMetadata metadata;
    if (ruleMeta != null) {
      metadata = _metadataFromYaml(ruleMeta.content, ruleMeta.source);
    } else {
      throw FormatException(
        'rule "$ruleTitle" requires exactly one # rule-spec-begin/# rule-spec-end block',
      );
    }

    return ParsedRule(
      metadata: metadata,
      tags: tags,
      ruleElement: ruleElement,
      scenarios: scenarios,
      backgroundSteps: backgroundLines == null
          ? const []
          : _parseSteps(
              backgroundLines,
              file,
              lineOffset: lineOffset + backgroundStart!,
            ),
    );
  }

  /// Gherkin tags immediately before an Examples block belong to that block,
  /// while tags before a following scenario belong to the following scenario.
  bool _tagsApplyToExamples(List<String> lines, int tagLine) {
    for (var i = tagLine + 1; i < lines.length; i++) {
      final next = lines[i].trim();
      if (next.isEmpty || next.startsWith('#') || next.startsWith('@')) {
        continue;
      }
      return next.startsWith('Examples:');
    }
    return false;
  }

  GherkinScenario? _parseScenario(
    List<String> lines,
    String file, {
    required int lineOffset,
  }) {
    int scenarioLine = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('Scenario:') ||
          lines[i].trim().startsWith('Scenario Outline:')) {
        scenarioLine = i;
        break;
      }
    }
    if (scenarioLine < 0) return null;

    final line = lines[scenarioLine].trim();
    final title = line.substring(line.indexOf(':') + 1).trim();

    final tags = <GherkinTag>[];
    for (int i = 0; i < scenarioLine; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('@')) {
        for (final tag in trimmed.split(RegExp(r'\s+'))) {
          if (tag.startsWith('@')) {
            tags.add(
              GherkinTag(
                name: tag.substring(1),
                source: SourceLocation(
                  file: file,
                  line: lineOffset + i + 1,
                  column: lines[i].indexOf('@') + 1,
                ),
              ),
            );
          }
        }
      }
    }

    final stepLines = lines.sublist(scenarioLine + 1);
    // Split step lines by Examples: blocks — everything between Scenario and
    // first Examples: are steps; each Examples: section has a title and table.
    final examplesList = <GherkinExamples>[];
    final executableLines = <String>[];
    final pendingExampleTags = <GherkinTag>[];
    int inExamples = -1;

    for (int i = 0; i < stepLines.length; i++) {
      final trimmed = stepLines[i].trim();
      if (trimmed.startsWith('@')) {
        for (final tag in trimmed.split(RegExp(r'\s+'))) {
          if (!tag.startsWith('@')) continue;
          pendingExampleTags.add(
            GherkinTag(
              name: tag.substring(1),
              source: SourceLocation(
                file: file,
                line: lineOffset + scenarioLine + i + 2,
                column: stepLines[i].indexOf('@') + 1,
              ),
            ),
          );
        }
        continue;
      }
      if (trimmed.startsWith('Examples:')) {
        // Determine the title from the Examples: line
        final titlePart = trimmed.substring('Examples:'.length).trim();
        final examplesTitle = titlePart.isNotEmpty
            ? titlePart
            : 'examples_${examplesList.length}';
        // Collect the table lines (rows starting with |)
        final tableLines = <String>[];
        int j = i + 1;
        while (j < stepLines.length && stepLines[j].trim().startsWith('|')) {
          tableLines.add(stepLines[j]);
          j++;
        }
        if (tableLines.isNotEmpty) {
          final rows = tableLines.map(_parseTableRow).toList();
          examplesList.add(
            GherkinExamples(
              title: examplesTitle,
              tags: List.unmodifiable(pendingExampleTags),
              headers: rows.first,
              rows: rows.skip(1).toList(),
              source: SourceLocation(
                file: file,
                line: lineOffset + scenarioLine + i + 2,
                column: stepLines[i].indexOf('Examples:') + 1,
              ),
            ),
          );
        }
        pendingExampleTags.clear();
        inExamples = i;
        i = j - 1; // skip past the table rows
        continue;
      }
      if (inExamples < 0) executableLines.add(stepLines[i]);
    }

    final steps = _parseSteps(
      executableLines,
      file,
      lineOffset: lineOffset + scenarioLine + 1,
    );

    final scenarioElement = GherkinElement(
      keyword: line.startsWith('Scenario Outline:')
          ? GherkinKeyword.scenarioOutline
          : GherkinKeyword.scenario,
      title: title,
      source: SourceLocation(
        file: file,
        line: lineOffset + scenarioLine + 1,
        column: lines[scenarioLine].indexOf('Scenario') + 1,
      ),
      tags: tags,
    );

    return GherkinScenario(
      tags: tags,
      scenarioElement: scenarioElement,
      steps: steps,
      examples: examplesList,
    );
  }

  List<GherkinStep> _parseSteps(
    List<String> lines,
    String file, {
    int lineOffset = 0,
  }) {
    final steps = <GherkinStep>[];
    GherkinStep? current;
    var previousKeyword = 'Given';
    String? docDelimiter;
    final doc = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (docDelimiter != null) {
        if (trimmed == docDelimiter) {
          current = GherkinStep(
            keyword: current!.keyword,
            inheritedKeyword: current.inheritedKeyword,
            text: current.text,
            source: current.source,
            docString: doc.toString(),
            table: current.table,
          );
          steps[steps.length - 1] = current;
          docDelimiter = null;
          doc.clear();
        } else {
          doc.writeln(lines[i]);
        }
        continue;
      }
      final match = RegExp(
        r'^(Given|When|Then|And|But)\s+(.+)$',
      ).firstMatch(trimmed);
      if (match != null) {
        final keyword = match.group(1)!;
        final inherited = keyword == 'And' || keyword == 'But'
            ? previousKeyword
            : keyword;
        if (keyword != 'And' && keyword != 'But') previousKeyword = keyword;
        current = GherkinStep(
          keyword: keyword,
          inheritedKeyword: inherited,
          text: match.group(2)!,
          source: SourceLocation(
            file: file,
            line: lineOffset + i + 1,
            column: lines[i].indexOf(keyword) + 1,
          ),
        );
        steps.add(current);
      } else if (trimmed == '"""' || trimmed == "'''") {
        if (current != null) {
          docDelimiter = trimmed;
        }
      } else if (trimmed.startsWith('|') && current != null) {
        current = GherkinStep(
          keyword: current.keyword,
          inheritedKeyword: current.inheritedKeyword,
          text: current.text,
          source: current.source,
          docString: current.docString,
          table: [...current.table, _parseTableRow(trimmed)],
        );
        steps[steps.length - 1] = current;
      }
    }
    return steps;
  }

  List<String> _parseTableRow(String line) {
    final value = line.trim();
    if (!value.startsWith('|')) return const [];
    final end = value.endsWith('|') ? value.length - 1 : value.length;
    final cells = <String>[];
    final current = StringBuffer();
    var escaped = false;
    for (final character in value.substring(1, end).split('')) {
      if (escaped) {
        current.write(character);
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == '|') {
        cells.add(current.toString().trim());
        current.clear();
      } else {
        current.write(character);
      }
    }
    if (escaped) current.write('\\');
    cells.add(current.toString().trim());
    return cells;
  }

  MetadataBlock? _extractMetadataBlock(
    List<String> lines,
    String beginMarker,
    String endMarker,
  ) {
    bool inBlock = false;
    int startLine = 0;
    final content = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();
      if (trimmed == '# $beginMarker') {
        inBlock = true;
        startLine = i + 1;
        content.clear();
      } else if (inBlock && trimmed == '# $endMarker') {
        if (content.isNotEmpty) {
          return MetadataBlock(
            content: content.toString(),
            source: SourceLocation(file: _lastFile!, line: startLine),
          );
        }
        inBlock = false;
      } else if (inBlock && raw.trimLeft().startsWith('#')) {
        var lineContent = raw.substring(raw.indexOf('#') + 1);
        if (lineContent.startsWith(' ')) {
          lineContent = lineContent.substring(1);
        }
        content.writeln(lineContent);
      }
    }
    return null;
  }

  ParsedMetadata _metadataFromYaml(
    String yamlText,
    SourceLocation source, {
    bool requireSchemaVersion = false,
  }) {
    final metadata = _parseSimpleYaml(yamlText, source);
    final errors = <String>[];
    var extensions = metadata.extensions;
    try {
      final value = loadYaml(yamlText);
      if (value is! Map) {
        errors.add('metadata must be a mapping');
      } else {
        const allowed = {
          'schemaVersion',
          'id',
          'epic',
          'owner',
          'status',
          'targets',
          'pbis',
          'bindings',
          'endpoints',
          'events',
          'featureFlags',
          'performance',
          'requires',
          'requiredEvidence',
          'securityProfile',
          'required',
          'method',
          'contract',
          'usage',
          'kind',
          'cardinality',
          'acceptableAssurance',
          'threshold',
          'percentile',
          'profile',
          'variant',
          'slot',
          'interaction',
          'defaultEvidence',
          'acceptableProviderKinds',
          'prohibitedProviderTargets',
          'coverageSemantics',
          'defenseInDepth',
          'requiredLayers',
          'description',
        };
        _validateMapKeys(value, allowed, '', errors);
        _validateSecrets(value, '', errors);
        extensions = _extensionsFromYaml(value);
      }
    } catch (e) {
      errors.add('invalid metadata YAML: $e');
    }
    if (metadata.id == null || metadata.id!.trim().isEmpty) {
      errors.add('metadata requires a non-empty id');
    }
    if (requireSchemaVersion && metadata.schemaVersion != '1') {
      errors.add(
        'feature metadata requires schemaVersion 1; found '
        '"${metadata.schemaVersion ?? 'missing'}"',
      );
    }
    return ParsedMetadata(
      schemaVersion: metadata.schemaVersion,
      id: metadata.id,
      epic: metadata.epic,
      owner: metadata.owner,
      status: metadata.status,
      targets: metadata.targets,
      pbis: metadata.pbis,
      bindings: metadata.bindings,
      endpoints: metadata.endpoints,
      events: metadata.events,
      featureFlags: metadata.featureFlags,
      performance: metadata.performance,
      requires: metadata.requires,
      requiredEvidence: metadata.requiredEvidence,
      evidenceRequirements: _yamlEvidenceRequirements(
        (loadYaml(yamlText) as Map?)?['requiredEvidence'],
      ),
      securityProfile: metadata.securityProfile,
      extensions: extensions,
      source: source,
      errors: errors,
    );
  }

  List<Map<String, String>> _yamlEvidenceRequirements(Object? value) {
    if (value is! Iterable || value is String) return const [];
    final result = <Map<String, String>>[];
    for (final item in value) {
      if (item is! Map) continue;
      final row = <String, String>{};
      for (final entry in item.entries) {
        if (entry.key is String && entry.value is String) {
          row[entry.key as String] = entry.value as String;
        }
      }
      if (row.isNotEmpty) result.add(Map.unmodifiable(row));
    }
    return List.unmodifiable(result);
  }

  Map<String, Object?> _extensionsFromYaml(Map value) {
    Object? convert(Object? input) {
      if (input is Map) {
        final keys = input.keys.map((key) => key.toString()).toList()..sort();
        return {for (final key in keys) key: convert(input[key])};
      }
      if (input is Iterable) return input.map(convert).toList(growable: false);
      if (input is String || input is num || input is bool || input == null) {
        return input;
      }
      return input.toString();
    }

    final keys =
        value.keys
            .map((key) => key.toString())
            .where((key) => key.startsWith('x-'))
            .toList()
          ..sort();
    return Map.unmodifiable({for (final key in keys) key: convert(value[key])});
  }

  /// Recursively validate YAML map keys: allow known keys and x-* prefixed keys.
  void _validateMapKeys(
    Map map,
    Set<String> allowed,
    String prefix,
    List<String> errors,
  ) {
    for (final key in map.keys) {
      final keyText = key.toString();
      final fullKey = prefix.isEmpty ? keyText : '$prefix.$keyText';
      if (!allowed.contains(keyText) &&
          !keyText.startsWith('x-') &&
          !prefix.startsWith('x-')) {
        errors.add('unknown metadata field "$fullKey"');
      }
      final value = map[key];
      if (value is Map) {
        _validateMapKeys(value, allowed, fullKey, errors);
      }
    }
  }

  List<MetadataBlock> _ruleMetadataBlocks(
    List<String> lines, {
    required int start,
    required int end,
    required String file,
  }) {
    final blocks = <MetadataBlock>[];
    StringBuffer? content;
    int? beginLine;
    for (var index = start; index < end; index++) {
      final raw = lines[index];
      final trimmed = raw.trim();
      if (trimmed == '# rule-spec-begin') {
        if (content != null) {
          throw FormatException('nested rule-spec block at line ${index + 1}');
        }
        content = StringBuffer();
        beginLine = index + 1;
      } else if (trimmed == '# rule-spec-end') {
        if (content == null || beginLine == null) {
          throw FormatException('orphan rule-spec end at line ${index + 1}');
        }
        blocks.add(
          MetadataBlock(
            content: content.toString(),
            source: SourceLocation(file: file, line: beginLine),
          ),
        );
        content = null;
        beginLine = null;
      } else if (content != null) {
        if (!raw.trimLeft().startsWith('#')) {
          throw FormatException(
            'non-comment rule metadata at line ${index + 1}',
          );
        }
        var lineContent = raw.substring(raw.indexOf('#') + 1);
        if (lineContent.startsWith(' ')) lineContent = lineContent.substring(1);
        content.writeln(lineContent);
      }
    }
    if (content != null) {
      throw FormatException('unterminated rule-spec block at line $beginLine');
    }
    return blocks;
  }

  void _validateSecrets(Map value, String prefix, List<String> errors) {
    final privateKey = RegExp(
      r'-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----',
      caseSensitive: false,
    );
    final credentialKey = RegExp(
      r'(?:password|secret|token|api[_-]?key|private[_-]?key)',
      caseSensitive: false,
    );
    final cloudKey = RegExp(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b');

    for (final entry in value.entries) {
      final key = entry.key.toString();
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final item = entry.value;
      if (item is Map) {
        _validateSecrets(item, path, errors);
      } else if (item is Iterable && item is! String) {
        for (final child in item) {
          if (child is Map) {
            _validateSecrets(child, path, errors);
          } else if (child is String &&
              (privateKey.hasMatch(child) || cloudKey.hasMatch(child))) {
            errors.add('metadata may contain a secret at "$path"');
          }
        }
      } else if (item is String &&
          (credentialKey.hasMatch(key) ||
              privateKey.hasMatch(item) ||
              cloudKey.hasMatch(item))) {
        errors.add('metadata may contain a secret at "$path"');
      }
    }
  }

  ParsedMetadata _parseSimpleYaml(String yamlText, SourceLocation source) {
    final parsed = loadYaml(yamlText);
    if (parsed is! YamlMap) {
      throw const FormatException('metadata must be a YAML mapping');
    }
    final root = _yamlMap(parsed);
    final bindingsRoot = _yamlMap(root['bindings']);

    return ParsedMetadata(
      schemaVersion: _yamlText(root['schemaVersion']),
      id: _yamlText(root['id']),
      epic: _yamlText(root['epic']),
      owner: _yamlText(root['owner']),
      status: _yamlText(root['status']),
      targets: _yamlTextList(root['targets']),
      pbis: _yamlTextList(root['pbis']),
      bindings: _yamlMapList(bindingsRoot['required'])
          .map(
            (value) => ParsedBinding(
              id: _yamlRequiredText(value, 'bindings.required[].id'),
              target: _yamlText(value['target']) ?? 'flutter',
              cardinality: canonicalBindingCardinality(
                _yamlText(value['cardinality']) ?? 'exactlyOne',
              ),
              instanceCardinality: canonicalBindingInstanceCardinality(
                _yamlText(value['instanceCardinality']) ?? 'exactlyOne',
              ),
              variant: _yamlText(value['variant']) ?? 'default',
              slot: _yamlText(value['slot']) ?? 'primary',
              interaction: _yamlText(value['interaction']),
            ),
          )
          .toList(growable: false),
      endpoints: _yamlMapList(root['endpoints'])
          .map(
            (value) => ParsedEndpoint(
              id: _yamlRequiredText(value, 'endpoints[].id'),
              target: _yamlText(value['target']) ?? 'backend',
              method: _yamlText(value['method']),
              contract: _yamlText(value['contract']),
              usage: _yamlText(value['usage']),
            ),
          )
          .toList(growable: false),
      events: _yamlTextList(root['events']),
      featureFlags: _yamlTextList(root['featureFlags']),
      performance: _yamlMapList(root['performance'])
          .map(
            (value) => ParsedPerformance(
              id: _yamlRequiredText(value, 'performance[].id'),
              target: _yamlText(value['target']) ?? 'backend',
              threshold: _yamlText(value['threshold']) ?? '0ms',
              percentile: _yamlInt(value['percentile']) ?? 0,
              profile: _yamlText(value['profile']) ?? '',
            ),
          )
          .toList(growable: false),
      requires: _yamlMapList(root['requires'])
          .map(
            (value) => ParsedControlRef(
              kind: _yamlText(value['kind']) ?? 'control',
              id: _yamlRequiredText(value, 'requires[].id'),
              target: _yamlText(value['target']) ?? 'backend',
              cardinality: _yamlText(value['cardinality']) ?? 'oneOrMore',
              acceptableAssurance: _yamlTextList(value['acceptableAssurance']),
              variant: _yamlText(value['variant']) ?? 'default',
              slot: _yamlText(value['slot']) ?? 'primary',
            ),
          )
          .toList(growable: false),
      requiredEvidence: _yamlEvidenceTypes(root['requiredEvidence']),
      evidenceRequirements: _yamlEvidenceRequirements(root['requiredEvidence']),
      securityProfile: _yamlText(root['securityProfile']),
      extensions: Map.unmodifiable(_extensionsFromYaml(root)),
      source: source,
    );
  }

  Map<String, Object?> _yamlMap(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in value.entries) entry.key.toString(): entry.value,
    });
  }

  List<Map<String, Object?>> _yamlMapList(Object? value) {
    if (value is! Iterable || value is String) return const [];
    return value
        .map((item) {
          if (item is! Map) {
            throw FormatException(
              'expected a YAML mapping in a list, found $item',
            );
          }
          return _yamlMap(item);
        })
        .toList(growable: false);
  }

  List<String>? _yamlEvidenceTypes(Object? value) {
    if (value == null) return null;
    if (value is Iterable && value.any((item) => item is Map)) {
      return value
          .whereType<Map>()
          .map((item) => item['type'] ?? item['evidenceType'])
          .whereType<String>()
          .toList(growable: false);
    }
    return _yamlTextList(value);
  }

  List<String>? _yamlTextList(Object? value) {
    if (value == null) return null;
    if (value is! Iterable || value is String) {
      throw FormatException('expected a YAML list, found $value');
    }
    return value
        .map((item) => _yamlRequiredTextValue(item))
        .toList(growable: false);
  }

  String _yamlRequiredText(Map<String, Object?> value, String field) {
    final key = field.substring(field.lastIndexOf('.') + 1);
    final result = _yamlText(value[key]);
    if (result == null || result.isEmpty) {
      throw FormatException(
        'missing required metadata field "$field"; available keys: '
        '${value.keys.join(', ')}',
      );
    }
    return result;
  }

  String _yamlRequiredTextValue(Object? value) {
    final result = _yamlText(value);
    if (result == null) {
      throw const FormatException('list item must be a scalar');
    }
    return result;
  }

  String? _yamlText(Object? value) {
    if (value == null) return null;
    if (value is Map || (value is Iterable && value is! String)) {
      throw FormatException('expected a YAML scalar, found $value');
    }
    return value.toString();
  }

  int? _yamlInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(_yamlText(value) ?? '');
  }
}

/// A raw metadata block and its source location.
class MetadataBlock {
  /// YAML content inside the block.
  final String content;

  /// Location of the block in the source file.
  final SourceLocation source;

  /// Creates a metadata block.
  const MetadataBlock({required this.content, required this.source});
}
