// GENERATED. DO NOT EDIT.
// Source: FEAT-TODO-001 (specs/features/todo.feature)

import 'package:zuke_annotations/zuke_annotations.dart';

sealed class FeatTodo001FlutterBinding implements ZukeBindingDescriptor {
  const FeatTodo001FlutterBinding(this.id);
  @override
  final String id;

  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings);

  static const taskInput = FeatTodo001TaskInputBinding();
  static const addTaskButton = FeatTodo001AddTaskButtonBinding();
  static const taskItemCheckbox = FeatTodo001TaskItemCheckboxBinding();
  static const clearCompletedButton = FeatTodo001ClearCompletedButtonBinding();
  static const taskCountDisplay = FeatTodo001TaskCountDisplayBinding();
  static const emptyStateMessage = FeatTodo001EmptyStateMessageBinding();
  static const errorMessage = FeatTodo001ErrorMessageBinding();
  static const taskList = FeatTodo001TaskListBinding();
  static const taskItemText = FeatTodo001TaskItemTextBinding();

  static FeatTodo001FlutterBinding fromId(String bindingId) =>
      switch (bindingId) {
        'todo.taskInput' => taskInput,
        'todo.addTaskButton' => addTaskButton,
        'todo.taskItemCheckbox' => taskItemCheckbox,
        'todo.clearCompletedButton' => clearCompletedButton,
        'todo.taskCountDisplay' => taskCountDisplay,
        'todo.emptyStateMessage' => emptyStateMessage,
        'todo.errorMessage' => errorMessage,
        'todo.taskList' => taskList,
        'todo.taskItemText' => taskItemText,
        _ => throw ArgumentError.value(
          bindingId,
          'bindingId',
          'Unknown Flutter binding for FEAT-TODO-001',
        ),
      };
}

