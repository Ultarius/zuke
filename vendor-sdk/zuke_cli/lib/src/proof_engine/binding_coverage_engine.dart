/// The shared binding-coverage verdict computation.
///
/// Both front ends run this: `zuke validate` and the analysis-server plugin.
/// It is deliberately free of `../ir.dart` and of `zuke_frontend`, so importing
/// it into an analysis-server isolate does not pull `DartExtractor` or the
/// `zuke_core` IR types along with it. See `editor.dart` for that constraint.
///
/// **What it decides and what it does not.** This answers one question: is a
/// managed test registered for a rule's declared evidence slot? It establishes
/// nothing further. A registration it finds may call a service directly and never
/// perform the user's action, so `bound` means a matching test exists, not that
/// it exercises the promised behaviour. Deciding that needs runtime observation
/// of which entry point actually ran, which no static check can supply.
///
/// **Why absence is a three-state answer.** `unbound` is a claim that nothing
/// satisfies a slot, and that claim is only sound if the scan was complete. An
/// unreadable registration, a scenario argument that resolves to no ID, or a
/// runner scope that cannot attribute an adapter all leave the answer open, and
/// every one of them yields `unverified` instead. A resolver limitation must
/// never be allowed to read as a confident "nothing is registered".
///
/// The inputs are already-extracted facts rather than workspace objects, so that
/// the plugin can supply them from the index and the CLI from a live scan without
/// either front end reimplementing the matching, the aggregation, or the
/// uncertainty policy.
library;

/// Diagnostic codes raised from these verdicts.
///
/// Two codes, not one severity knob: an unbound slot is a known gap and an
/// unreadable registration is an unknown, and collapsing them would let a
/// resolver limitation read as a confident claim that nothing is registered.
const bindingCoverageUnboundCode = 'ZUKE-EVIDENCE-BINDING-UNBOUND';
const bindingCoverageUnverifiedCode = 'ZUKE-EVIDENCE-BINDING-UNVERIFIED';

/// The per-feature planning roll-up, always informational.
const bindingCoverageSummaryCode = 'ZUKE-EVIDENCE-BINDING-SUMMARY';

/// The default `variant` value a slot means when it does not name one.
const defaultSlotVariant = 'default';

/// How one registration compares to one dimension of a slot.
///
/// Three states because two would force a choice between claiming a gap the
/// scan cannot establish and crediting a claim it cannot verify.
enum BindingFit { satisfies, refutes, unknown }

/// One managed test registration, reduced to the facts a slot is matched on.
///
/// The nullable fields are **unknown, not absent**. [evidenceTypes] is null when
/// the declaration could not be read or inherited from nowhere; [target] and
/// [packageId] are null when no configured package owns the file. A registration
/// that may satisfy a slot has to block a gap claim, so each of these is
/// serialized as an explicit null rather than being omitted or coerced to an
/// empty value — otherwise a round trip through the index would turn `unverified`
/// into a false `unbound`.
final class ManagedRegistrationFact {
  final String scenarioId;

  /// Workspace-relative, forward-slashed path of the file declaring it.
  final String sourcePath;

  /// The configured target owning [sourcePath], or null when unattributable.
  final String? target;

  /// The configured package containing [sourcePath], or null when unattributable.
  ///
  /// Distinct from [target] because one target can own several packages, and a
  /// slot names a package.
  final String? packageId;

  /// The evidence kinds this registration publishes, or null when unreadable.
  final List<String>? evidenceTypes;

  const ManagedRegistrationFact({
    required this.scenarioId,
    required this.sourcePath,
    this.target,
    this.packageId,
    this.evidenceTypes,
  });

  Map<String, Object?> toJson() => {
    'scenarioId': scenarioId,
    'sourcePath': sourcePath,
    // Written even when null. The reader requires these keys so an older or
    // partial index cannot silently stand in for "unknown".
    'target': target,
    'packageId': packageId,
    'evidenceTypes': evidenceTypes,
  };

