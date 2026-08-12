# spec-begin
# schemaVersion: 1
# id: FEAT-TODO-001
# epic: EPIC-TODO-001
# owner: todo-team
# status: active
# targets:
#   - flutter
# pbis:
#   - PBI-TODO-001
# bindings:
#   required:
#     - id: todo.taskInput
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: todo.addTaskButton
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: todo.taskItemCheckbox
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrMore
#       interaction: action
#     - id: todo.clearCompletedButton
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: todo.taskCountDisplay
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: todo.emptyStateMessage
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: todo.errorMessage
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: todo.taskList
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: todo.taskItemText
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrMore
#       interaction: output
# spec-end

@EPIC-TODO-001 @FEAT-TODO-001
Feature: Todo List Application
  As a task manager user
  I want to add tasks, toggle completion states, and clear finished tasks
  So that I can maintain an organized list of pending activities.

  The Flutter UI presents task entry, active count displays, completion checkboxes, and clear-completed actions.

  Background:
    Given the todo application is open

  # rule-spec-begin
  # id: RULE-TODO-ADD-ITEM
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: todo-app, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: todo-validation-profile
  # rule-spec-end
  @RULE-TODO-ADD-ITEM
  Rule: Add tasks to the todo list

    @SCN-TODO-ADD-ITEM @pr @merge @release
    Scenario: Add a new task to the todo list
      When the user enters "Buy groceries" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      Then element "todo.taskCountDisplay" displays "1 item left"
      And element "todo.taskItemText" displays "Buy groceries"

    @SCN-TODO-ADD-EMPTY @negative @pr @merge
    Scenario: Reject adding an empty task
      When the user enters "" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      Then element "todo.errorMessage" displays "Task text cannot be empty"
      And element "todo.emptyStateMessage" displays "No tasks yet"

    @SCN-TODO-ADD-WHITESPACE @negative @pr @merge
    Scenario: Reject adding a whitespace-only task
      When the user enters 3 spaces into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      Then element "todo.errorMessage" displays "Task text cannot be empty"
      And element "todo.emptyStateMessage" displays "No tasks yet"

    @SCN-TODO-MULTI-TASKS @pr @merge
    Scenario: Track counts across multiple tasks
      When the user enters "Task A" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      And the user enters "Task B" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      Then element "todo.taskCountDisplay" displays "2 items left"
      When the user marks task "Task A" as complete
      Then element "todo.taskCountDisplay" displays "1 item left"
      When the user taps "todo.clearCompletedButton"
      Then element "todo.taskItemText" displays "Task B"

  # rule-spec-begin
  # id: RULE-TODO-COMPLETE-ITEM
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: todo-app, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: todo-validation-profile
  # rule-spec-end
  @RULE-TODO-COMPLETE-ITEM
  Rule: Mark tasks as complete

    @SCN-TODO-COMPLETE-ITEM @pr @merge
    Scenario: Mark a task as complete
      When the user enters "Buy groceries" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      And the user marks task "Buy groceries" as complete
      Then element "todo.taskCountDisplay" displays "0 items left"

    @SCN-TODO-TOGGLE-BACK @negative @pr @merge
    Scenario: Reopen a completed task
      When the user enters "Buy groceries" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      And the user marks task "Buy groceries" as complete
      And the user marks task "Buy groceries" as complete
      Then element "todo.taskCountDisplay" displays "1 item left"

    @SCN-TODO-CLEAR-COMPLETED @pr @merge
    Scenario: Clear all completed tasks
      When the user enters "Buy groceries" into "todo.taskInput"
      And the user taps "todo.addTaskButton"
      And the user marks task "Buy groceries" as complete
      And the user taps "todo.clearCompletedButton"
      Then element "todo.emptyStateMessage" displays "No tasks yet"
