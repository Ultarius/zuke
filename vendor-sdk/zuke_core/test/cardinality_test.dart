import 'package:zuke_core/src/internal_ir.dart';
import 'package:test/test.dart';

void main() {
  test('parses zeroOrMore as many', () {
    expect(Cardinality.parse('zeroOrMore'), same(Cardinality.many));
  });
}
