import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/todo_app.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

class TodoWorld extends ScenarioWorld {
  final WidgetTester tester;
  final TodoController controller;
  final TodoBindings bindings;

  TodoWorld({
    required this.tester,
    required this.controller,
    required this.bindings,
  });
}

class TodoFlutterDriver
    extends BindingDrivenFlutterScenarioDriver<TodoWorld, FlutterBindingKey>
    with FeatTodo001BindingDrivenFlutterDriver<TodoWorld, FlutterBindingKey> {
  const TodoFlutterDriver();

  @override
  WidgetTester testerFor(TodoWorld world) => world.tester;

  @override
  FeatTodo001FlutterBindings<FlutterBindingKey> bindingsFor(TodoWorld world) =>
      world.bindings;

  @override
  Widget buildRoot(TodoWorld world) =>
      TodoScreen(controller: world.controller, bindings: world.bindings);
}