  /// Read strictly: a missing key is an error, not an empty value.
  ///
  /// Falling back to `?? const []` here would be the exact defect this class's
  /// documentation warns about — an unreadable registration would become one
  /// publishing no kinds, which refutes every slot instead of blocking it.
  static ManagedRegistrationFact? fromJson(Map<Object?, Object?> json) {
    final scenarioId = json['scenarioId'];
    final sourcePath = json['sourcePath'];
    if (scenarioId is! String || scenarioId.isEmpty) return null;
    if (sourcePath is! String || sourcePath.isEmpty) return null;
    // Every key must be present. Presence with a null value is the encoding for
    // "unknown"; absence means the producer did not know about the dimension,
    // which is not something to guess at.
    if (!json.containsKey('target')) return null;
    if (!json.containsKey('packageId')) return null;
    if (!json.containsKey('evidenceTypes')) return null;
    final target = json['target'];
    final packageId = json['packageId'];
    final kinds = json['evidenceTypes'];
    if (target != null && target is! String) return null;
    if (packageId != null && packageId is! String) return null;
    // Kept as a separate step from the null check so the promoted type survives to
    // the constructor call below; the closure in a combined condition prevents it.
    List<String>? parsedKinds;
    if (kinds != null) {
      if (kinds is! List) return null;
      final entries = <String>[];
      for (final entry in kinds) {
        if (entry is! String) return null;
        entries.add(entry);
      }
      parsedKinds = List.unmodifiable(entries);
    }
    return ManagedRegistrationFact(
      scenarioId: scenarioId,
      sourcePath: sourcePath,
      target: target as String?,
      packageId: packageId as String?,
      evidenceTypes: parsedKinds,
    );
  }

  @override
  String toString() =>
      'ManagedRegistrationFact($scenarioId @ $sourcePath -> '
      '$target/$packageId, ${evidenceTypes ?? '<unknown>'})';
}

/// One configured runner's target, package and adapter.
///
/// A registration records no adapter, so an adapter can only be attributed
/// through the runner configured for its target and package. [adapters] holds
/// every adapter the configuration supplies for that pair: more than one means no
/// registration can be attributed to one, which is a fact the engine needs rather
/// than an error it can raise.
final class RunnerScopeFact {
  const RunnerScopeFact({
    required this.target,
    required this.sourcePackage,
    required this.adapters,
  });

  final String target;
  final String sourcePackage;
  final List<String> adapters;

  Map<String, Object?> toJson() => {
    'target': target,
    'sourcePackage': sourcePackage,
    'adapters': adapters,
  };