final class FeatTodo001TaskInputBinding extends FeatTodo001FlutterBinding {
  const FeatTodo001TaskInputBinding() : super('todo.taskInput');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.taskInput;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatTodo001AddTaskButtonBinding extends FeatTodo001FlutterBinding {
  const FeatTodo001AddTaskButtonBinding() : super('todo.addTaskButton');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.addTaskButton;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatTodo001TaskItemCheckboxBinding
    extends FeatTodo001FlutterBinding {
  const FeatTodo001TaskItemCheckboxBinding() : super('todo.taskItemCheckbox');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.taskItemCheckbox;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.many;
}

final class FeatTodo001ClearCompletedButtonBinding
    extends FeatTodo001FlutterBinding {
  const FeatTodo001ClearCompletedButtonBinding()
    : super('todo.clearCompletedButton');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.clearCompletedButton;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatTodo001TaskCountDisplayBinding
    extends FeatTodo001FlutterBinding {
  const FeatTodo001TaskCountDisplayBinding() : super('todo.taskCountDisplay');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.taskCountDisplay;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatTodo001EmptyStateMessageBinding
    extends FeatTodo001FlutterBinding {
  const FeatTodo001EmptyStateMessageBinding() : super('todo.emptyStateMessage');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.emptyStateMessage;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

final class FeatTodo001ErrorMessageBinding extends FeatTodo001FlutterBinding {
  const FeatTodo001ErrorMessageBinding() : super('todo.errorMessage');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.errorMessage;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

final class FeatTodo001TaskListBinding extends FeatTodo001FlutterBinding {
  const FeatTodo001TaskListBinding() : super('todo.taskList');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.taskList;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatTodo001TaskItemTextBinding extends FeatTodo001FlutterBinding {
  const FeatTodo001TaskItemTextBinding() : super('todo.taskItemText');

  @override
  T keyIn<T extends Object>(FeatTodo001FlutterBindings<T> bindings) =>
      bindings.taskItemText;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.many;
}

abstract interface class FeatTodo001FlutterBindings<T extends Object> {
  T get taskInput;
  T get addTaskButton;
  T get taskItemCheckbox;
  T get clearCompletedButton;
  T get taskCountDisplay;
  T get emptyStateMessage;
  T get errorMessage;
  T get taskList;
  T get taskItemText;
}

mixin FeatTodo001BindingDrivenFlutterDriver<W, T extends Object>
    implements FeatTodo001FlutterDriver<W> {
  FeatTodo001FlutterBindings<T> bindingsFor(W world);
  Future<void> zukeEnterBinding(W world, T key, String value);
  Future<void> zukeTapBinding(W world, T key);
  Future<String?> zukeReadBinding(W world, T key);
  Future<void> zukeEnterBindingInstance(
    W world,
    T key,
    Object instanceId,
    String value,
  );
  Future<void> zukeTapBindingInstance(W world, T key, Object instanceId);
  Future<String?> zukeReadBindingInstance(W world, T key, Object instanceId);
  Future<List<String>> zukeReadAllBindings(W world, T key);
  @override
  Future<void> enterTaskInput(W world, String value) =>
      zukeEnterBinding(world, bindingsFor(world).taskInput, value);
  @override
  Future<void> tapAddTaskButton(W world) =>
      zukeTapBinding(world, bindingsFor(world).addTaskButton);
  @override
  Future<void> tapTaskItemCheckbox(W world, Object instanceId) =>
      zukeTapBindingInstance(
        world,
        bindingsFor(world).taskItemCheckbox,
        instanceId,
      );
  @override
  Future<void> tapClearCompletedButton(W world) =>
      zukeTapBinding(world, bindingsFor(world).clearCompletedButton);
  @override
  Future<String?> readTaskCountDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).taskCountDisplay);
  @override
  Future<String?> readEmptyStateMessage(W world) =>
      zukeReadBinding(world, bindingsFor(world).emptyStateMessage);
  @override
  Future<String?> readErrorMessage(W world) =>
      zukeReadBinding(world, bindingsFor(world).errorMessage);
  @override
  Future<String?> readTaskList(W world) =>
      zukeReadBinding(world, bindingsFor(world).taskList);
  @override
  Future<String?> readTaskItemText(W world, Object instanceId) =>
      zukeReadBindingInstance(
        world,
        bindingsFor(world).taskItemText,
        instanceId,
      );
  @override
  Future<List<String>> readAllTaskItemText(W world) =>
      zukeReadAllBindings(world, bindingsFor(world).taskItemText);
}

abstract interface class FeatTodo001FlutterDriver<W> {
  Future<void> enterTaskInput(W world, String value);
  Future<void> tapAddTaskButton(W world);
  Future<void> tapTaskItemCheckbox(W world, Object instanceId);
  Future<void> tapClearCompletedButton(W world);
  Future<String?> readTaskCountDisplay(W world);
  Future<String?> readEmptyStateMessage(W world);
  Future<String?> readErrorMessage(W world);
  Future<String?> readTaskList(W world);
  Future<String?> readTaskItemText(W world, Object instanceId);
  Future<List<String>> readAllTaskItemText(W world);
}

abstract final class FeatTodo001RequirementIds {
  static const addItem = 'RULE-TODO-ADD-ITEM';
  static const addItemId = RuleId('RULE-TODO-ADD-ITEM');
  static const completeItem = 'RULE-TODO-COMPLETE-ITEM';
  static const completeItemId = RuleId('RULE-TODO-COMPLETE-ITEM');
}

abstract final class FeatTodo001ControlIds {
  static const validation = ControlId('CTRL-TODO-VALIDATION');
}

enum FeatTodo001Scenario implements ZukeScenarioContract {
  addItem(
    ScenarioId('SCN-TODO-ADD-ITEM'),
    RuleId('RULE-TODO-ADD-ITEM'),
    'Add a new task to the todo list',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  ),
  addEmpty(
    ScenarioId('SCN-TODO-ADD-EMPTY'),
    RuleId('RULE-TODO-ADD-ITEM'),
    'Reject adding an empty task',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  ),
  addWhitespace(
    ScenarioId('SCN-TODO-ADD-WHITESPACE'),
    RuleId('RULE-TODO-ADD-ITEM'),
    'Reject adding a whitespace-only task',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  ),
  multiTasks(
    ScenarioId('SCN-TODO-MULTI-TASKS'),
    RuleId('RULE-TODO-ADD-ITEM'),
    'Track counts across multiple tasks',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  ),
  completeItem(
    ScenarioId('SCN-TODO-COMPLETE-ITEM'),
    RuleId('RULE-TODO-COMPLETE-ITEM'),
    'Mark a task as complete',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  ),
  toggleBack(
    ScenarioId('SCN-TODO-TOGGLE-BACK'),
    RuleId('RULE-TODO-COMPLETE-ITEM'),
    'Reopen a completed task',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  ),
  clearCompleted(
    ScenarioId('SCN-TODO-CLEAR-COMPLETED'),
    RuleId('RULE-TODO-COMPLETE-ITEM'),
    'Clear all completed tasks',
    <ControlId>{ControlId('CTRL-TODO-VALIDATION')},
  );

  const FeatTodo001Scenario(
    this.id,
    this.requirementId,
    this.title,
    this.controlIds,
  );
  @override
  final ScenarioId id;
  @override
  final RuleId requirementId;
  @override
  final String title;
  @override
  final Set<ControlId> controlIds;
}

abstract final class FeatTodo001Scenarios {
  static const all = FeatTodo001Scenario.values;
  static final Map<ScenarioId, FeatTodo001Scenario>
  byId = Map.unmodifiable(<ScenarioId, FeatTodo001Scenario>{
    ScenarioId('SCN-TODO-ADD-ITEM'): FeatTodo001Scenario.addItem,
    ScenarioId('SCN-TODO-ADD-EMPTY'): FeatTodo001Scenario.addEmpty,
    ScenarioId('SCN-TODO-ADD-WHITESPACE'): FeatTodo001Scenario.addWhitespace,
    ScenarioId('SCN-TODO-MULTI-TASKS'): FeatTodo001Scenario.multiTasks,
    ScenarioId('SCN-TODO-COMPLETE-ITEM'): FeatTodo001Scenario.completeItem,
    ScenarioId('SCN-TODO-TOGGLE-BACK'): FeatTodo001Scenario.toggleBack,
    ScenarioId('SCN-TODO-CLEAR-COMPLETED'): FeatTodo001Scenario.clearCompleted,
  });
  static final Map<String, List<FeatTodo001Scenario>> byRule = Map.unmodifiable(
    <String, List<FeatTodo001Scenario>>{
      'RULE-TODO-ADD-ITEM': List.unmodifiable(<FeatTodo001Scenario>[
        FeatTodo001Scenario.addItem,
        FeatTodo001Scenario.addEmpty,
        FeatTodo001Scenario.addWhitespace,
        FeatTodo001Scenario.multiTasks,
      ]),
      'RULE-TODO-COMPLETE-ITEM': List.unmodifiable(<FeatTodo001Scenario>[
        FeatTodo001Scenario.completeItem,
        FeatTodo001Scenario.toggleBack,
        FeatTodo001Scenario.clearCompleted,
      ]),
    },
  );
  static List<FeatTodo001Scenario> matching(ZukeScenarioPattern pattern) =>
      all.where(pattern.matches).toList(growable: false);
}

abstract final class AddItemScenarios {
  static const addItem = FeatTodo001Scenario.addItem;
  static const addEmpty = FeatTodo001Scenario.addEmpty;
  static const addWhitespace = FeatTodo001Scenario.addWhitespace;
  static const multiTasks = FeatTodo001Scenario.multiTasks;
  static const all = <ZukeScenarioContract>[
    FeatTodo001Scenario.addItem,
    FeatTodo001Scenario.addEmpty,
    FeatTodo001Scenario.addWhitespace,
    FeatTodo001Scenario.multiTasks,
  ];
}

abstract final class CompleteItemScenarios {
  static const completeItem = FeatTodo001Scenario.completeItem;
  static const toggleBack = FeatTodo001Scenario.toggleBack;
  static const clearCompleted = FeatTodo001Scenario.clearCompleted;
  static const all = <ZukeScenarioContract>[
    FeatTodo001Scenario.completeItem,
    FeatTodo001Scenario.toggleBack,
    FeatTodo001Scenario.clearCompleted,
  ];
}
