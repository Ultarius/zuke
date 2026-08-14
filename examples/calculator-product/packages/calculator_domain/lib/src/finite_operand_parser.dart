import 'package:zuke_annotations/zuke_annotations.dart';

/// Enforces the supported finite numeric grammar for calculator operands.
/// This is the enforcement point for CTRL-CALC-INPUT-VALIDATION.
@ProvidesControl(
  ['CTRL-CALC-INPUT-VALIDATION'],
  kind: ControlProviderKind.applicationValidator,
  layer: EnforcementLayer.application,
)
class FiniteOperandParser {
  static final _numericPattern = RegExp(r'^-?\d+(\.\d+)?$');
  static final _infinityPattern = RegExp(r'^[-+]?[iI]nf(inity)?$');
  static final _nanPattern = RegExp(r'^[-+]?[nN][aA][nN]$');

  num parse(String input) {
    if (input.trim().isEmpty) {
      throw const FormatException('Empty operand');
    }

    final trimmed = input.trim();

    if (_infinityPattern.hasMatch(trimmed) || _nanPattern.hasMatch(trimmed)) {
      throw const FormatException('Not a finite number');
    }

    if (!_numericPattern.hasMatch(trimmed)) {
      throw const FormatException('Invalid operand format');
    }

    final value = num.tryParse(trimmed);
    if (value == null) {
      throw const FormatException('Invalid operand');
    }

    if (!value.isFinite) {
      throw const FormatException('Not a finite number');
    }

    return value;
  }
}
