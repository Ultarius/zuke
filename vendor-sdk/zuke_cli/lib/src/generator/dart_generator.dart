import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dart_style/dart_style.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'manifest.dart';

class GeneratedFile {
  final String path;
  final String content;
  final String hash;

  const GeneratedFile({
    required this.path,
    required this.content,
    required this.hash,
  });
}

class GenerationResult {
  final List<GeneratedFile> files;
  final Manifest manifest;
  final List<String> errors;

  const GenerationResult({
    required this.files,
    required this.manifest,
    this.errors = const [],
  });
}

// Reserved Dart words that can't be used as identifiers
const _reservedWords = {
  'abstract',
  'else',
  'import',
  'show',
  'as',
  'enum',
  'in',
  'static',
  'assert',
  'export',
  'interface',
  'super',
  'async',
  'extends',
  'is',
  'switch',
  'await',
  'extension',
  'late',
  'sync',
  'break',
  'external',
  'library',
  'this',
  'case',
  'factory',
  'mixin',
  'throw',
  'catch',
  'false',
  'new',
  'true',
  'class',
  'final',
  'null',
  'try',
  'const',
  'finally',
  'on',
  'typedef',
  'continue',
  'for',
  'operator',
  'var',
  'covariant',
  'Function',
  'part',
  'void',
  'default',
  'get',
  'required',
  'while',
  'deferred',
  'hide',
  'rethrow',
  'with',
  'do',
  'if',
  'return',
  'yield',
  'dynamic',
  'implements',
  'set',
};

