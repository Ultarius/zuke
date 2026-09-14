/// Stable semantic identity for a source binding.
///
/// Workspace placement supplies [target]. An annotation supplies the subject,
/// role, variant, and slot. Package and symbol provenance deliberately do not
/// participate in this key: moving the same logical binding between packages
/// must not make a duplicate identity appear unique.
final class BindingIdentity {
  final String subjectKind;
  final String subjectId;
  final String target;
  final String role;
  final String variant;
  final String slot;

  const BindingIdentity({
    required this.subjectKind,
    required this.subjectId,
    required this.target,
    required this.role,
    this.variant = 'default',
    this.slot = 'primary',
  }) : assert(subjectKind != ''),
       assert(subjectId != ''),
       assert(target != ''),
       assert(role != ''),
       assert(variant != ''),
       assert(slot != '');

  String get key => '$subjectKind|$subjectId|$target|$role|$variant|$slot';

  Map<String, Object?> toJson() => {
    'subjectKind': subjectKind,
    'subjectId': subjectId,
    'target': target,
    'role': role,
    'variant': variant,
    'slot': slot,
  };

  factory BindingIdentity.fromJson(Map<String, Object?> json) {
    String required(String name) {
      final value = json[name];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Binding identity requires $name');
      }
      return value;
    }

    final slot = required('slot');
    if (!isValidBindingSlot(slot)) {
      throw FormatException('Invalid binding slot: $slot');
    }
    return BindingIdentity(
      subjectKind: required('subjectKind'),
      subjectId: required('subjectId'),
      target: required('target'),
      role: required('role'),
      variant: required('variant'),
      slot: slot,
    );
  }
}

/// Returns whether [value] is a stable binding-slot token.
bool isValidBindingSlot(String value) {
  if (!RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$').hasMatch(value)) {
    return false;
  }
  const reserved = {
    'connect',
    'delete',
    'get',
    'head',
    'options',
    'patch',
    'post',
    'put',
    'trace',
  };
  return !reserved.contains(value);
}

/// Validates and returns [value] for use by tooling boundaries.
String requireBindingSlot(String value) {
  if (!isValidBindingSlot(value)) {
    throw FormatException('Invalid binding slot: $value');
  }
  return value;
}
