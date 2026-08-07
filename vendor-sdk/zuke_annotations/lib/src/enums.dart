enum ControlProviderKind {
  applicationValidator('application-validator'),
  requestValidator('request-validator'),
  requestMiddleware('request-middleware'),
  publicErrorMapper('public-error-mapper'),
  errorInterceptor('error-interceptor'),
  gatewayPolicy('gateway-policy'),
  loggingInterceptor('logging-interceptor'),
  structuredLogger('structured-logger'),
  telemetryProcessor('telemetry-processor'),
  semanticsProvider('semantics-provider');

  final String value;
  const ControlProviderKind(this.value);

  static ControlProviderKind fromValue(String v) =>
      values.firstWhere((e) => e.value == v);
}

enum EnforcementLayer {
  edge('edge'),
  infrastructure('infrastructure'),
  application('application'),
  presentation('presentation');

  final String value;
  const EnforcementLayer(this.value);

  static EnforcementLayer fromValue(String v) =>
      values.firstWhere((e) => e.value == v);
}

/// Runtime multiplicity of widgets represented by one logical UI binding.
///
/// This is deliberately separate from the proof-layer `cardinality` field,
/// which counts annotated application providers.
enum BindingInstanceCardinality {
  exactlyOne,
  zeroOrOne,
  oneOrMore,
  many;

  bool get allowsZero => switch (this) {
    zeroOrOne || many => true,
    exactlyOne || oneOrMore => false,
  };

  bool get allowsMany => switch (this) {
    oneOrMore || many => true,
    exactlyOne || zeroOrOne => false,
  };
}