class DartContractGenerator {
  GenerationResult generate({
    required WorkspaceDiscoveryResult workspace,
    String outputDir = 'lib/src/generated',
    String? exportPath,
  }) {
    final files = <GeneratedFile>[];
    final manifestEntries = <ManifestEntry>[];
    final errors = <String>[];
    final reservedScenarioIds = <String, _ScenarioLocation>{};
    final reservedFeatureTypes = <String>{};

    for (final feature in workspace.data.features) {
      final featId = feature.metadata.id;
      if (featId == null) continue;

      final pascalName = _idToPascal(featId);
      if (!reservedFeatureTypes.add('${pascalName}Scenario')) {
        errors.add(
          '$featId has colliding generated feature enum $pascalName Scenario',
        );
      }
      final snakeName = featId.toLowerCase().replaceAll('-', '_');
      final fileName = '${snakeName}_contracts.g.dart';
      final filePath = '$outputDir/$fileName';

      final bindings = feature.metadata.bindings ?? [];
      final bindingMembers = <String>{};
      final bindingTypes = <String>{};
      for (final binding in bindings) {
        final member = _bindingIdToMember(binding.id);
        final type = _bindingIdToType(pascalName, binding.id);
        if (!bindingMembers.add(member)) {
          errors.add('$featId has colliding Flutter binding member "$member"');
        }
        if (!bindingTypes.add(type)) {
          errors.add('$featId has colliding Flutter binding subtype "$type"');
        }
      }
      final isFlutterFeature = (feature.metadata.targets ?? const []).contains(
        'flutter',
      );
      if (isFlutterFeature) {
        for (final binding in bindings) {
          if (!const {
            'input',
            'action',
            'output',
          }.contains(binding.interaction)) {
            errors.add(
              '$featId binding ${binding.id} must declare interaction: input, action, or output',
            );
          }
        }
      }
      final rules = feature.rules.where((r) => r.metadata.id != null).toList();

      final scenarioContracts = <String, List<_GeneratedScenario>>{};
      for (final rule in rules) {
        final scenarios = <_GeneratedScenario>[];
        final seenIds = <String>{};
        for (final scenario in rule.scenarios) {
          final tags = <GherkinTag>[
            ...scenario.tags,
            for (final examples in scenario.examples) ...examples.tags,
          ];
          for (final tag in tags) {
            if (tag.name.toUpperCase().startsWith('SCN-') &&
                !_isCanonicalScenarioId(tag.name)) {
              errors.add(
                '$featId: tag "${tag.name}" looks like a scenario ID but is not canonical',
              );
              continue;
            }
            if (!tag.name.startsWith('SCN-') || !seenIds.add(tag.name)) {
              continue;
            }
            final location = _ScenarioLocation(
              featureId: featId,
              ruleId: rule.metadata.id!,
              source: scenario.scenarioElement.source.file,
            );
            final previous = reservedScenarioIds[tag.name];
            if (previous != null) {
              errors.add(
                'Scenario ID ${tag.name} is declared by ${previous.featureId}/${previous.ruleId} '
                '(${previous.source}) and $featId/${rule.metadata.id} (${location.source})',
              );
            } else {
              reservedScenarioIds[tag.name] = location;
            }
            scenarios.add(
              _GeneratedScenario(
                id: tag.name,
                title: scenario.scenarioElement.title,
                controlIds: _effectiveControlIds(workspace, rule),
              ),
            );
          }
        }
        if (scenarios.isNotEmpty) {
          scenarioContracts[rule.metadata.id!] = scenarios;
        }
      }

      final buffer = StringBuffer();
      buffer.writeln('// GENERATED. DO NOT EDIT.');
      final sourcePath = _normalizedSourcePath(
        workspace,
        feature.metadata.source.file,
      );
      buffer.writeln('// Source: $featId ($sourcePath)');
      buffer.writeln();
      if (scenarioContracts.isNotEmpty || bindings.isNotEmpty) {
        buffer.writeln(
          "import 'package:zuke_annotations/zuke_annotations.dart';",
        );
        buffer.writeln();
      }

      // Binding interfaces are consumed by Flutter and pure-Dart targets.
      // The identity type stays generic so Flutter can use Key without making
      // shared generated-contract packages depend on Flutter.
      if (bindings.isNotEmpty) {
        final bindingBase = '${pascalName}FlutterBinding';
        buffer.writeln(
          'sealed class $bindingBase implements ZukeBindingDescriptor {',
        );
        buffer.writeln('  const $bindingBase(this.id);');
        buffer.writeln('  @override');
        buffer.writeln('  final String id;');
        buffer.writeln();
        buffer.writeln(
          '  T keyIn<T extends Object>(${pascalName}FlutterBindings<T> bindings);',
        );
        buffer.writeln();
        for (final binding in bindings) {
          final member = _bindingIdToMember(binding.id);
          final type = _bindingIdToType(pascalName, binding.id);
          buffer.writeln('  static const $member = $type();');
        }
        buffer.writeln();
        buffer.writeln(
          '  static $bindingBase fromId(String bindingId) => switch (bindingId) {',
        );
        for (final binding in bindings) {
          final member = _bindingIdToMember(binding.id);
          buffer.writeln('    ${_dartStringLiteral(binding.id)} => $member,');
        }
        buffer.writeln(
          "    _ => throw ArgumentError.value(bindingId, 'bindingId', "
          "${_dartStringLiteral('Unknown Flutter binding for $featId')}),",
        );
        buffer.writeln('  };');
        buffer.writeln('}');
        buffer.writeln();
        for (final binding in bindings) {
          final type = _bindingIdToType(pascalName, binding.id);
          final member = _bindingIdToMember(binding.id);
          buffer.writeln('final class $type extends $bindingBase {');
          buffer.writeln(
            '  const $type() : super(${_dartStringLiteral(binding.id)});',
          );
          buffer.writeln();
          buffer.writeln('  @override');
          buffer.writeln(
            '  T keyIn<T extends Object>(${pascalName}FlutterBindings<T> bindings) => bindings.$member;',
          );
          buffer.writeln();
          buffer.writeln('  @override');
          buffer.writeln(
            '  BindingInstanceCardinality get instanceCardinality => '
            'BindingInstanceCardinality.${_bindingInstanceCardinalityMember(binding.instanceCardinality)};',
          );
          buffer.writeln('}');
          buffer.writeln();
        }
        buffer.writeln(
          'abstract interface class ${pascalName}FlutterBindings<T extends Object> {',
        );
        for (final binding in bindings) {
          final member = _bindingIdToMember(binding.id);
          buffer.writeln('  T get $member;');
        }
        buffer.writeln('}');
        buffer.writeln();

        buffer.writeln(
          'mixin ${pascalName}BindingDrivenFlutterDriver<W, T extends Object> '
          'implements ${pascalName}FlutterDriver<W> {',
        );
        buffer.writeln(
          '  ${pascalName}FlutterBindings<T> bindingsFor(W world);',
        );
        buffer.writeln(
          '  Future<void> zukeEnterBinding(W world, T key, String value);',
        );
        buffer.writeln('  Future<void> zukeTapBinding(W world, T key);');
        buffer.writeln('  Future<String?> zukeReadBinding(W world, T key);');
        buffer.writeln(
          '  Future<void> zukeEnterBindingInstance(W world, T key, Object instanceId, String value);',
        );
        buffer.writeln(
          '  Future<void> zukeTapBindingInstance(W world, T key, Object instanceId);',
        );
        buffer.writeln(
          '  Future<String?> zukeReadBindingInstance(W world, T key, Object instanceId);',
        );
        buffer.writeln(
          '  Future<List<String>> zukeReadAllBindings(W world, T key);',
        );
        for (final binding in bindings) {
          final method = _bindingIdToDriverMethod(
            binding.id,
            binding.interaction,
          );
          final member = _bindingIdToMember(binding.id);
          final repeated = _bindingAllowsMany(binding.instanceCardinality);
          switch (binding.interaction) {
            case 'input':
              buffer.writeln('  @override');
              buffer.writeln(
                repeated
                    ? '  Future<void> $method(W world, Object instanceId, String value) => zukeEnterBindingInstance(world, bindingsFor(world).$member, instanceId, value);'
                    : '  Future<void> $method(W world, String value) => zukeEnterBinding(world, bindingsFor(world).$member, value);',
              );
            case 'action':
              buffer.writeln('  @override');
              buffer.writeln(
                repeated
                    ? '  Future<void> $method(W world, Object instanceId) => zukeTapBindingInstance(world, bindingsFor(world).$member, instanceId);'
                    : '  Future<void> $method(W world) => zukeTapBinding(world, bindingsFor(world).$member);',
              );
            case 'output':
              buffer.writeln('  @override');
              buffer.writeln(
                repeated
                    ? '  Future<String?> $method(W world, Object instanceId) => zukeReadBindingInstance(world, bindingsFor(world).$member, instanceId);'
                    : '  Future<String?> $method(W world) => zukeReadBinding(world, bindingsFor(world).$member);',
              );
              if (repeated) {
                buffer.writeln('  @override');
                buffer.writeln(
                  '  Future<List<String>> ${_readAllDriverMethod(method)}(W world) => zukeReadAllBindings(world, bindingsFor(world).$member);',
                );
              }
          }
        }
        buffer.writeln('}');
        buffer.writeln();
      }

      if (bindings.isNotEmpty) {
        // A driver is generated from the declared interaction semantics rather
        // than from a product-specific list of calculator controls.
        buffer.writeln(
          'abstract interface class ${pascalName}FlutterDriver<W> {',
        );
        for (final binding in bindings) {
          final method = _bindingIdToDriverMethod(
            binding.id,
            binding.interaction,
          );
          switch (binding.interaction) {
            case 'input':
              buffer.writeln(
                _bindingAllowsMany(binding.instanceCardinality)
                    ? '  Future<void> $method(W world, Object instanceId, String value);'
                    : '  Future<void> $method(W world, String value);',
              );
            case 'action':
              buffer.writeln(
                _bindingAllowsMany(binding.instanceCardinality)
                    ? '  Future<void> $method(W world, Object instanceId);'
                    : '  Future<void> $method(W world);',
              );
            case 'output':
              buffer.writeln(
                _bindingAllowsMany(binding.instanceCardinality)
                    ? '  Future<String?> $method(W world, Object instanceId);\n  Future<List<String>> ${_readAllDriverMethod(method)}(W world);'
                    : '  Future<String?> $method(W world);',
              );
          }
        }
        buffer.writeln('}');
        buffer.writeln();
      }

      // RequirementIds — only Rule IDs
      buffer.writeln('abstract final class ${pascalName}RequirementIds {');
      final requirementMembers = <String>{};
      for (final rule in rules) {
        final constName = _ruleIdToConst(rule.metadata.id!);
        if (!requirementMembers.add(constName)) {
          errors.add('$featId has colliding requirement member "$constName"');
          continue;
        }
        buffer.writeln(
          '  static const $constName = ${_dartStringLiteral(rule.metadata.id!)};',
        );
      }
      buffer.writeln('}');

      // Canonical feature enum and aggregate catalog; aliases would provide a
      // second, drift-prone naming surface and are intentionally not emitted.
      final featureScenarioType = '${pascalName}Scenario';
      final allScenarios = <_GeneratedScenario>[];
      for (final rule in rules) {
        allScenarios.addAll(scenarioContracts[rule.metadata.id!] ?? const []);
      }
      final enumMembers = <String>{};
      if (allScenarios.isNotEmpty) {
        buffer.writeln();
        buffer.writeln(
          'enum $featureScenarioType implements ZukeScenarioContract {',
        );
        for (final scenario in allScenarios) {
          final member = _scnIdToConst(scenario.id);
          if (!enumMembers.add(member)) {
            errors.add('$featId has colliding enum member "$member"');
            continue;
          }
          buffer.writeln(
            '  $member(ScenarioId(${_dartStringLiteral(scenario.id)}), '
            '${_dartStringLiteral(_ruleForScenario(rules, scenario.id, scenarioContracts))}, '
            '${_dartStringLiteral(scenario.title)}, '
            '${_controlSetLiteral(scenario.controlIds)}),',
          );
        }
        buffer.writeln(';');
        buffer.writeln(
          '  const $featureScenarioType(this.id, this.requirementId, this.title, this.controlIds);',
        );
        buffer.writeln('  @override final ScenarioId id;');
        buffer.writeln('  @override final String requirementId;');
        buffer.writeln('  @override final String title;');
        buffer.writeln('  @override final Set<String> controlIds;');
        buffer.writeln('}');
        buffer.writeln();
        buffer.writeln('abstract final class ${pascalName}Scenarios {');
        buffer.writeln('  static const all = $featureScenarioType.values;');
        buffer.writeln(
          '  static final Map<ScenarioId, $featureScenarioType> byId = Map.unmodifiable(<ScenarioId, $featureScenarioType>{',
        );
        for (final scenario in allScenarios) {
          final member = _scnIdToConst(scenario.id);
          buffer.writeln(
            '    ScenarioId(${_dartStringLiteral(scenario.id)}): $featureScenarioType.$member,',
          );
        }
        buffer.writeln('  });');
        buffer.writeln(
          '  static final Map<String, List<$featureScenarioType>> byRule = Map.unmodifiable(<String, List<$featureScenarioType>>{',
        );
        for (final rule in rules) {
          final scenarios = scenarioContracts[rule.metadata.id!] ?? const [];
          if (scenarios.isEmpty) continue;
          buffer.writeln(
            '    ${_dartStringLiteral(rule.metadata.id!)}: List.unmodifiable(<${featureScenarioType}>[',
          );
          for (final scenario in scenarios) {
            buffer.writeln(
              '      $featureScenarioType.${_scnIdToConst(scenario.id)},',
            );
          }
          buffer.writeln('    ]),');
        }
        buffer.writeln('  });');
        buffer.writeln(
          '  static List<$featureScenarioType> matching(ZukeScenarioPattern pattern) =>',
        );
        buffer.writeln(
          '      all.where(pattern.matches).toList(growable: false);',
        );
        buffer.writeln('}');
      }

      final scenarioClassNames = <String>{};
      for (final rule in rules) {
        final scenarios = scenarioContracts[rule.metadata.id!];
        if (scenarios == null) continue;
        final ruleConstName = _ruleIdToConst(rule.metadata.id!);
        final scenarioClassName =
            '${_toUpperCamelIdentifier(ruleConstName)}Scenarios';
        if (!scenarioClassNames.add(scenarioClassName)) {
          errors.add(
            '$featId has colliding scenario class "$scenarioClassName"',
          );
          continue;
        }
        buffer.writeln();
        buffer.writeln('abstract final class $scenarioClassName {');
        final scenarioMembers = <String>{};
        for (final scenario in scenarios) {
          final alias = _legacyScnIdToConst(scenario.id);
          if (!scenarioMembers.add(alias)) {
            errors.add(
              '$featId has colliding scenario member "$alias" in '
              '$scenarioClassName',
            );
            continue;
          }
          buffer.writeln(
            '  static const $alias = $featureScenarioType.${_scnIdToConst(scenario.id)};',
          );
        }
        buffer.writeln('  static const all = <ZukeScenarioContract>[');
        for (final scenario in scenarios) {
          buffer.writeln(
            '    $featureScenarioType.${_scnIdToConst(scenario.id)},',
          );
        }
        buffer.writeln('  ];');
        buffer.writeln('}');
      }

      late final String content;
      try {
        content = _formatDart(buffer.toString());
      } on FormatterException catch (error) {
        errors.add('$featId generated invalid Dart: $error');
        continue;
      }
      final hash = sha256.convert(utf8.encode(content)).toString();

      files.add(GeneratedFile(path: filePath, content: content, hash: hash));
      manifestEntries.add(ManifestEntry(path: filePath, contentHash: hash));

      final generatedStepPaths = <String>{};
      for (final supportTarget in _generatedStepTargets(workspace)) {
        if (!(feature.metadata.targets ?? const <String>[]).contains(
          supportTarget.target,
        )) {
          continue;
        }
        final supportPath = '${supportTarget.root}/${snakeName}_steps.g.dart';
        if (!generatedStepPaths.add(supportPath)) {
          errors.add(
            '$featId has multiple generated step targets writing $supportPath',
          );
          continue;
        }
        final support = _generateStepSupport(
          feature,
          pascalName,
          supportTarget.target,
          errors,
        );
        if (support == null) continue;
        final supportHash = sha256.convert(utf8.encode(support)).toString();
        files.add(
          GeneratedFile(path: supportPath, content: support, hash: supportHash),
        );
        manifestEntries.add(
          ManifestEntry(path: supportPath, contentHash: supportHash),
        );
      }
    }

    // Export file
    if (files.isNotEmpty && exportPath != null) {
      final exportContent = StringBuffer();
      for (final file in files) {
        final lastPart = file.path.split('/').last;
        exportContent.writeln("export 'src/generated/$lastPart';");
      }
      late final String content;
      try {
        content = _formatDart(exportContent.toString());
      } on FormatterException catch (error) {
        errors.add('Generated export is invalid Dart: $error');
        return GenerationResult(
          files: files,
          manifest: Manifest(entries: manifestEntries),
          errors: errors,
        );
      }
      final hash = sha256.convert(utf8.encode(content)).toString();
      files.add(GeneratedFile(path: exportPath, content: content, hash: hash));
      manifestEntries.add(ManifestEntry(path: exportPath, contentHash: hash));
    }

    return GenerationResult(
      files: files,
      manifest: Manifest(entries: manifestEntries),
      errors: errors,
    );
  }

