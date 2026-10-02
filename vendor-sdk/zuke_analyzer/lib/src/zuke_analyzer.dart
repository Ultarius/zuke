import 'dart:io';

import 'package:zuke_cli/tooling.dart';

class ZukeAnalyzer {
  Future<List<ZukeDiagnostic>> analyzePackage(String packageRoot) async {
    late final ResolvedPlacement placement;
    try {
      placement = resolvePlacement(packageRoot);
    } on PlacementFailure catch (error) {
      return [ZukeDiagnostic(code: error.code, message: error.message)];
    }
    final workspaceRoot = Directory(placement.workspaceRoot);
    final indexFile = File('${workspaceRoot.path}/.zuke/analyzer-index.json');
    ZukeIndexHeader? header;
    FormatException? headerError;
    try {
      if (indexFile.existsSync()) {
        header = ZukeIndexHeader.read(indexFile);
        if (header.isIncompatible) {
          return [
            ZukeDiagnostic(
              code: 'ZUKE-PLUGIN-STALE',
              message: header.mismatchMessage,
            ),
          ];
        }
      }
    } on FormatException catch (error) {
      // Keep the parse failure for the stale-index diagnostic below.
      headerError = error;
    }
    final output = await DartExtractor().extract(
      packageRoot,
      roots: placement.package.roots,
      target: placement.target.id,
    );
    final diagnostics = output.errors
        .map(
          (error) =>
              ZukeDiagnostic(code: 'ZUKE-ANNOTATION-001', message: error),
        )
        .toList();

    // Split by what the drift invalidates rather than stopping at the first
    // problem. An index that is merely behind still answers questions about the
    // specifications correctly, and returning early meant one edited file cost
    // the workspace every diagnostic for the rest of the session.
    ZukeIndex? index;
    var unusable = false;
    // Read once: `freshnessIssues` walks the workspace, and doing it twice per
    // package doubled the cost of the check for no new information.
    List<ZukeIndexFreshnessIssue> issues = const [];
    try {
      if (headerError != null) throw headerError;
      if (header == null) {
        throw const FormatException('analyzer index is missing');
      }
      index = ZukeIndex.fromJson(header.json);
      issues = index.freshnessIssues(root: workspaceRoot.path);
      if (issues.any((issue) => issue.rendersIndexUnusable)) {
        unusable = true;
        final first = issues.firstWhere((issue) => issue.rendersIndexUnusable);
        diagnostics.add(
          ZukeDiagnostic(
            code: 'ZUKE-INDEX-STALE',
            message: 'Run "zuke generate" before analysis: ${first.message}',
          ),
        );
      } else if (issues.isNotEmpty) {
        final first = issues.first;
        diagnostics.add(
          ZukeDiagnostic(
            code: 'ZUKE-INDEX-STALE',
            message:
                'The analyzer index is behind the sources. ${first.message} '
                '(${issues.length} in total; run zuke doctor for the full list).',
          ),
        );
      }
    } on FormatException catch (error) {
      // A missing, unparseable or incompatible index leaves nothing to consult,
      // so no rule that depends on it can answer.
      unusable = true;
      diagnostics.add(
        ZukeDiagnostic(
          code: 'ZUKE-INDEX-STALE',
          message: 'Run "zuke generate" before analysis: $error',
        ),
      );
    }
    if (unusable) index = null;
    // Which facts survive the drift, from the same classification the plugin
    // uses. A source edit invalidates claims and implementation sets but cannot
    // change what the specifications declare; a specification edit is the other
    // way round.
    //
    // A check whose facts are unavailable must not run. Substituting an empty ID
    // set and carrying on reports every annotation as unknown and every verified
    // requirement as untested, which is worse than reporting nothing: the split
    // would manufacture the very findings it was meant to avoid.
    final facts = issues.consultableFacts(indexReadable: index != null);
    final specificationFresh = facts.specification;
    final sourcesFresh = facts.sources;
    final ids = specificationFresh ? index!.requirementIds : const <String>{};
    final controls = specificationFresh ? index!.controlIds : const <String>{};
    final bindingsDefined = specificationFresh
        ? index!.bindingIds
        : const <String>{};
    final claims = sourcesFresh
        ? index!.verifiedClaims
        : const <ZukeImplementationClaim>[];

    for (final symbol in output.symbols) {
      final isImplementation =
          symbol.kind == ExtractedSymbolKind.requirementBoundary ||
          symbol.kind == ExtractedSymbolKind.presentationBoundary;
      // Claims are unavailable under a source drift, so "has no
      // @VerifiesRequirement" cannot be answered and is not asked.
      if (isImplementation && specificationFresh && sourcesFresh) {
        for (final requirementId in symbol.requirementIds) {
          if (ids.contains(requirementId) &&
              !claimsSatisfyRequirement(claims, requirementId, symbol.target)) {
            diagnostics.add(
              ZukeDiagnostic(
                code: 'ZUKE-MISSING-TEST',
                message:
                    'Requirement "$requirementId" on ${symbol.symbolId} has no '
                    '@VerifiesRequirement; add a test and run zuke generate.',
              ),
            );
          }
        }
      }
      // "Is this ID one the index knows?" is unanswerable while the ID sets are
      // in doubt, so the unknown-ID checks are gated on the same facts. The
      // duplicate-binding check below needs no index at all and keeps running.
      if (specificationFresh) {
        for (final requirementId in symbol.requirementIds) {
          if (!ids.contains(requirementId)) {
            diagnostics.add(
              _unknown('requirement', requirementId, symbol.symbolId),
            );
          }
        }
        for (final controlId in symbol.controlIds) {
          if (!controls.contains(controlId)) {
            diagnostics.add(_unknown('control', controlId, symbol.symbolId));
          }
        }
        final bindingId = symbol.bindingId;
        if (bindingId != null && !bindingsDefined.contains(bindingId)) {
          diagnostics.add(_unknown('binding', bindingId, symbol.symbolId));
        }
      }
    }
    final bindings = <String, List<String>>{};
    for (final symbol in output.symbols) {
      final bindingId = symbol.bindingId;
      if (bindingId != null) {
        (bindings[bindingId] ??= []).add(symbol.symbolId);
      }
    }
    for (final entry in bindings.entries) {
      if (entry.value.length > 1) {
        diagnostics.add(
          ZukeDiagnostic(
            code: 'ZUKE-INDEX-DUPLICATE-BINDING',
            message:
                'Binding ID "${entry.key}" has multiple package candidates: '
                '${entry.value..sort()}',
          ),
        );
      }
    }
    return diagnostics;
  }

  ZukeDiagnostic _unknown(
    String kind,
    String id,
    String symbolId,
  ) => ZukeDiagnostic(
    code: 'ZUKE-INDEX-UNKNOWN-ID',
    message:
        'Unknown $kind ID "$id" on $symbolId; run generation or fix the annotation.',
  );
}

class ZukeDiagnostic {
  final String code;
  final String message;

  const ZukeDiagnostic({required this.code, required this.message});
}

/// Entry point for an analyzer-facing diagnostic process. It never mutates
/// generated source; the CLI owns generation and release eligibility.
Future<void> main(List<String> args) async {
  final root = args.isEmpty ? Directory.current.path : args.first;
  final diagnostics = await ZukeAnalyzer().analyzePackage(root);
  for (final diagnostic in diagnostics) {
    stderr.writeln('${diagnostic.code}: ${diagnostic.message}');
  }
  if (diagnostics.isNotEmpty) exitCode = 1;
}