  static RunnerScopeFact? fromJson(Map<Object?, Object?> json) {
    final target = json['target'];
    final sourcePackage = json['sourcePackage'];
    final adapters = json['adapters'];
    if (target is! String || target.isEmpty) return null;
    if (sourcePackage is! String || sourcePackage.isEmpty) return null;
    if (adapters is! List || adapters.any((a) => a is! String)) return null;
    // Distinct, because the engine asks "how many adapters could apply" and a
    // repeated entry is one adapter named twice. A producer that forgets to
    // deduplicate would otherwise turn every decided slot into an unknown one.
    return RunnerScopeFact(
      target: target,
      sourcePackage: sourcePackage,
      adapters: List.unmodifiable(
        adapters.cast<String>().toSet().toList()..sort(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RunnerScopeFact &&
      other.target == target &&
      other.sourcePackage == sourcePackage &&
      other.adapters.toSet().length == adapters.toSet().length &&
      other.adapters.every(adapters.contains);

  @override
  int get hashCode => Object.hash(
    target,
    sourcePackage,
    Object.hashAll(adapters.toSet().toList()..sort()),
  );
}

/// Where a rule is declared in its `.feature` file.
///
/// The analyzer plugin can only anchor a diagnostic on a Dart node, so the
/// location of the problem and the location of the report are different things.
/// This is the former, carried so the message can send the reader to the real
/// line instead of to a generated constant.
final class FeatureLocation {
  const FeatureLocation({
    required this.file,
    required this.line,
    this.column = 0,
  });

  /// Workspace-relative, forward-slashed path of the `.feature`.
  final String file;

  /// 1-based.
  final int line;

  /// 1-based, or 0 when unknown.
  final int column;

  Map<String, Object?> toJson() => {
    'file': file,
    'line': line,
    'column': column,
  };

  static FeatureLocation? fromJson(Map<Object?, Object?> json) {
    final file = json['file'];
    final line = json['line'];
    final column = json['column'];
    if (file is! String || file.isEmpty) return null;
    if (line is! int || line < 1) return null;
    if (column is! int || column < 0) return null;
    return FeatureLocation(file: file, line: line, column: column);
  }

  String get location => column > 0 ? '$file:$line:$column' : '$file:$line';
}

/// One rule's declared evidence slots, with the scenarios that share them.
///
/// A slot is declared by a rule and the rule's scenarios collectively satisfy it:
/// `requiredEvidence` is rule metadata, and a rule spanning two targets
/// legitimately covers its UI slot from a UI scenario and its API slot from an API
/// scenario. So one scenario carrying a registration satisfies the slot for the
/// rule, and the finding names which scenarios carry it and which do not.
final class EvidenceObligation {
  const EvidenceObligation({
    required this.featureId,
    required this.ruleId,
    required this.scenarioIds,
    required this.slots,
    this.location,
  });

  final String featureId;
  final String ruleId;

  /// Every scenario of the rule, complete and sorted.
  final List<String> scenarioIds;

  /// Each declared slot, keyed by type/target/sourcePackage/sourceAdapter/variant.
  final List<Map<String, String>> slots;

  /// The rule's declaration in the `.feature` file, when recorded.
  final FeatureLocation? location;

  Map<String, Object?> toJson() => {
    'featureId': featureId,
    'ruleId': ruleId,
    'scenarioIds': scenarioIds,
    'slots': slots,
    if (location != null) 'location': location!.toJson(),
  };

  static EvidenceObligation? fromJson(Map<Object?, Object?> json) {
    final featureId = json['featureId'];
    final ruleId = json['ruleId'];
    final scenarioIds = json['scenarioIds'];
    final slots = json['slots'];
    if (featureId is! String || ruleId is! String) return null;
    if (scenarioIds is! List || scenarioIds.any((s) => s is! String)) {
      return null;
    }
    if (slots is! List) return null;
    final parsedSlots = <Map<String, String>>[];
    for (final slot in slots) {
      if (slot is! Map) return null;
      final entries = <String, String>{};
      for (final entry in slot.entries) {
        if (entry.key is! String || entry.value is! String) return null;
        entries[entry.key! as String] = entry.value! as String;
      }
      parsedSlots.add(entries);
    }
    final location = json['location'];
    return EvidenceObligation(
      featureId: featureId,
      ruleId: ruleId,
      scenarioIds: List.unmodifiable(scenarioIds.cast<String>()),
      slots: List.unmodifiable(parsedSlots),
      location: location == null
          ? null
          : location is Map
          ? FeatureLocation.fromJson(location)
          : null,
    );
  }
}

/// What the scan could establish about one rule's obligation for one slot.
enum BindingCoverageVerdict {
  /// A registration satisfying the slot was found among the rule's scenarios.
  bound,

  /// No registration satisfies the slot, and the scan could establish that.
  unbound,

  /// The scan could not answer: a registration's kinds, target, package or
  /// adapter were unreadable, or a registration named no resolvable scenario.
  unverified,
}

/// One rule's relationship to one declared evidence slot.
final class BindingCoverageFinding {
  const BindingCoverageFinding({
    required this.featureId,
    required this.ruleId,
    required this.scenarioIds,
    required this.slot,
    required this.verdict,
    this.location,
    this.discoveredAt = const [],
    this.publishedKinds = '',
    this.reason = '',
  });

  final String featureId;
  final String ruleId;

  /// Every scenario this finding is about, complete.
  ///
  /// Structured rather than a pre-rendered string: a truncation decided here is
  /// invisible to a consumer that wants the full list, and a message is only one
  /// of the places these IDs are read.
  final List<String> scenarioIds;

  /// The declared slot, keyed by type/target/sourcePackage/sourceAdapter/variant.
  final Map<String, String> slot;
  final BindingCoverageVerdict verdict;

  /// The rule's declaration in the `.feature` file, when recorded.
  final FeatureLocation? location;

  /// Workspace-relative files holding the rule's registrations, empty when it has
  /// none. Carried so a finding can say what *was* found rather than only what was
  /// not.
  final List<String> discoveredAt;

  /// The evidence kinds the rule's registrations publish, for a message that can
  /// contrast them with the required one.
  final String publishedKinds;

  /// Why the verdict is what it is, in the reader's terms.
  final String reason;

  bool get isDecidable => verdict != BindingCoverageVerdict.unverified;

  /// `type/target/sourcePackage/sourceAdapter/variant`, the slot's full identity.
  ///
  /// Matching on the type alone would let a registration in another target, or of
  /// another variant, satisfy this slot, which is the substitution the slot
  /// identity exists to prevent.
  String get slotKey =>
      '${slot['type'] ?? slot['evidenceType'] ?? '-'}'
      '/${slot['target'] ?? '-'}'
      '/${slot['sourcePackage'] ?? '-'}'
      '/${slot['sourceAdapter'] ?? '-'}'
      '/${slot['variant'] ?? defaultSlotVariant}';

  String get type => slot['type'] ?? slot['evidenceType'] ?? '-';

  /// The scenarios rendered for a message, truncated for readability only.
  String get scenarioId => scenarioIds.length <= 3
      ? scenarioIds.join(', ')
      : '${scenarioIds.take(3).join(', ')} (+${scenarioIds.length - 3} more)';
}

/// Per-feature counts for planning, reported separately from the findings.
final class BindingCoverageFeatureSummary {
  const BindingCoverageFeatureSummary({
    required this.featureId,
    required this.obligations,
    required this.bound,
    required this.unbound,
    required this.unverified,
  });

  final String featureId;

  /// The number of rule/slot verdicts counted, not the number of scenarios.
  final int obligations;
  final int bound;
  final int unbound;
  final int unverified;
}

/// The verdict for one workspace, plus the planning roll-up.
final class BindingCoverageReport {
  const BindingCoverageReport({
    required this.findings,
    required this.featureSummaries,
    required this.unresolvedRegistrations,
  });

  final List<BindingCoverageFinding> findings;
  final List<BindingCoverageFeatureSummary> featureSummaries;

  /// Registrations whose scenario argument could not be resolved to an ID.
  /// Non-zero makes the whole report incomplete: an unresolvable registration
  /// could be the one satisfying any slot.
  final int unresolvedRegistrations;

  List<BindingCoverageFinding> get unbound => [
    for (final finding in findings)
      if (finding.verdict == BindingCoverageVerdict.unbound) finding,
  ];

  List<BindingCoverageFinding> get unverified => [
    for (final finding in findings)
      if (finding.verdict == BindingCoverageVerdict.unverified) finding,
  ];

  bool get isComplete => unresolvedRegistrations == 0;
}

/// The sentence both front ends show for one unbound slot.
///
/// Shared deliberately. The editor and `zuke validate` reach the same verdict
/// through the same engine, so they must also describe it identically — a reader
/// who sees the same gap in two places should not have to work out whether the
/// wording means something different.
///
/// The closing clause is not decoration: it is the limit of what this check
/// establishes, and it has to travel with the verdict wherever it is rendered. A
/// configured runner proves the project *can* produce that evidence type; it says
/// nothing about whether a test for these scenarios exists.
String bindingUnboundMessage(BindingCoverageFinding finding) =>
    'Evidence slot ${finding.slotKey} is unbound: ${finding.reason}. '
    'Affected scenarios: ${finding.scenarioId}. '
    'A matching runner being configured only means the project can execute that '
    'evidence type; it does not mean a test for these scenarios exists.'
    '${finding.location == null ? '' : ' Declared at ${finding.location!.location}.'}';

/// Computes binding-coverage verdicts from already-extracted facts.
///
/// Deliberately a plain function of its arguments. Every decision that could
/// otherwise differ between the CLI and the editor — which dimension blocks a
/// comparison, whether a registration counts once per file, how scenarios roll up
/// into a feature summary — is made here, once.
final class BindingVerdictEngine {
  const BindingVerdictEngine();

  /// The verdict for every rule/slot obligation supplied.
  ///
  /// [unresolvedRegistrations] is the count of registrations the scan could not
  /// resolve to scenario IDs. A non-zero value makes every slot `unverified`,
  /// because any one of them may be the registration that satisfies any slot.
  ///
  /// [selectedScenarioIds] narrows *which scenarios a finding names*, never which
  /// registrations count: a slot satisfied by an out-of-profile scenario is still
  /// satisfied. Pass null for whole-workspace scope, which is what the editor
  /// does — it has no profile, so a finding there can legitimately cover more
  /// scenarios than a profile-scoped `zuke validate` run.
  BindingCoverageReport compute({
    required List<EvidenceObligation> obligations,
    required List<ManagedRegistrationFact> registrations,
    required List<RunnerScopeFact> runnerScopes,
    int unresolvedRegistrations = 0,
    List<String>? selectedScenarioIds,
  }) {
    final registrationsByScenario = <String, List<ManagedRegistrationFact>>{};
    for (final registration in registrations) {
      registrationsByScenario
          .putIfAbsent(
            registration.scenarioId,
            () => <ManagedRegistrationFact>[],
          )
          .add(registration);
    }
    // A set, not a list: the question this map answers is how many *distinct*
    // adapters could supply a registration, so two runners naming the same
    // adapter are one adapter, not two. Counting them twice turns a decided slot
    // into an unknown one, which is a drift this shared engine exists to prevent.
    final scopes = <_ScopeKey, Set<String>>{};
    for (final scope in runnerScopes) {
      scopes
          .putIfAbsent(
            _ScopeKey(target: scope.target, sourcePackage: scope.sourcePackage),
            () => <String>{},
          )
          .addAll(scope.adapters);
    }
    final selected = selectedScenarioIds?.toSet();
    final findings = <BindingCoverageFinding>[];
    final summaries = <String, BindingCoverageFeatureSummary>{};

    for (final obligation in obligations) {
      var featureBound = 0, featureUnbound = 0, featureUnverified = 0;
      final scenarioIds = obligation.scenarioIds;
      if (scenarioIds.isEmpty) continue;
      final inScope = selected == null
          ? scenarioIds
          : scenarioIds.where(selected.contains).toList();
      if (inScope.isEmpty) continue;
      // Every registration of the rule, not just the selected scenarios: a slot
      // satisfied by an out-of-profile scenario is still satisfied.
      final bindings = [
        for (final id in scenarioIds) ...?registrationsByScenario[id],
      ];
      for (final slot in obligation.slots) {
        final finding = _judge(
          obligation: obligation,
          scenarioIds: inScope,
          registrationsByScenario: registrationsByScenario,
          slot: slot,
          bindings: bindings,
          unresolvedRegistrations: unresolvedRegistrations,
          scopes: scopes,
        );
        findings.add(finding);
        switch (finding.verdict) {
          case BindingCoverageVerdict.bound:
            featureBound++;
          case BindingCoverageVerdict.unbound:
            featureUnbound++;
          case BindingCoverageVerdict.unverified:
            featureUnverified++;
        }
      }
      if (featureBound + featureUnbound + featureUnverified > 0) {
        final previous = summaries[obligation.featureId];
        summaries[obligation.featureId] = BindingCoverageFeatureSummary(
          featureId: obligation.featureId,
          obligations:
              (previous?.obligations ?? 0) +
              featureBound +
              featureUnbound +
              featureUnverified,
          bound: (previous?.bound ?? 0) + featureBound,
          unbound: (previous?.unbound ?? 0) + featureUnbound,
          unverified: (previous?.unverified ?? 0) + featureUnverified,
        );
      }
    }
    return BindingCoverageReport(
      findings: List.unmodifiable(findings),
      featureSummaries: List.unmodifiable(summaries.values),
      unresolvedRegistrations: unresolvedRegistrations,
    );
  }

  /// Whether [registration] satisfies, contradicts, or cannot be compared to
  /// [slot].
  ///
  /// Every dimension the slot names has to agree. A dimension this cannot read
  /// yields unknown rather than refutes, because a registration that may satisfy
  /// the slot must block a gap claim.
  BindingFit _fitOf(
    ManagedRegistrationFact registration,
    Map<String, String> slot,
    Map<_ScopeKey, Set<String>> scopes,
  ) {
    final type = slot['type'] ?? slot['evidenceType'];
    final kinds = registration.evidenceTypes;
    // Unreadable kinds may include the required one, so they cannot refute.
    if (kinds == null) return BindingFit.unknown;
    if (!kinds.contains(type)) return BindingFit.refutes;

    final target = slot['target'];
    if (target != null) {
      // A registration outside every configured package has no target, so it can
      // be neither credited nor excluded.
      if (registration.target == null) return BindingFit.unknown;
      if (registration.target != target) return BindingFit.refutes;
    }

    final sourcePackage = slot['sourcePackage'];
    if (sourcePackage != null) {
      if (registration.packageId == null) return BindingFit.unknown;
      if (registration.packageId != sourcePackage) return BindingFit.refutes;
    }

    // A registration records no adapter: which one runs it is a property of the
    // runner the workspace configured for that target and package, not of the
    // call site. So this is decided only when the configuration attributes
    // exactly one adapter there, and left unknown otherwise. A slot naming an
    // adapter no runner declares is already a workspace-configuration error, and
    // deciding it here would report the same problem twice.
    final sourceAdapter = slot['sourceAdapter'];
    if (sourceAdapter != null) {
      final configured =
          scopes[_ScopeKey(target: target, sourcePackage: sourcePackage)];
      if (configured == null || configured.length != 1) {
        return BindingFit.unknown;
      }
      if (configured.single != sourceAdapter) return BindingFit.unknown;
    }
    return BindingFit.satisfies;
  }

  BindingCoverageFinding _judge({
    required EvidenceObligation obligation,
    required List<String> scenarioIds,
    required Map<String, List<ManagedRegistrationFact>> registrationsByScenario,
    required Map<String, String> slot,
    required List<ManagedRegistrationFact> bindings,
    required int unresolvedRegistrations,
    required Map<_ScopeKey, Set<String>> scopes,
  }) {
    final type = slot['type'] ?? slot['evidenceType'];

    if (type == null || type.isEmpty) {
      return BindingCoverageFinding(
        featureId: obligation.featureId,
        ruleId: obligation.ruleId,
        scenarioIds: scenarioIds,
        slot: slot,
        verdict: BindingCoverageVerdict.unverified,
        location: obligation.location,
        reason: 'the slot declares no evidence type, so it cannot be matched',
      );
    }

    // A non-default variant can never be satisfied from a registration: the
    // Flutter `TestVariant` a call site passes reaches `testWidgets` only and is
    // absent from the emitted record, so every record carries 'default'. Reporting
    // those as unbound would assert a falsehood about the framework.
    if ((slot['variant'] ?? defaultSlotVariant) != defaultSlotVariant) {
      return BindingCoverageFinding(
        featureId: obligation.featureId,
        ruleId: obligation.ruleId,
        scenarioIds: scenarioIds,
        slot: slot,
        verdict: BindingCoverageVerdict.unverified,
        location: obligation.location,
        reason:
            'the slot requires variant "${slot['variant']}" and registrations '
            'do not record a variant, so this slot cannot be decided from source',
      );
    }

    // One entry per file, so a rule whose four scenarios share one test file reads
    // as one registration site rather than four.
    final fits = <String, BindingFit>{};
    for (final registration in bindings) {
      final fit = _fitOf(registration, slot, scopes);
      final existing = fits[registration.sourcePath];
      // A file holding both a satisfying and an unknown registration satisfies:
      // the weaker reading must not overwrite the stronger one.
      if (existing == BindingFit.satisfies || fit == BindingFit.satisfies) {
        fits[registration.sourcePath] = BindingFit.satisfies;
      } else if (existing == null || existing == BindingFit.refutes) {
        fits[registration.sourcePath] = fit;
      }
    }
    final publishing = [
      for (final entry in fits.entries)
        if (entry.value == BindingFit.satisfies) entry.key,
    ]..sort();

    // Which of the rule's scenarios carry the registration, over the whole rule
    // and not only the in-scope ones: when the only registration sits outside the
    // profile, the reader still has to be told which scenario it is.
    final coveredSet = <String>{};
    for (final id in obligation.scenarioIds) {
      if ((registrationsByScenario[id] ?? const <ManagedRegistrationFact>[])
          .any(
            (registration) =>
                _fitOf(registration, slot, scopes) == BindingFit.satisfies,
          )) {
        coveredSet.add(id);
      }
    }
    final covered = coveredSet.toList()..sort();
    final uncovered = [
      for (final id in scenarioIds)
        if (!coveredSet.contains(id)) id,
    ]..sort();
    final discoveredAt = fits.keys.toList()..sort();
    final publishedKinds = _kindsOf(bindings);

    if (publishing.isNotEmpty) {
      return BindingCoverageFinding(
        featureId: obligation.featureId,
        ruleId: obligation.ruleId,
        scenarioIds: covered,
        slot: slot,
        verdict: BindingCoverageVerdict.bound,
        location: obligation.location,
        discoveredAt: List.unmodifiable(publishing),
        publishedKinds: publishedKinds,
        reason: uncovered.isEmpty
            ? 'every in-scope scenario has a matching registration'
            : 'satisfied by ${covered.length} of ${scenarioIds.length} in-scope '
                  'scenarios; ${uncovered.length} carry no registration of this '
                  'identity',
      );
    }

    if (unresolvedRegistrations > 0) {
      return BindingCoverageFinding(
        featureId: obligation.featureId,
        ruleId: obligation.ruleId,
        scenarioIds: scenarioIds,
        slot: slot,
        verdict: BindingCoverageVerdict.unverified,
        location: obligation.location,
        discoveredAt: List.unmodifiable(discoveredAt),
        publishedKinds: publishedKinds,
        reason:
            '$unresolvedRegistrations managed registration(s) named no resolvable '
            'scenario, so one of them may be the registration for this slot',
      );
    }

    // A registration that fits every dimension this can read, but not one it
    // cannot, leaves the answer open. Reporting it as a gap would claim an absence
    // the scan has not established.
    final undecidable = [
      for (final registration in bindings)
        if (_fitOf(registration, slot, scopes) == BindingFit.unknown)
          registration,
    ];
    if (undecidable.isNotEmpty) {
      final reasons = <String>{
        for (final registration in undecidable)
          _unknownReason(registration, slot, scopes),
      }.toList()..sort();
      return BindingCoverageFinding(
        featureId: obligation.featureId,
        ruleId: obligation.ruleId,
        scenarioIds: scenarioIds,
        slot: slot,
        verdict: BindingCoverageVerdict.unverified,
        location: obligation.location,
        discoveredAt: List.unmodifiable(discoveredAt),
        publishedKinds: publishedKinds,
        reason: reasons.join('; '),
      );
    }

    return BindingCoverageFinding(
      featureId: obligation.featureId,
      ruleId: obligation.ruleId,
      scenarioIds: scenarioIds,
      slot: slot,
      verdict: BindingCoverageVerdict.unbound,
      location: obligation.location,
      discoveredAt: List.unmodifiable(discoveredAt),
      publishedKinds: publishedKinds,
      reason: bindings.isEmpty
          ? "no managed registration names any of this rule's scenarios"
          : _refutationReason(bindings, slot, publishedKinds),
    );
  }

  /// Why a registration could not be compared, in the reader's terms.
  String _unknownReason(
    ManagedRegistrationFact registration,
    Map<String, String> slot,
    Map<_ScopeKey, Set<String>> scopes,
  ) {
    // Ordered the way `_fitOf` evaluates, so the reason names the first dimension
    // that actually blocked the comparison.
    if (registration.evidenceTypes == null) {
      return 'a managed registration for this rule declares evidence kinds that '
          'could not be read as constants, so one of them may publish this slot';
    }
    if (registration.target == null) {
      return 'a managed registration for this rule belongs to no configured '
          'package, so its target cannot be compared to the slot target';
    }
    if (registration.packageId == null) {
      return 'a managed registration for this rule belongs to no configured '
          'package, so its package cannot be compared to the slot package';
    }
    final adapters =
        scopes[_ScopeKey(
          target: slot['target'],
          sourcePackage: slot['sourcePackage'],
        )];
    if (adapters == null || adapters.isEmpty) {
      return "no runner is configured for the slot's target and package, so no "
          'adapter can be attributed to a registration';
    }
    return 'the slot names an adapter that more than one configured runner could '
        'supply, so a registration cannot be attributed to one';
  }

  /// Why the registrations fail to satisfy the slot, naming what they publish.
  String _refutationReason(
    List<ManagedRegistrationFact> bindings,
    Map<String, String> slot,
    String publishedKinds,
  ) {
    final type = slot['type'] ?? slot['evidenceType'];
    final targets = {
      for (final binding in bindings) binding.target ?? '<unattributed>',
    }.toList()..sort();
    final packages = {
      for (final binding in bindings) binding.packageId ?? '<unattributed>',
    }.toList()..sort();
    if (!bindings.any(
      (binding) => binding.evidenceTypes?.contains(type) ?? false,
    )) {
      return 'registrations publish $publishedKinds, which does not include '
          '"$type"';
    }
    if (slot['target'] != null && !targets.contains(slot['target'])) {
      return 'registrations publish $publishedKinds, but none in the slot target '
          '(registration targets: ${targets.join(', ')})';
    }
    return 'registrations publish $publishedKinds in the slot target, but none in '
        'the slot package "${slot['sourcePackage']}" (registration packages: '
        '${packages.join(', ')})';
  }

  static String _kindsOf(List<ManagedRegistrationFact> bindings) {
    final kinds = <String>{
      for (final binding in bindings) ...?binding.evidenceTypes,
    }.toList()..sort();
    return kinds.isEmpty ? 'no evidence kinds' : kinds.join(', ');
  }
}

/// The target and package a configured runner serves, as a map key.
final class _ScopeKey {
  const _ScopeKey({required this.target, required this.sourcePackage});

  final String? target;
  final String? sourcePackage;

  @override
  bool operator ==(Object other) =>
      other is _ScopeKey &&
      other.target == target &&
      other.sourcePackage == sourcePackage;

  @override
  int get hashCode => Object.hash(target, sourcePackage);
}