  // Converts FEAT-CALC-001 → FeatCalc001
  List<_GeneratedStepTarget> _generatedStepTargets(
    WorkspaceDiscoveryResult workspace,
  ) {
    final runners = workspace.config.executionConfig['runners'];
    if (runners is! List) return const <_GeneratedStepTarget>[];
    final targets = <String, _GeneratedStepTarget>{};
    for (final runner in runners) {
      if (runner is! Map) continue;
      final target = runner['target'];
      final output = runner['generatedStepsOutput'];
      if (target is! String ||
          target.isEmpty ||
          output is! String ||
          output.isEmpty) {
        continue;
      }
      final root = output.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
      targets['$target\u0000$root'] = _GeneratedStepTarget(root, target);
    }
    return targets.values.toList()..sort((left, right) {
      final root = left.root.compareTo(right.root);
      return root != 0 ? root : left.target.compareTo(right.target);
    });
  }

  String? _generateStepSupport(
    ParsedFeature feature,
    String featureType,
    String target,
    List<String> errors,
  ) {
    final expressions = <String>{};
    for (final step in feature.backgroundSteps) {
      if (!_isVendorStep(step.text)) {
        expressions.add(_snippetExpression(step.text));
      }
    }
    for (final rule in feature.rules) {
      for (final step in [
        ...rule.backgroundSteps,
        for (final scenario in rule.scenarios) ...scenario.steps,
      ]) {
        if (!_isVendorStep(step.text))
          expressions.add(_snippetExpression(step.text));
      }
    }
    final items = expressions.map(_GeneratedStep.new).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final names = <String>{};
    for (final item in items) {
      if (!names.add(item.name)) {
        errors.add(
          '${feature.metadata.id} has colliding generated step name ${item.name}',
        );
        return null;
      }
    }
    final out = StringBuffer()
      ..writeln('// GENERATED. DO NOT EDIT.')
      ..writeln('// Source: ${feature.metadata.id}')
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln(
        "import '${target == 'flutter' ? 'package:zuke_runner_flutter/zuke_runner_flutter.dart' : 'package:zuke/zuke.dart'}';",
      )
      ..writeln()
      ..writeln(
        'final class ${featureType}GeneratedSteps<W extends ScenarioWorld> {',
      )
      ..writeln('  const ${featureType}GeneratedSteps();')
      ..writeln()
      ..writeln('  List<StepDefinition<W>> build({');
    for (final item in items) {
      out.writeln('    required ${item.callbackType('W')} ${item.name},');
    }
    out
      ..writeln('  }) {')
      ..writeln('    final parameters = StepParameterTypeRegistry.standard();')
      ..writeln('    return [');
    for (final item in items) {
      out
        ..writeln('      StepDefinition<W>.cucumber(')
        ..writeln(
          "        expression: CucumberExpression(${_dartStringLiteral(item.expression)}, parameters),",
        )
        ..writeln('        tier: StepTier.generated,')
        ..writeln('        target: ${_dartStringLiteral(target)},')
        ..writeln('        action: (world, step, values) => ${item.invoke()},')
        ..writeln('      ),');
    }
    out
      ..writeln('    ];')
      ..writeln('  }')
      ..writeln('}');
    return _formatDart(out.toString());
  }

