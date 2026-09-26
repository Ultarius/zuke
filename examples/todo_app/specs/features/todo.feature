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
#       label: task input field
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: todo.addTaskButton
#       label: add task button
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: todo.taskItemCheckbox
#       label: task completion checkbox
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrMore
#       interaction: action
#     - id: todo.clearCompletedButton
#       label: clear completed button
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: todo.taskCountDisplay
#       label: active task count
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: todo.emptyStateMessage
#       label: empty list message
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: todo.errorMessage
#       label: error message
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: todo.taskList
#       label: task list
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: todo.taskItemText
#       label: task text
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
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: todo-app, sourceAdapter: dart-source, variant: default}]
  # securityProfile: todo-validation-profile
  # rule-spec-end
  @RULE-TODO-ADD-ITEM
  Rule: Add tasks to the todo list

    @SCN-TODO-ADD-ITEM @pr @merge @release
    Scenario: Add a new task to the todo list
      When the user enters "Buy groceries" into "task input field"
      And the user taps "add task button"
      Then element "active task count" displays "1 item left"
      And element "task text" displays "Buy groceries"

    @SCN-TODO-ADD-EMPTY @negative @pr @merge
    Scenario: Reject adding an empty task
      When the user enters "" into "task input field"
      And the user taps "add task button"
      Then element "error message" displays "Task text cannot be empty"
      And element "empty list message" displays "No tasks yet"

    @SCN-TODO-ADD-WHITESPACE @negative @pr @merge
    Scenario: Reject adding a whitespace-only task
      When the user enters 3 spaces into "task input field"
      And the user taps "add task button"
      Then element "error message" displays "Task text cannot be empty"
      And element "empty list message" displays "No tasks yet"

    @SCN-TODO-MULTI-TASKS @pr @merge
    Scenario: The active count reflects every task that is added
      When the user enters "Task A" into "task input field"
      And the user taps "add task button"
      And the user enters "Task B" into "task input field"
      And the user taps "add task button"
      Then element "active task count" displays "2 items left"
      And element "task text" displays "Task A"
      And element "task text" displays "Task B"

  # rule-spec-begin
  # id: RULE-TODO-COMPLETE-ITEM
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: todo-app, sourceAdapter: dart-source, variant: default}]
  # securityProfile: todo-validation-profile
  # rule-spec-end
  @RULE-TODO-COMPLETE-ITEM
  Rule: Mark tasks as complete

    @SCN-TODO-COMPLETE-ITEM @pr @merge
    Scenario: Mark a task as complete
      Given the todo list contains task "Buy groceries"
      When the user marks task "Buy groceries" as complete
      Then element "active task count" displays "0 items left"

    @SCN-TODO-COMPLETE-COUNT @pr @merge
    Scenario: Completing one task lowers the active count by one
      Given the todo list contains task "Task A"
      And the todo list contains task "Task B"
      When the user marks task "Task A" as complete
      Then element "active task count" displays "1 item left"

    @SCN-TODO-TOGGLE-BACK @pr @merge
    Scenario: Reopening a completed task restores the active count
      Given the todo list contains task "Buy groceries"
      And task "Buy groceries" is complete
      When the user reopens task "Buy groceries"
      Then element "active task count" displays "1 item left"

    @SCN-TODO-CLEAR-COMPLETED @pr @merge
    Scenario: Clearing completed tasks removes them from the list
      Given the todo list contains task "Buy groceries"
      And task "Buy groceries" is complete
      When the user taps "clear completed button"
      Then element "empty list message" displays "No tasks yet"

    @SCN-TODO-CLEAR-KEEPS-INCOMPLETE @pr @merge
    Scenario: Clearing completed tasks keeps the uncompleted tasks
      Given the todo list contains task "Task A"
      And the todo list contains task "Task B"
      And task "Task A" is complete
      When the user taps "clear completed button"
      Then element "task text" displays "Task B"
      And element "active task count" displays "1 item left"
