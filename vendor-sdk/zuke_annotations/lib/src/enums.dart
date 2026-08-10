/// Roles that a control provider can play in an application topology.
enum ControlProviderKind {
  /// Application-level validation.
  applicationValidator('application-validator'),

  /// Request validation.
  requestValidator('request-validator'),

  /// Request middleware.
  requestMiddleware('request-middleware'),

  /// Public error mapping.
  publicErrorMapper('public-error-mapper'),

  /// Error interception.
  errorInterceptor('error-interceptor'),

  /// Gateway policy enforcement.
  gatewayPolicy('gateway-policy'),

  /// Logging interception.
  loggingInterceptor('logging-interceptor'),

  /// Structured logging.
  structuredLogger('structured-logger'),

  /// Telemetry processing.
  telemetryProcessor('telemetry-processor'),

  /// Semantics provision.
  semanticsProvider('semantics-provider');

  /// Stable serialized provider role.
  final String value;

  /// Creates a provider role with its serialized [value].
  const ControlProviderKind(this.value);

  /// Resolves a provider role from its serialized value.
  static ControlProviderKind fromValue(String v) =>
      values.firstWhere((e) => e.value == v);
}

/// Application layer at which a control is enforced.
enum EnforcementLayer {
  /// Network or edge layer.
  edge('edge'),

  /// Infrastructure layer.
  infrastructure('infrastructure'),

  /// Application layer.
  application('application'),

  /// Presentation layer.
  presentation('presentation');

  /// Stable serialized layer name.
  final String value;

  /// Creates an enforcement layer with its serialized [value].
  const EnforcementLayer(this.value);

  /// Resolves a layer from its serialized value.
  static EnforcementLayer fromValue(String v) =>
      values.firstWhere((e) => e.value == v);
}

/// Runtime multiplicity of widgets represented by one logical UI binding.
///
/// This is deliberately separate from the proof-layer `cardinality` field,
/// which counts annotated application providers.
enum BindingInstanceCardinality {
  /// Exactly one widget instance is expected.
  exactlyOne,

  /// Zero or one widget instance is expected.
  zeroOrOne,

  /// At least one widget instance is expected.
  oneOrMore,

  /// Any number of widget instances is allowed.
  many;

  /// Whether this cardinality permits no instances.
  bool get allowsZero => switch (this) {
    zeroOrOne || many => true,
    exactlyOne || oneOrMore => false,
  };

  /// Whether this cardinality permits multiple instances.
  bool get allowsMany => switch (this) {
    oneOrMore || many => true,
    exactlyOne || zeroOrOne => false,
  };
}