  bool _isVendorStep(String text) =>
      text.startsWith('the user taps ') ||
      text.startsWith('the user enters ') ||
      text.startsWith('element ');

  String _snippetExpression(String text) => text.replaceAllMapped(
    RegExp(r'''(["'])(?:\\.|(?!\1).)*\1'''),
    (_) => '{string}',
  );

  String _idToPascal(String id) {
    return id.split('-').map((p) => _toPascal(p)).join();
  }

  Set<String> _effectiveControlIds(
    WorkspaceDiscoveryResult workspace,
    ParsedRule rule,
  ) {
    final result = <String>{
      for (final control
          in rule.metadata.requires ?? const <ParsedControlRef>[])
        if (control.kind == 'control') control.id,
    };
    final profile = rule.metadata.securityProfile;
    if (profile != null) {
      for (final policy in workspace.data.policies.values) {
        final profiles = policy['securityProfiles'];
        final definition = profiles is Map ? profiles[profile] : null;
        final requires = definition is Map ? definition['requires'] : null;
        if (requires is! List) continue;
        for (final control in requires.whereType<Map>()) {
          if (control['kind']?.toString() == 'control' &&
              control['id']?.toString().isNotEmpty == true) {
            result.add(control['id']!.toString());
          }
        }
      }
    }
    return result;
  }

