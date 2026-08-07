import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('Requirement IDs are defined', () {
    expect(FeatCalc001RequirementIds.addition, startsWith('RULE-'));
    expect(FeatCalc001RequirementIds.subtraction, startsWith('RULE-'));
  });

  test('Scenario IDs are defined', () {
    expect(AdditionScenarios.addIntegersUi.id.value, startsWith('SCN-'));
    expect(DivisionScenarios.divideZero.id.value, startsWith('SCN-'));
  });
}
