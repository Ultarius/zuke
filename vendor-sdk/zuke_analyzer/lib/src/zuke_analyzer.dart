import 'dart:io';

import 'package:zuke_cli/tooling.dart';

class ZukeAnalyzer {
  Future<List<ZukeDiagnostic>> analyzePackage(String packageRoot) async {
    final output = await DartExtractor().extract(packageRoot);
    final diagnostics = output.errors
        .map(
          (error) =>
              ZukeDiagnostic(code: 'ZUKE-ANNOTATION-001', message: error),
        )
        .toList();
    final workspaceRoot = _findWorkspaceRoot(Directory(packageRoot));
    if (workspaceRoot == null) return diagnostics;

    final indexFile = File('${workspaceRoot.path}/.zuke/analyzer-index.json');
    ZukeIndex index;
    try {
      if (!indexFile.existsSync()) {
        throw const FormatException('analyzer index is missing');
      }
      index = ZukeIndex.read(indexFile);
      if (!index.isCurrent(root: workspaceRoot.path)) {
        throw const FormatException('analyzer index is stale');
      }
    } on FormatException catch (error) {
      diagnostics.add(
        ZukeDiagnostic(
          code: 'ZUKE-INDEX-STALE',
          message: 'Run "zuke generate" before analysis: $error',
        ),
      );
      return diagnostics;
    }

    for (final symbol in output.symbols) {
      for (final requirementId in symbol.requirementIds) {
        if (!index.requirementIds.contains(requirementId)) {
          diagnostics.add(
            _unknown('requirement', requirementId, symbol.symbolId),
          );
        }
      }
      for (final controlId in symbol.controlIds) {
        if (!index.controlIds.contains(controlId)) {
          diagnostics.add(_unknown('control', controlId, symbol.symbolId));
        }
      }
      final bindingId = symbol.bindingId;
      if (bindingId != null && !index.bindingIds.contains(bindingId)) {
        diagnostics.add(_unknown('binding', bindingId, symbol.symbolId));
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

  Directory? _findWorkspaceRoot(Directory start) {
    var current = start.absolute;
    while (true) {
      if (File('${current.path}/zuke.yaml').existsSync()) return current;
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }
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
