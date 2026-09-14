import 'enums.dart';

/// Associates a declaration with one or more governed backend requirements.
class ImplementsRequirement {
  /// Requirement identifiers implemented by the declaration.
  final List<String> requirementIds;

  /// Variant name used when resolving the implementation.
  final String variant;

  /// Binding slot occupied by the implementation.
  final String slot;

  /// Creates implementation metadata for [requirementIds].
  const ImplementsRequirement(
    this.requirementIds, {
    this.variant = 'default',
    this.slot = 'primary',
  });
}

/// Associates a declaration with one or more requirements presented in a UI.
class PresentsRequirement {
  /// Requirement identifiers presented by the declaration.
  final List<String> requirementIds;

  /// Variant name used when resolving the presentation.
  final String variant;

  /// Binding slot occupied by the presentation.
  final String slot;

  /// Creates presentation metadata for [requirementIds].
  const PresentsRequirement(
    this.requirementIds, {
    this.variant = 'default',
    this.slot = 'primary',
  });
}

/// Declares a runtime provider for one or more governed controls.
class ProvidesControl {
  /// Control identifiers provided by the declaration.
  final List<String> controlIds;

  /// Provider role, when the control requires a specific role.
  final ControlProviderKind? kind;

  /// Layer at which the provider is enforced.
  final EnforcementLayer? layer;

  /// Variant name used when resolving the provider.
  final String variant;

  /// Binding slot occupied by the provider.
  final String slot;

  /// Creates control-provider metadata for [controlIds].
  const ProvidesControl(
    this.controlIds, {
    this.kind,
    this.layer,
    this.variant = 'default',
    this.slot = 'primary',
  });
}

/// Associates a UI declaration with a generated Zuke binding identifier.
class ZukeBinding {
  /// Generated binding identifier.
  final String bindingId;

  /// Binding variant selected by the application.
  final String variant;

  /// Binding slot occupied by the binding.
  final String slot;

  /// Creates binding metadata for [bindingId].
  const ZukeBinding(
    this.bindingId, {
    this.variant = 'default',
    this.slot = 'primary',
  });
}

/// Generated binding metadata consumed by target-specific runners.
abstract interface class ZukeBindingDescriptor {
  /// Stable generated binding identifier.
  String get id;

  /// Runtime multiplicity of the binding.
  BindingInstanceCardinality get instanceCardinality;
}

/// Associates a test declaration with requirement and evidence identifiers.
class VerifiesRequirement {
  /// Requirement identifiers verified by the declaration.
  final List<String> requirementIds;

  /// Evidence kind emitted by the verification.
  final String? evidenceType;

  /// Variant name used when resolving the verification.
  final String variant;

  /// Binding slot occupied by the verification.
  final String slot;

  /// Scenario identifiers covered by the verification.
  final List<String> scenarioIds;

  /// Control identifiers covered by the verification.
  final List<String> controlIds;

  /// Creates verification metadata for [requirementIds].
  const VerifiesRequirement(
    this.requirementIds, {
    this.evidenceType,
    this.variant = 'default',
    this.slot = 'primary',
    this.scenarioIds = const [],
    this.controlIds = const [],
  });
}
