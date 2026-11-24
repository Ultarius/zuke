# Evidence declarations

Some projects attach metadata to each rule naming the kinds of evidence allowed to prove it: domain (`unit`), UI (`widget`, `e2e`), integration (`api`). The type names come from the project's configuration. The declaration is the gate's **field of view**: only evidence of a declared kind counts, and everything else is invisible to it. This is the audit for rule 17.

## Two questions per scenario

Ask both of every scenario in the rule. They are independent; one rule may need several slots.

1. **Event path.** Is the `When` performed through a surface the user operates? Then the rule needs a **UI slot**. Without one, a missing control stays invisible.
2. **Artifact.** Does a `Then` assert something that can be wrong while every screen looks right: a saved file, a written or rendered output, a log payload, an external response? Then the rule needs a **domain or integration slot**.

A **mirrored state** is not an artifact. Playing, paused, a marked range, a selected value: the screen shows it, so the UI slot already observes it.

## Find candidates

```text
UI-layer words   \b(user|customer|actor)\b.*\b(selects?|chooses?|opens?|enables?|enters?|types?|presses?|taps?|views?|sees?)\b
Artifact words   \b(saved|written|file|on disk|rendered|exported|log(ged)?|payload|sent to|received by|remembered|persisted|unchanged)\b
```

For each hit, open the owning rule's declaration. UI wording under a declaration with no UI type, or artifact wording under a UI-only declaration, is a mismatch.

Judge what a slot observes from the bindings and their registered evidence kinds — the tests under `test/`, the step definitions, or the runner configuration — not from stale evidence artifacts. A generated record can predate the last test run and misreport which kinds exist.

## Mismatches

- **Too narrow.** A user journey ("the user selects another output device", "the user enters an API key in settings") under a domain-only declaration. Domain tests satisfy the gate while the screen may not exist.
- **UI-only with an artifact.** "the saved project file is unchanged" under a UI-only declaration. The screen can look right while the file is wrong.
- **Padded.** A UI slot on a pure domain contract, or a domain slot on a UI-only rule with no artifact. It forces tests onto a layer that owns no behavior.
- **Unbound slot.** The scenarios need the layer and the declaration correctly lists it, but no binding emits evidence of that kind yet: the rule declares `flutter-widget` while every registered test is `unit`, or the reverse. The declaration is not the defect — deleting the slot to make the gate pass would hide the very gap the audit exists to find. Keep the slot, and record the missing binding as a product gap with the scenario ids it covers; add the binding at the declared layer to close it.

Too narrow is the specification-level twin of borrowed coverage: no test body looks wrong, because no test was ever able to look.

## Fix

- Declare one slot per layer the rule's scenarios observe. Adding a UI slot keeps the existing domain slot.
- When one scenario belongs to another layer, either add the slot or move the scenario to a rule that already observes that layer.
- Copy each slot's type name and identity fields from a sibling rule in the same project; the values are the tooling's, not yours to invent.

## Example

```gherkin
# Before: a user journey under a domain-only declaration
# rule-spec-begin
# id: RULE-DEVICE-001
# requiredEvidence:
#   - type: unit
# rule-spec-end
@RULE-DEVICE-001
Rule: Audio device configuration applies to the running engine

  @SCN-DEVICE-001
  Scenario: The engine runs on the selected device
    Given at least two output devices are available
    When the user selects another output device
    Then the selected device is the active output
```

Question 1 is yes (the user selects), question 2 is no (the active output is mirrored on screen). The rule needs a UI slot; the domain slot stays for the rule's domain scenarios.

```gherkin
# After: one slot per observed layer (identity fields copied from a sibling rule)
# rule-spec-begin
# id: RULE-DEVICE-001
# requiredEvidence:
#   - type: unit
#     target: app
#     sourcePackage: app
#     sourceAdapter: dart-source
#     variant: default
#   - type: flutter-widget
#     target: app
#     sourcePackage: app
#     sourceAdapter: dart-source
#     variant: default
# rule-spec-end
```

## Done

Each rule has a row: scenario, the answer to both questions, and the slot that observes it. No scenario has a layer with no slot, and no slot lacks a scenario that needs it. A slot whose scenarios have no binding yet is reported as an unbound slot with the affected ids — never resolved by removing the slot.
