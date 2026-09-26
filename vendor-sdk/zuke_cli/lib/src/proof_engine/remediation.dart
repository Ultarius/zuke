/// Concrete next step for a validation code.
///
/// Validators own the finding; this table owns the remedy so a terminal
/// failure never depends on the operator inferring the recipe from the
/// message itself. It is deliberately family-based: every code under
/// `ZUKE-ID-` is an identifier problem, so it shares one remedy.
///
/// A diagnostic that carries its own `remediation` wins over this table, so
/// validators can override with something more specific. Every code emitted by
/// a validator must resolve here; `test/remediation_coverage_test.dart` scans
/// the validator sources and fails when a new code is added without a remedy.
library;

const String _evidenceRecipe =
    'Republish evidence by running the tests again: `zuke test --profile '
    '<profile>`, or `zuke lock --refresh` to regenerate, test, validate and '
    're-lock in one step.';

/// Returns the remediation for [code], or null when no remedy applies.
String? defaultRemediation(String code) {
  // Informational success codes carry no action.
  if (code.endsWith('-OK')) return null;
  return switch (code) {
    'ZUKE-EVIDENCE-STALE' =>
      'Inputs changed after evidence was recorded, so its digests no longer '
          'match. $_evidenceRecipe',
    'ZUKE-SCENARIO-UNTESTED' =>
      'A scenario selected by this profile never executed. $_evidenceRecipe',
    'ZUKE-SCENARIO-UNEXPECTED' =>
      'Evidence exists for a scenario the workspace no longer declares. '
          '$_evidenceRecipe',
    'ZUKE-PROFILE-UNTESTED' =>
      'The profile has no executed evidence at all. $_evidenceRecipe',
    'ZUKE-EVIDENCE-006' =>
      'Security evidence was skipped. Execute the scenario so real evidence is '
          'published; skipped security evidence is never accepted.',
    'ZUKE-SCHEMA-002' =>
      'Set the metadata `schemaVersion` to "1", or migrate the feature file '
          'with the current CLI.',
    'ZUKE-ID-010' =>
      'Move the id out of the title text and into the metadata block or a tag.',
    'ZUKE-SCHEMA-001' =>
      'Remove the unsupported metadata keys; only the declared allow-list is '
          'accepted.',
    'ZUKE-DISCOVERY-001' =>
      'Fix the workspace discovery failure reported above '
          'and re-run.',
    'ZUKE-REF-CYCLE' =>
      'Break the reference cycle by removing one of the edges '
          'listed above.',
    'ZUKE-TRUST-001' =>
      'Publish the trust bundle at the reported path with an '
          'authorized key whose status is active and whose usages include the '
          'required one.',
    _ => _familyRemediation(code),
  };
}

