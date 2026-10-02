import 'package:zuke_frontend/zuke_frontend.dart';

/// Where [value] was declared for [field], falling back to [metadata]'s block.
///
/// A finding that names a declared value should point at that value, not at the
/// top of its metadata block: the whole point of recording positions is that the
/// reported line is the line to edit. The field is part of the key because the
/// same string under two fields means two different declarations, and a finding
/// about a feature's `targets` must not land on a binding that happens to name
/// the same target.
///
/// The fallback keeps every finding well-defined for a value with no recorded
/// position, rather than leaving the source null.
SourceLocation declarationSource(
  ParsedMetadata metadata,
  MetadataField field,
  Object? value,
) =>
    (value is String ? metadata.locationOf(field, value) : null) ??
    metadata.source;
