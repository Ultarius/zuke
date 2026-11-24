import 'package:test/test.dart';
import 'package:zuke/src/step_arguments.dart';

void main() {
  final expression = CucumberExpression(
    'the value is {string}',
    StepParameterTypeRegistry.standard(),
  );

  Future<Object?> valueOf(String text) async {
    final match = expression.pattern.firstMatch(text);
    expect(match, isNotNull, reason: text);
    return (await expression.transform(match!)).single;
  }

  test('passes single-quoted text through', () async {
    expect(await valueOf("the value is 'abc'"), 'abc');
  });

  test('passes double-quoted and empty text through', () async {
    expect(await valueOf('the value is "abc"'), 'abc');
    expect(await valueOf('the value is ""'), '');
    expect(await valueOf("the value is ''"), '');
  });

  test('keeps a value ending in a literal backslash', () async {
    expect(await valueOf(r'the value is "C:\temp\"'), r'C:\temp\');
    expect(await valueOf(r"the value is 'C:\temp\'"), r'C:\temp\');
  });

  test('still reads an escaped quote inside a value', () async {
    expect(await valueOf(r'the value is "say \"hi\""'), 'say "hi"');
    expect(await valueOf(r"the value is 'it\'s'"), "it's");
  });

  test('a trailing backslash does not swallow the next parameter', () async {
    final pair = CucumberExpression(
      'at {string} contains {string}',
      StepParameterTypeRegistry.standard(),
    );
    final match = pair.pattern.firstMatch(r'at "a\" contains "b"');
    expect(match, isNotNull);
    expect(await pair.transform(match!), [r'a\', 'b']);
  });
}