/// `ZK-` and `ZUKE-` name the same families: `ZK-BINDING-...` and
/// `ZUKE-BINDING-...` are both binding findings. The prefix is stripped once so
/// each family is declared in exactly one place.
String? _familyRemediation(String rawCode) {
  final code = _withoutDiagnosticPrefix(rawCode);
  if (code.startsWith('ID-')) {
    return 'Rename the identifier to match the required pattern: upper-case '
        'segments separated by "-", scoped by a `FEAT-`/`RULE-`/`SCN-` kind '
        'prefix. Keep ids in metadata blocks and tags, not in title text.';
  }
  if (code.startsWith('REF-')) {
    return 'Repair the cross-reference: the referenced requirement, control, '
        'binding or endpoint is not declared, or declare it in the spec that '
        'owns it.';
  }
  if (code.startsWith('CARD-')) {
    return 'Correct the binding cardinality in the feature metadata, or the '
        'implementation obligation that claims it.';
  }
  if (code.startsWith('MAP-')) {
    return 'Add the missing mapping entry in `specs/registry/`, or drop the '
        'reference to it.';
  }
  if (code.startsWith('EVID')) {
    return 'Publish the required evidence for this rule. $_evidenceRecipe';
  }
  if (code.startsWith('PROVIDER-')) {
    return 'Fix the provider declaration in the project policy: the provider '
        'is unknown, duplicated, or missing a required field.';
  }
  if (code.startsWith('POLICY-')) {
    return 'Resolve the conflict in the policy files; the same control may '
        'not be declared twice.';
  }
  if (code.startsWith('PROCESS-') || code.startsWith('TEST-')) {
    return 'Inspect the runner output above; the configured runner did not '
        'complete as declared. Check `executable`, `args`, `workingDirectory` '
        'and `timeoutSeconds` for that runner.';
  }
  if (code.startsWith('FLUTTER-')) {
    return 'Prepare the Flutter toolchain with `dart run '
        'tool/prepare_flutter_toolchain.dart`, then re-run.';
  }
  if (code.startsWith('EXTRACT-')) {
    return 'Fix the extraction failure above; generated fragments and resolved '
        'sources must both be available.';
  }
  if (code.startsWith('BINDING-')) {
    return 'Declare the binding `target` and `variant` so the provider can be '
        'matched to exactly one generated binding.';
  }
  if (code.startsWith('REGISTRATION-')) {
    return 'Register every selected scenario in exactly one runner for the '
        'target, then re-run.';
  }
  if (code.startsWith('CONTROL-')) {
    return 'Repair the control declaration or its proof: declare the provider, '
        'the required semantics, and the evidence the policy expects.';
  }
  if (code.startsWith('IR-')) {
    return 'Fix the extracted graph: remove duplicate nodes and restore the '
        'missing edges reported above, then re-extract.';
  }
  if (code.startsWith('IMPL-')) {
    return 'Align the implementation obligation with the declared bindings: '
        'every claimed slot must resolve to a known binding provider.';
  }
  if (code.startsWith('PROOF-')) {
    return 'Give each proof exactly one owner; remove the conflicting control '
        'or evidence declaration.';
  }
  if (code.startsWith('ALIGNMENT-')) {
    return 'Align the supported dependency tuple: fix the constraint, override, '
        'or resolution reported above, then re-run the alignment check.';
  }
  if (code.startsWith('ARTIFACT-')) {
    return 'Fix the artifact bundle: every input must exist, be stable, and '
        'contain no secrets or unexpected sources.';
  }
  if (code.startsWith('CONFIG-')) {
    return 'Fix `zuke.yaml`: unknown keys, legacy version keys, and invalid '
        'values are rejected before any stage runs.';
  }
  if (code.startsWith('CONTRACT-')) {
    return 'Align the contract check: document the route, or remove the stale '
        'OpenAPI operation.';
  }
  if (code.startsWith('DOCTOR-')) {
    return 'Resolve the diagnosed setup problem, then re-run `zuke doctor`.';
  }
  if (code.startsWith('EXECUTION-') || code.startsWith('REGISTRATION-')) {
    return 'Register every selected scenario in exactly one runner and let it '
        'execute to completion, then re-run.';
  }
  if (code.startsWith('GATE-')) {
    return 'Resolve the gate stage reported above; the gate never publishes a '
        'partial result.';
  }
  if (code.startsWith('LOCK-')) {
    return 'Refresh the profile lock with `zuke lock --refresh`, or '
        '`zuke lock --update` to refresh the selected locks only.';
  }
  if (code.startsWith('SOURCE-')) {
    return 'Fix the resolved source mapping: the package, adapter, or path '
        'reported above does not resolve in this workspace.';
  }
  if (code.startsWith('BATCH-')) {
    return 'Batch files reject shell metacharacters (`&`, `|`, `<`, `>`, `^`, '
        '`%`, `!`, quotes, newlines). Quote or escape the argument, or use a '
        'native executable / shell-free runner instead.';
  }
  if (code.startsWith('DART-FROG-')) {
    return 'Fix the Dart Frog topology: restore the route or middleware '
        'registration, or mark the affected dimension indeterminate rather '
        'than guessing.';
  }
  if (code.startsWith('TARGET-')) {
    return 'Declare the source-mapping target: the declaration names a target '
        'the workspace does not define, is ambiguous, or omits it entirely.';
  }
  if (code.startsWith('COMMAND-RESULT-')) {
    return 'Resolve the command-result conflict: two writers targeted the same '
        'result file, or no result was written for a failed command.';
  }
  if (code.startsWith('COVERAGE-')) {
    return 'Fix the coverage gate: raise coverage, or correct the LCOV input '
        'and baseline the gate compares against.';
  }
  if (code.startsWith('HISTORY-')) {
    return 'Regenerate the assurance-history artifact with the current CLI; '
        'legacy history formats are not accepted.';
  }
  if (code.startsWith('RESULT-')) {
    return 'Publish the missing result: the runner did not write the artifact '
        'its registration promised.';
  }
  if (code.startsWith('VALIDATE-')) {
    return 'Fix the validation failure reported above; `zuke validate` '
        'reproduces it outside the composed pipeline.';
  }
  if (code.startsWith('ATTEST-')) {
    return 'Re-issue the external attestation with a current validity window '
        'before the gate depends on it.';
  }
  return null;
}

/// Drops the `ZK-` or `ZUKE-` namespace prefix from [code].
String _withoutDiagnosticPrefix(String code) {
  for (final prefix in const ['ZUKE-', 'ZK-']) {
    if (code.startsWith(prefix)) return code.substring(prefix.length);
  }
  return code;
}