  String _controlSetLiteral(Set<String> controls) {
    final sorted = controls.toList()..sort();
    return '<String>{${sorted.map(_dartStringLiteral).join(', ')}}';
  }

  String _ruleForScenario(
    List<ParsedRule> rules,
    String scenarioId,
    Map<String, List<_GeneratedScenario>> scenarioContracts,
  ) => rules
      .firstWhere(
        (rule) => (scenarioContracts[rule.metadata.id!] ?? const []).any(
          (scenario) => scenario.id == scenarioId,
        ),
      )
      .metadata
      .id!;

  // Converts a word to PascalCase: 'firstOperand' → 'FirstOperand', 'CALC' → 'Calc'
  String _toPascal(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  String _toUpperCamelIdentifier(String identifier) {
    if (identifier.isEmpty) return identifier;
    return identifier[0].toUpperCase() + identifier.substring(1);
  }

  String _dartStringLiteral(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    return "'$escaped'";
  }

  // Converts to camelCase: 'ADDITION' → 'addition', 'DIVIDE_ZERO' → 'divideZero'
  String _toCamel(String s) {
    if (s.isEmpty) return s;
    final parts = s.split('_');
    if (parts.length == 1) {
      return s.toLowerCase();
    }
    final buffer = StringBuffer(parts[0].toLowerCase());
    for (int i = 1; i < parts.length; i++) {
      buffer.write(_toPascal(parts[i]));
    }
    return buffer.toString();
  }

  // Ensures an identifier isn't a reserved Dart word
  String _safeIdent(String name) {
    if (name.isNotEmpty && RegExp(r'^[0-9]').hasMatch(name)) {
      return 'id$name';
    }
    if (_reservedWords.contains(name)) return '${name}_';
    return name;
  }

  // calculator.firstOperand → firstOperand
  String _bindingIdToMember(String id) {
    final last = id.split('.').last;
    return _safeIdent(last);
  }

  String _bindingIdToType(String featureName, String id) =>
      '$featureName${_toUpperCamelIdentifier(_bindingIdToMember(id))}Binding';

  // calculator.firstOperand → enterFirstOperand
  String _bindingIdToDriverMethod(String id, String? interaction) {
    final last = id.split('.').last;
    final capitalized = '${last[0].toUpperCase()}${last.substring(1)}';
    return switch (interaction) {
      'action' => 'tap$capitalized',
      'output' => 'read$capitalized',
      _ => 'enter$capitalized',
    };
  }

  bool _bindingAllowsMany(String instanceCardinality) =>
      instanceCardinality == 'oneOrMore' || instanceCardinality == 'many';

  String _bindingInstanceCardinalityMember(String value) => switch (value) {
    'zeroOrMore' || 'many' => 'many',
    'oneOrMore' => 'oneOrMore',
    'zeroOrOne' => 'zeroOrOne',
    _ => 'exactlyOne',
  };

  String _readAllDriverMethod(String readMethod) =>
      readMethod.startsWith('read')
      ? 'readAll${readMethod.substring('read'.length)}'
      : 'readAll$readMethod';

  String _normalizedSourcePath(
    WorkspaceDiscoveryResult workspace,
    String path,
  ) {
    final root = workspace.config.root?.replaceAll('\\', '/') ?? '';
    final normalized = path.replaceAll('\\', '/');
    if (root.isNotEmpty && normalized.startsWith('$root/')) {
      return normalized.substring(root.length + 1);
    }
    return normalized.split('/').last;
  }

  String _ruleIdToConst(String id) => _idToConst(id, 2);

  String _scnIdToConst(String id) => _idToConst(id, 2);

  String _idToConst(String id, int skipCount) {
    final parts = id.split('-');
    final meaningful = parts.skip(skipCount).join('_');
    if (meaningful.isNotEmpty) {
      return _safeIdent(_toCamel(meaningful));
    }
    final fallback = parts.skip(1).join('_');
    return _safeIdent(_toCamel(fallback));
  }

  String _legacyScnIdToConst(String id) {
    final parts = id.split('-');
    final source = parts.skip(2).join('_').isNotEmpty
        ? parts.skip(2).join('_')
        : parts.skip(1).join('_');
    final fragments = source.split('_');
    final buffer = StringBuffer(fragments.first.toLowerCase());
    for (final fragment in fragments.skip(1)) {
      buffer.write(fragment[0].toUpperCase());
      buffer.write(fragment.substring(1).toLowerCase());
    }
    return _safeIdent(buffer.toString());
  }

  bool _isCanonicalScenarioId(String id) =>
      RegExp(r'^SCN-[A-Z0-9]+-[A-Z0-9]+(?:-[A-Z0-9]+)*$').hasMatch(id);

  String _formatDart(String source) => DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    lineEnding: '\n',
  ).format(source);
}

