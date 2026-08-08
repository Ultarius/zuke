import 'package:zuke/runner.dart';
import 'package:test/test.dart';

void main() {
  group('CucumberExpression', () {
    test(
      'transforms quoted strings and preserves embedded escaped quotes',
      () async {
        final expression = CucumberExpression(
          'the user enters {string}',
          StepParameterTypeRegistry.standard(),
        );

        final match = expression.pattern.firstMatch(
          r'the user enters "say \"hello\""',
        );

        expect(match, isNotNull);
        expect(await expression.transform(match!), ['say "hello"']);
      },
    );

    test('transforms signed integers and scientific doubles', () async {
      final registry = StepParameterTypeRegistry.standard();
      final expression = CucumberExpression(
        'values {int} and {double}',
        registry,
      );

      final match = expression.pattern.firstMatch('values -42 and 6.02e23');

      expect(match, isNotNull);
      expect(await expression.transform(match!), [-42, 6.02e23]);
    });

    test('supports asynchronous custom transformations', () async {
      final registry = StepParameterTypeRegistry.standard()
        ..define<int>(
          StepParameterType(
            name: 'doubled',
            expressions: [RegExp(r'^x(\d+)$')],
            transform: (captures) async => int.parse(captures.single!) * 2,
          ),
        );
      final expression = CucumberExpression('count {doubled}', registry);

      final match = expression.pattern.firstMatch('count x21');

      expect(match, isNotNull);
      expect(await expression.transform(match!), [42]);
    });

    test('rejects unknown parameter types', () {
      expect(
        () => CucumberExpression(
          'an unsupported {thing}',
          StepParameterTypeRegistry.standard(),
        ),
        throwsArgumentError,
      );
    });

    test('matches Unicode operator literals exactly', () {
      final registry = StepParameterTypeRegistry.standard();

      expect(
        CucumberExpression(
          'the selected operator is "×"',
          registry,
        ).pattern.hasMatch('the selected operator is "×"'),
        isTrue,
      );
      expect(
        CucumberExpression(
          'the selected operator is "÷"',
          registry,
        ).pattern.hasMatch('the selected operator is "÷"'),
        isTrue,
      );
    });
  });

  group('structural step arguments', () {
    test('provides deterministic table projections', () {
      const table = StepDataTable([
        ['name', 'email'],
        ['Ada', 'ada@example.com'],
      ]);

      expect(table.asList(), ['name', 'email', 'Ada', 'ada@example.com']);
      expect(table.asMaps(), [
        {'name': 'Ada', 'email': 'ada@example.com'},
      ]);
    });
  });
}
