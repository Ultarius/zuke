import 'package:zuke_frontend/zuke_frontend.dart' as frontend;

import 'proof_engine.dart';

/// Terminal rendering of validation findings.
final class RenderedValidation {
  const RenderedValidation(this.lines, {required this.hasHints});

  /// Lines including their leading two-space indent.
  final List<String> lines;

  /// Whether any group carried a remediation, so a caller that prints its own
  /// fallback hint can tell whether one is already there.
  final bool hasHints;
}

/// Binding ids and labels the workspace declares, longest first.
///
/// Grouping replaces these exact names with a placeholder; resolving the real
/// names avoids both a heuristic pattern and the false positives it would cause
/// on ordinary prose containing a dotted word.
List<String> bindingNamesOf(frontend.WorkspaceDiscoveryResult workspace) {
  final names = <String>{};
  for (final feature in workspace.data.features) {
    for (final binding
        in feature.metadata.bindings ?? const <frontend.ParsedBinding>[]) {
      final id = binding.id;
      if (id.isNotEmpty) names.add(id);
      final label = binding.label;
      if (label != null && label.isNotEmpty) names.add(label);
    }
  }
  return names.toList()
    ..sort((left, right) => right.length.compareTo(left.length));
}

/// Renders [messages] for a terminal.
///
/// Repeated findings are grouped by code plus a normalized shape -- identifiers,
/// declared binding names, and quoted values replaced by placeholders -- so a
/// stale-evidence failure reports one line per distinct problem with a count and
/// examples, instead of one line per rule. A group of a single message keeps the
/// plain one-line form, and every group that has a remediation prints it as a
/// `HINT`.
///
/// When a group is too large to print in full the sample says how many findings
/// were withheld and how to see them, rather than trailing off after `e.g.`.
RenderedValidation renderValidationMessages(
  List<ValidationMessage> messages, {
  required String label,
  Iterable<String> bindingNames = const [],
}) {
  if (messages.isEmpty) {
    return const RenderedValidation([], hasHints: false);
  }
  final bindingPattern = _bindingPattern(bindingNames);
  final groups = <String, _MessageGroup>{};
  for (final message in messages) {
    final signature =
        '${message.code} ${_shape(message.message, bindingPattern)}';
    final group = groups.putIfAbsent(signature, () => _MessageGroup());
    group.messages.add(message);
  }
  final lines = <String>[];
  var hasHints = false;
  for (final group in groups.values) {
    final first = group.messages.first;
    final title = group.messages.length == 1
        ? first.message
        : _shape(first.message, bindingPattern);
    final count = group.messages.length == 1
        ? ''
        : '  (${group.messages.length} findings)';
    lines.add('  $label: [${first.code}] $title$count');
    if (group.messages.length > 1) {
      final examples = <String>[];
      for (final message in group.messages) {
        if (examples.contains(message.message)) continue;
        examples.add(message.message);
        if (examples.length == _exampleLimit) break;
      }
      lines.add('      e.g. ${examples.join(' | ')}');
      final withheld = group.messages.length - examples.length;
      if (withheld > 0) {
        lines.add(
          '      (+$withheld more findings not shown; use --format json for '
          'the full list)',
        );
      }
    }
    final remediation = first.remediation ?? defaultRemediation(first.code);
    if (remediation != null) {
      hasHints = true;
      lines.add('      HINT: $remediation');
    }
  }
  return RenderedValidation(lines, hasHints: hasHints);
}

/// The distinct ineligibility reasons [messages] did not already report.
///
/// Eligibility reports restate validation errors verbatim; printing both would
/// double every line. Order is preserved and each reason appears once, even
/// when it collides with an extraction error that is already a diagnostic.
List<String> unprintedReasons(
  Iterable<ValidationMessage> messages,
  Iterable<String> reasons, {
  Iterable<String> alreadyReported = const [],
}) {
  final covered = messages.map((message) => message.message).toSet()
    ..addAll(alreadyReported);
  final seen = <String>{};
  return [
    for (final reason in reasons)
      if (!covered.contains(reason) && seen.add(reason)) reason,
  ];
}

/// How many distinct findings a grouped line samples before truncating.
const _exampleLimit = 3;

/// A pattern matching every declared binding name, or null when there are none.
RegExp? _bindingPattern(Iterable<String> names) {
  final alternatives = names
      .where((name) => name.trim().isNotEmpty)
      .map(RegExp.escape)
      .toList();
  if (alternatives.isEmpty) return null;
  return RegExp(alternatives.join('|'));
}

/// The identity of a message once volatile parts are replaced, used only for
/// grouping. The original text is what gets printed.
String _shape(String message, RegExp? bindingPattern) {
  var shaped = message.replaceAll(
    RegExp(r'\b(?:FEAT|EPIC|RULE|SCN|CTRL|REQ|PBI)-[A-Z0-9-]+'),
    '<id>',
  );
  if (bindingPattern != null) {
    shaped = shaped.replaceAll(bindingPattern, '<binding>');
  }
  return shaped
      .replaceAll(RegExp(r'"[^"]*"'), '"<value>"')
      .replaceAll(RegExp(r'\([^)]*\)'), '(<scope>)');
}

final class _MessageGroup {
  final messages = <ValidationMessage>[];
}
