import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'generated/feat_todo_001_contracts.g.dart';

class TodoBindings implements FeatTodo001FlutterBindings<FlutterBindingKey> {
  @override
  @ZukeBinding('todo.taskInput')
  FlutterBindingKey get taskInput =>
      const FlutterBindingKey.single('todo.taskInput');

  @override
  @ZukeBinding('todo.addTaskButton')
  FlutterBindingKey get addTaskButton =>
      const FlutterBindingKey.single('todo.addTaskButton');

  @override
  @ZukeBinding('todo.taskItemCheckbox')
  FlutterBindingKey get taskItemCheckbox =>
      const FlutterBindingKey.collection('todo.taskItemCheckbox');

  @override
  @ZukeBinding('todo.clearCompletedButton')
  FlutterBindingKey get clearCompletedButton =>
      const FlutterBindingKey.single('todo.clearCompletedButton');

  @override
  @ZukeBinding('todo.taskCountDisplay')
  FlutterBindingKey get taskCountDisplay =>
      const FlutterBindingKey.single('todo.taskCountDisplay');

  @override
  @ZukeBinding('todo.emptyStateMessage')
  FlutterBindingKey get emptyStateMessage =>
      const FlutterBindingKey.single('todo.emptyStateMessage');

  @override
  @ZukeBinding('todo.errorMessage')
  FlutterBindingKey get errorMessage =>
      const FlutterBindingKey.single('todo.errorMessage');

  @override
  @ZukeBinding('todo.taskList')
  FlutterBindingKey get taskList =>
      const FlutterBindingKey.single('todo.taskList');

  @override
  @ZukeBinding('todo.taskItemText')
  FlutterBindingKey get taskItemText =>
      const FlutterBindingKey.collection('todo.taskItemText');
}
