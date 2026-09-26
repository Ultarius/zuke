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

    // Arrange and guard steps read the domain state, which is what "the todo
    // list" means; interactions and observable assertions go through the widget
    // tree, so a Then step observes exactly what the user sees.
    TodoItemModel singleTask(TodoWorld world, String taskText) {
      final matches = world.controller.tasks
          .where((task) => task.text == taskText)
          .toList();
      if (matches.length != 1) {
        throw StateError(
          'Expected exactly one task named "$taskText" in the todo list, '
          'found ${matches.length}.',
        );
      }
      return matches.single;
    }

    bool isComplete(TodoWorld world, String taskText) =>
        singleTask(world, taskText).isCompleted;

    Finder taskCheckbox(TodoWorld world, String taskText) {
      final rows = find.ancestor(
        of: find.text(taskText),
        matching: find.byType(ListTile),
      );
      final rowCount = rows.evaluate().length;
      if (rowCount != 1) {
        throw StateError(
          'Expected exactly one task named "$taskText" on screen, '
          'found $rowCount.',
        );
      }
      final checkbox = find.descendant(
        of: rows,
        matching: findFlutterBinding(world.bindings.taskItemCheckbox),
      );
      final checkboxCount = checkbox.evaluate().length;
      if (checkboxCount != 1) {
        throw StateError(
          'Expected one checkbox for task "$taskText", found $checkboxCount.',
        );
      }
      return checkbox;
    }

    bool checkboxIsChecked(TodoWorld world, String taskText) =>
        world.tester.widget<Checkbox>(taskCheckbox(world, taskText)).value ??
        false;

    Future<void> tapTaskCheckbox(TodoWorld world, String taskText) async {
      await world.tester.tap(taskCheckbox(world, taskText));
      await driver.pumpAndSettle(world);
    }

    /// Establishes completion in the controller rather than by driving the
    /// widget under test, so a broken checkbox cannot fail an arrange step.
    Future<void> markComplete(TodoWorld world, String taskText) async {
      final task = singleTask(world, taskText);
      if (task.isCompleted) return;
      world.controller.toggleTask(task.id);
      await driver.pumpAndSettle(world);
    }

    return buildStepRegistry([
      ...const FeatTodo001GeneratedSteps<TodoWorld>().build(
        theTodoApplicationIsOpen: driver.open,
        theTodoListContainsTask: (world, taskText) async {
          if (world.controller.tasks.any((task) => task.text == taskText)) {
            // Arrange steps stay idempotent so a rerun or `--retest` cannot
            // fail because the state is already established.
            return;
          }
          await driver.enterTaskInput(world, taskText);
          await driver.tapAddTaskButton(world);
          singleTask(world, taskText);
        },
        taskIsComplete: (world, taskText) async {
          await markComplete(world, taskText);
          if (!checkboxIsChecked(world, taskText)) {
            throw StateError('Expected task "$taskText" to be complete.');
          }
        },
        theUserMarksTaskAsComplete: (world, taskText) async {
          if (isComplete(world, taskText)) {
            throw StateError('Task "$taskText" is already complete.');
          }
          await tapTaskCheckbox(world, taskText);
          if (!checkboxIsChecked(world, taskText)) {
            throw StateError(
              'Expected task "$taskText" to be marked as complete.',
            );
          }
        },
        theUserReopensTask: (world, taskText) async {
          if (!isComplete(world, taskText)) {
            throw StateError('Task "$taskText" is not complete.');
          }
          await tapTaskCheckbox(world, taskText);
          if (checkboxIsChecked(world, taskText)) {
            throw StateError('Expected task "$taskText" to be reopened.');
          }
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
