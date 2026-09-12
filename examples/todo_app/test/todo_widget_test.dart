import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/main.dart' as app;
import 'package:todo_app/todo_app.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

import 'support/todo_driver.dart';
import 'support/generated/feat_todo_001_steps.g.dart';

void main() {
  final feature = ZukeFeatureLoader.load('todo.feature');

  StepRegistry<TodoWorld> registry() {
    final driver = const TodoFlutterDriver();
    return buildStepRegistry([
      ...const FeatTodo001GeneratedSteps<TodoWorld>().build(
        theTodoApplicationIsOpen: driver.open,
        theUserMarksTaskAsComplete: (world, taskText) async {
          final taskRows = find.ancestor(
            of: find.text(taskText),
            matching: find.byType(ListTile),
          );
          final rowCount = taskRows.evaluate().length;
          if (rowCount != 1) {
            throw StateError(
              'Expected exactly one task named "$taskText", found $rowCount.',
            );
          }
          final checkbox = find.descendant(
            of: taskRows,
            matching: findFlutterBinding(world.bindings.taskItemCheckbox),
          );
          final checkboxCount = checkbox.evaluate().length;
          if (checkboxCount != 1) {
            throw StateError(
              'Expected one checkbox for task "$taskText", found $checkboxCount.',
            );
          }
          await world.tester.tap(checkbox);
          await driver.pumpAndSettle(world);
        },
      ),
      ...flutterVendorSteps<TodoWorld, FeatTodo001FlutterBinding>(
        testerFor: (world) => world.tester,
        bindingFromId: FeatTodo001FlutterBinding.fromId,
        keyFor: (world, binding) => binding.keyIn(world.bindings),
      ),
    ]);
  }

  ZukeFlutterHarness<TodoWorld>(
    feature: feature,
    scenarios: FeatTodo001Scenarios.all,
    registryFactory: registry,
    worldFactory: (tester) => TodoWorld(
      tester: tester,
      controller: TodoController(),
      bindings: TodoBindings(),
    ),
    runnerId: 'todo-flutter-tests',
    runnerCompatibilityId: 'todo-flutter-runner-v1',
    digests: const {'runner': 'zuke-runner-flutter-v1'},
  ).registerAll();

  testWidgets('main launches application root', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(TodoScreen), findsOneWidget);
  });
}
