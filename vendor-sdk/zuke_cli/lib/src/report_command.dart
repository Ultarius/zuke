import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'extraction_service.dart';
import 'lock_command.dart';
import 'proof_engine.dart';
import 'reporter.dart';

class ReportCommand {
  final ArgResults args;

  ReportCommand(this.args);

  Future<int> execute() async {
    final requestedRoot = args['root'] as String? ?? Directory.current.path;
    final root = Directory(requestedRoot).absolute.path;
    final quiet =
        args.options.contains('quiet') && (args['quiet'] as bool? ?? false);

    void info(String message) {
      if (!quiet) stdout.writeln(message);
    }

    final discovery = WorkspaceDiscovery();
    final workspace = discovery.discover(root);
    final extraction = await ExtractionService().extract(workspace);

    final validation = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
      evidenceRecords: extraction.evidenceRecords,
    );

    final report = validation.toReport(
      evidence: extraction.evidenceRecords,
      requiredEvidence: validation.requiredEvidence,
    );

    final features = workspace.data.features.map((feature) {
      final featureTags = feature.tags.map((tag) => tag.name).toSet();
      final rules = feature.rules.map((rule) {
        final effectiveRuleTags = {
          ...featureTags,
          ...rule.tags.map((tag) => tag.name),
        };
        final rulePbis =
            rule.tags
                .map((tag) => tag.name)
                .where((tag) => tag.startsWith('PBI-'))
                .toSet()
                .toList()
              ..sort();
        final scenarios = rule.scenarios.map((scenario) {
          final scenarioTags = scenario.tags.map((tag) => tag.name).toList()
            ..sort();
          final effectiveScenarioTags = {
            ...effectiveRuleTags,
            ...scenarioTags,
          }.toList()..sort();
          final examples = scenario.examples.map((block) {
            final tags = block.tags.map((tag) => tag.name).toList()..sort();
            final effectiveTags = {...effectiveScenarioTags, ...tags}.toList()
              ..sort();
            return ZukeModelExamples(
              title: block.title,
              tags: tags,
              effectiveTags: effectiveTags,
              headers: block.headers,
              rows: block.rows,
            );
          }).toList();
          return ZukeModelScenario(
            id: scenarioTags.firstWhere(
              (tag) => tag.startsWith('SCN-'),
              orElse: () => '',
            ),
            title: scenario.scenarioElement.title,
            keyword: scenario.scenarioElement.keyword.name,
            tags: scenarioTags,
            effectiveTags: effectiveScenarioTags,
            steps: scenario.steps
                .map(
                  (step) =>
                      ZukeModelStep(keyword: step.keyword, text: step.text),
                )
                .toList(),
            examples: examples,
          );
        }).toList();
        return ZukeModelRule(
          id: rule.metadata.id ?? '',
          title: rule.ruleElement.title,
          pbis: rulePbis,
          requiredEvidence: rule.metadata.requiredEvidence ?? const [],
          securityProfile: rule.metadata.securityProfile,
          requires: (rule.metadata.requires ?? const [])
              .map(
                (ref) => ZukeModelControlRequirement(
                  kind: ref.kind,
                  id: ref.id,
                  target: ref.target,
                  cardinality: ref.cardinality,
                  acceptableAssurance: ref.acceptableAssurance ?? const [],
                  variant: ref.variant,
                  slot: ref.slot,
                ),
              )
              .toList(),
          scenarios: scenarios,
        );
      }).toList()..sort((left, right) => left.id.compareTo(right.id));
      final bindings =
          (feature.metadata.bindings ?? const [])
              .map(
                (binding) => ZukeModelBinding(
                  id: binding.id,
                  target: binding.target,
                  cardinality: binding.cardinality,
                  instanceCardinality: binding.instanceCardinality,
                  interaction: binding.interaction,
                  variant: binding.variant,
                  slot: binding.slot,
                ),
              )
              .toList()
            ..sort((left, right) => left.id.compareTo(right.id));
      return ZukeModelFeature(
        id: feature.metadata.id ?? '',
        title: feature.featureElement.title,
        epic: feature.metadata.epic,
        owner: feature.metadata.owner,
        status: feature.metadata.status,
        targets: feature.metadata.targets ?? const [],
        pbis: feature.metadata.pbis ?? const [],
        bindings: bindings,
        rules: rules,
      );
    }).toList()..sort((left, right) => left.id.compareTo(right.id));

    final epics = workspace.data.epics.values.map((epic) {
      final id = epic['id']?.toString() ?? '';
      final featureIds =
          features
              .where((feature) => feature.epic == id)
              .map((feature) => feature.id)
              .toList()
            ..sort();
      return ZukeModelEpic(
        id: id,
        title: epic['title']?.toString(),
        owner: epic['owner']?.toString(),
        featureIds: featureIds,
      );
    }).toList()..sort((left, right) => left.id.compareTo(right.id));

    final pbis =
        workspace.data.registries.values
            .where((entry) => entry['_sourceList'] == 'pbis')
            .map((entry) {
              final id = entry['id']?.toString() ?? '';
              final ruleIds = [
                for (final feature in features)
                  for (final rule in feature.rules)
                    if (rule.pbis.contains(id)) rule.id,
              ]..sort();
              return ZukeModelPbi(
                id: id,
                title: entry['title']?.toString(),
                owner: entry['owner']?.toString(),
                feature: entry['feature']?.toString(),
                status: entry['status']?.toString(),
                ruleIds: ruleIds,
              );
            })
            .toList()
          ..sort((left, right) => left.id.compareTo(right.id));

    final registriesMap = Map<String, Object?>.from(workspace.data.registries);

    Map<String, Object?> lockDigests = {};
    final lockFile = File(
      resolveProfileLockPath(root, workspace, 'pullRequest'),
    );
    if (lockFile.existsSync()) {
      try {
        final lockJson = jsonDecode(lockFile.readAsStringSync());
        if (lockJson is Map<String, Object?>) {
          lockDigests = lockJson;
        }
      } catch (_) {}
    }

    final workspaceName = Directory(
      root,
    ).uri.pathSegments.where((s) => s.isNotEmpty).last;

    final specModel = ZukeModel(
      workspaceName: workspaceName,
      root: root,
      graph: ZukeModelGraph(epics: epics, pbis: pbis, features: features),
      registries: registriesMap,
      validationReport: report,
      lockDigests: lockDigests,
    );

    final configuredReportOutput =
        args['output'] as String? ?? 'generated/report/zuke-model.json';
    final reportFile = File('$root/$configuredReportOutput');
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(renderSpecModelJson(specModel));

    info('Wrote $configuredReportOutput');
    return 0;
  }
}
