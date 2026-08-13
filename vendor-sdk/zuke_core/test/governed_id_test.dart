import 'package:zuke_core/zuke_core.dart';
import 'package:test/test.dart';

void main() {
  group('Governed ID Types', () {
    test('RuleId and ControlId accept only canonical governed IDs', () {
      expect(
        RuleId.parse('RULE-CART-PROMO-DISCOUNT').value,
        'RULE-CART-PROMO-DISCOUNT',
      );
      expect(
        ControlId.parse('CTRL-PROMO-VALIDATION').value,
        'CTRL-PROMO-VALIDATION',
      );
      expect(RuleId.tryParse('RULE-Cart-PROMO'), isNull);
      expect(ControlId.tryParse('CTRL_PROMO_VALIDATION'), isNull);
    });

    test(
      'ScenarioId accepts valid canonical SCN IDs and rejects invalid ones',
      () {
        expect(
          ScenarioId.parse('SCN-CART-ADD-ITEM').value,
          'SCN-CART-ADD-ITEM',
        );
        expect(ScenarioId.tryParse('SCN-cart-add-item'), isNull);
        expect(ScenarioId.tryParse('SCN_CART_ADD_ITEM'), isNull);
        expect(ScenarioId.tryParse('SCN-CART-'), isNull);
        expect(ScenarioId.tryParse(''), isNull);
      },
    );

    test('ControlId.tryParse returns ControlId instance', () {
      final control = ControlId.tryParse('CTRL-CALC-ERROR-REDACTION');
      expect(control, isA<ControlId>());
      expect(control?.value, 'CTRL-CALC-ERROR-REDACTION');
    });

    test('Equality and comparison work across all ID types', () {
      const scenario1 = ScenarioId('SCN-CART-ADD-ITEM');
      const scenario2 = ScenarioId('SCN-CART-ADD-ITEM');
      const scenario3 = ScenarioId('SCN-CART-APPLY-PROMO');

      expect(scenario1, equals(scenario2));
      expect(scenario1.hashCode, equals(scenario2.hashCode));
      expect(scenario1, isNot(equals(scenario3)));
      expect(scenario1.toString(), 'SCN-CART-ADD-ITEM');
      expect(scenario1.compareTo(scenario3), lessThan(0));

      const rule1 = RuleId('RULE-CART-ITEM-MANAGEMENT');
      const rule2 = RuleId('RULE-CART-ITEM-MANAGEMENT');
      expect(rule1, equals(rule2));
      expect(rule1.toString(), 'RULE-CART-ITEM-MANAGEMENT');

      const control1 = ControlId('CTRL-CART-SEMANTICS');
      const control2 = ControlId('CTRL-CART-SEMANTICS');
      expect(control1, equals(control2));
      expect(control1.toString(), 'CTRL-CART-SEMANTICS');
    });

    test('Parsers reject empty governed identifiers', () {
      expect(() => ScenarioId(''), throwsA(isA<AssertionError>()));
      expect(() => RuleId(''), throwsA(isA<AssertionError>()));
      expect(() => ControlId.parse(''), throwsA(isA<FormatException>()));
    });
  });
}
