import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/todo_app.dart';

void main() {
  group('TodoController', () {
    test('rejects empty task text', () {
      final ctrl = TodoController();
      expect(ctrl.addTask(''), isFalse);
      expect(ctrl.errorMessage, 'Task text cannot be empty');
      expect(ctrl.addTask('   '), isFalse);
      expect(ctrl.tasks, isEmpty);
    });

    test('adds tasks and tracks active count', () {
      final ctrl = TodoController();
      expect(ctrl.addTask('Buy groceries'), isTrue);
      expect(ctrl.tasks.length, 1);
      expect(ctrl.tasks.first.text, 'Buy groceries');
      expect(ctrl.activeTaskCount, 1);
    });

    test('toggles task completion', () {
      final ctrl = TodoController();
      ctrl.addTask('Buy groceries');
      final taskId = ctrl.tasks.first.id;
      ctrl.toggleTask(taskId);
      expect(ctrl.tasks.first.isCompleted, isTrue);
      expect(ctrl.activeTaskCount, 0);
    });

    test('clears completed tasks', () {
      final ctrl = TodoController();
      ctrl.addTask('Task 1');
      ctrl.addTask('Task 2');
      ctrl.toggleTask(ctrl.tasks.first.id);
      ctrl.clearCompleted();
      expect(ctrl.tasks.length, 1);
      expect(ctrl.tasks.first.text, 'Task 2');
    });
  });
}
