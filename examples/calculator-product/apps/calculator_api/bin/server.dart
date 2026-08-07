import 'dart:convert';
import 'package:calculator_api/calculator_api.dart';

Future<void> main() async {
  final server = CalculatorServer();
  await server.start();
  print(jsonEncode({'ready': true, 'port': server.port}));
  await Future<void>.delayed(const Duration(days: 3650));
}
