class CalculationResult {
  final String? result;
  final String? errorCode;

  const CalculationResult._({this.result, this.errorCode});

  factory CalculationResult.success(String result) =>
      CalculationResult._(result: result);

  factory CalculationResult.failure(String errorCode) =>
      CalculationResult._(errorCode: errorCode);

  bool get isSuccess => result != null;
  bool get isFailure => errorCode != null;
}
