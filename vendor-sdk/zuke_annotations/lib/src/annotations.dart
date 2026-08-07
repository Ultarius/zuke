import 'enums.dart';

class ImplementsRequirement {
  final List<String> requirementIds;
  final String target;
  final String variant;
  final String slot;
  const ImplementsRequirement(
    this.requirementIds, {
    this.target = 'backend',
    this.variant = 'default',
    this.slot = 'primary',
  });
}

class PresentsRequirement {
  final List<String> requirementIds;
  final String target;
  final String variant;
  final String slot;
  const PresentsRequirement(
    this.requirementIds, {
    this.target = 'flutter',
    this.variant = 'default',
    this.slot = 'primary',
  });
}

class ProvidesControl {
  final List<String> controlIds;
  final ControlProviderKind? kind;
  final EnforcementLayer? layer;
  final String target;
  final String variant;
  final String slot;
  const ProvidesControl(
    this.controlIds, {
    this.kind,
    this.layer,
    this.target = 'backend',
    this.variant = 'default',
    this.slot = 'primary',
  });
}

class ZukeBinding {
  final String bindingId;
  final String variant;
  final String target;
  const ZukeBinding(
    this.bindingId, {
    this.variant = 'default',
    this.target = 'flutter',
  });
}

/// Generated binding metadata consumed by target-specific runners.
abstract interface class ZukeBindingDescriptor {
  String get id;
  BindingInstanceCardinality get instanceCardinality;
}

class VerifiesRequirement {
  final List<String> requirementIds;
  final String? evidenceType;
  final String? target;
  final String variant;
  final List<String> scenarioIds;
  final List<String> controlIds;
  const VerifiesRequirement(
    this.requirementIds, {
    this.evidenceType,
    this.target,
    this.variant = 'default',
    this.scenarioIds = const [],
    this.controlIds = const [],
  });
}