final class _GeneratedScenario {
  final String id;
  final String title;
  final Set<String> controlIds;

  const _GeneratedScenario({
    required this.id,
    required this.title,
    required this.controlIds,
  });
}

final class _GeneratedStepTarget {
  final String root;
  final String target;

  const _GeneratedStepTarget(this.root, this.target);
}

final class _GeneratedStep {
  final String expression;
  final String name;
  final int stringCount;

  _GeneratedStep(this.expression)
    : stringCount = RegExp(r'\{string\}').allMatches(expression).length,
      name = _nameForExpression(expression);

  String callbackType(String world) {
    final arguments = List<String>.generate(
      stringCount,
      (index) => 'String value${index + 1}',
    );
    return 'FutureOr<void> Function($world world${arguments.isEmpty ? '' : ', ${arguments.join(', ')}'})';
  }

  String invoke() {
    final arguments = List<String>.generate(
      stringCount,
      (index) => 'values[$index] as String',
    );
    return '$name(world${arguments.isEmpty ? '' : ', ${arguments.join(', ')}'})';
  }

  static String _nameForExpression(String expression) {
    final literals = expression
        .replaceAll('{string}', ' ')
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (literals.isEmpty) return 'step';
    return literals.first.toLowerCase() +
        literals
            .skip(1)
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join();
  }
}

final class _ScenarioLocation {
  final String featureId;
  final String ruleId;
  final String source;

  const _ScenarioLocation({
    required this.featureId,
    required this.ruleId,
    required this.source,
  });
}
