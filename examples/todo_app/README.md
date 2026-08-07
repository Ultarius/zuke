# Zuke Todo App Example 🟢 (Beginner)

This is the **primary getting-started reference** for Zuke. It demonstrates a
complete, easy-to-understand Flutter BDD setup with generated contracts,
widget bindings, and Gherkin scenarios.

This beginner example intentionally keeps release signing and Dart build-hook
enforcement disabled. Those production concerns are introduced by the
Shopping Cart and Calculator examples after the core specification workflow is
understood. Its `release` profile is cumulative (`@pr or @merge or @release`)
and demonstrates profile selection rather than a signed release process.

---

## What This Example Demonstrates

1. **Gherkin Feature Specifications**: Written in `specs/features/todo.feature`.
2. **Contract Generation**: Automatically generates strongly-typed Dart contracts in `lib/src/generated/feat_todo_001_contracts.g.dart`.
3. **UI Key Wiring**: Uses `@ZukeBinding` and `FlutterBindings<Key>` to bind Flutter widgets (`lib/src/todo_screen.dart`) directly to requirements.
4. **State & Control Validation**: Annotates business logic in `lib/src/todo_controller.dart` with `@PresentsRequirement` and `@ProvidesControl`.
5. **Widget & Unit Testing**: Integrates standard `flutter_test` with Zuke `ScenarioExecutor` in `test/todo_widget_test.dart`.

---

## Quick Start: How to Run

From this directory (`examples/todo_app`):

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Check environment configuration
dart run zuke_cli:zuke doctor

# 3. Generate typed contracts from Gherkin feature files
dart run zuke_cli:zuke generate

# 4. Analyze code without re-fetching pub
flutter analyze --no-pub

# 5. Run widget and scenario tests with Zuke runner
dart run zuke_cli:zuke test --profile pullRequest

# 6. Validate evidence and control proofs
dart run zuke_cli:zuke validate --profile pullRequest

# 7. Check lockfile integrity
dart run zuke_cli:zuke lock --profile pullRequest --check

# 8. Run the complete pull-request gate
dart run zuke_cli:zuke gate --profile pullRequest
```

Alternatively, from the repository root, run the entire workspace test suite:
```bash
dart run --suppress-analytics melos run zuke:check
```

## Generated Traceability

Zuke derives rule, scenario, and evidence relationships from the feature
model rather than maintaining a second table in this README:

```bash
dart run zuke_cli:zuke report
dart run zuke_cli:zuke trace RULE-TODO-ADD-ITEM
```

The JSON model at `generated/report/zuke-model.json` is an ignored CI artifact;
`trace` is the concise human-readable view for an individual rule.

---

## Step-by-Step BDD Development Workflow

When adding new features or scenarios to your application:

### Step 1: Write Gherkin Feature
Add a new scenario or step to `specs/features/todo.feature`:
```gherkin
  Scenario: Filter completed tasks
    Given the user opens the todo app
    When the user filters by "Completed"
    Then only completed tasks are visible
```

### Step 2: Generate Contracts
Run `dart run zuke_cli:zuke generate`. This parses your feature files and generates Dart abstract interfaces and widget keys in `lib/src/generated/`.

### Step 3: Bind UI Widgets
Assign generated key constants to Flutter widgets using `@ZukeBinding`:
```dart
ElevatedButton(
  key: FeatTodo001Keys.filterCompletedButton,
  onPressed: () => controller.filterCompleted(),
  child: const Text('Filter Completed'),
)
```

### Step 4: Implement Step Definitions & Drivers
Register step definition callbacks or implement driver methods in `test/todo_widget_test.dart`:
```dart
steps.register('the user filters by {string}', (tester, match) async {
  final filterType = match.group(1)!;
  await tester.tap(find.byKey(FeatTodo001Keys.filterCompletedButton));
  await tester.pumpAndSettle();
});
```

### Step 5: Execute & Verify Gate
Run `dart run zuke_cli:zuke test --profile pullRequest`, followed by
`validate` and `lock --profile pullRequest`, to refresh evidence and the derived
lock. Then run `gate --profile pullRequest` to verify that generation, evidence,
and lock state are current without rewriting them.
