---
name: bdd-feature-files
description: 'Write, review, and refactor Gherkin feature files and step definitions for behavior-driven development. Use when creating or changing scenarios, reviewing Given/When/Then wording, choosing API or UI coverage, or spotting anti-patterns such as UI scripting, vague outcomes, hidden state, over-promising steps, and misleading example tables.'
---

# Writing good feature files

A feature file is an executable specification: concrete examples of how the system behaves, written in the language of the domain, and automated through step definitions. Product owners, testers, and developers read it; the test runner executes it. Write for the reader first. The step definitions carry the automation.

## When to use

- Writing a new `.feature` file or adding scenarios
- Reviewing or refactoring existing feature files
- Writing or changing the step definitions behind scenarios
- Answering "is this good BDD?" questions

## Core model

Every scenario is one example of one business rule.

| Part | Keyword | Describes | Must not contain |
|---|---|---|---|
| Context | `Given` | The state before the event | User interaction, navigation, clicks |
| Event | `When` | One action by a person **or** a system | Several unrelated actions, UI mechanics |
| Outcome | `Then` | A result the actor can observe | Internal state, vague adjectives |

**The actor is not always a person.** BDD does not require every scenario to be a user clicking through a screen.

- **UI feature**: the actor is the user; the outcome is what the user sees or can do.
- **API feature**: the actor is the consuming client or system; the outcome is what it receives, such as data, a refusal, or a status.
- **Security or audit behavior**: the outcome may be an event or log entry **if** an external party relies on it (audit, monitoring). Name that party.

## Rules

1. **Describe what, not how.** Ask: *would this wording change if the UI or implementation changed?* If yes, rewrite it. "The customer views the order" survives a redesign; "the customer swipes down and taps the Order button" does not. Exception: the interaction itself is the requirement (gesture support, keyboard-only operation, screen-reader labels).
2. **`Given` is state, not activity.** "Given a signed-in customer with an existing order" is state. How that state is reached (authentication, navigation, or test setup) belongs in the step definition.
3. **One behavior per scenario.** One `When` block, ideally 3–5 steps. A `Then` → `When` → `Then` chain is two scenarios.
4. **Every `Then` is verifiable and actually verified.** Step text is a promise; the step definition must assert exactly that promise. Read the binding before trusting a scenario.
5. **Scenarios are independent.** Each sets up its own state and passes when run alone or in any order. If a scenario depends on data another test produced, say so in its `Given`, or let it fetch its own data.
6. **Use the domain's language consistently.** Use one term per concept across all features, and use the term the business uses. Match the language the feature files already use. This repository's parser accepts English Gherkin keywords only; domain wording may still be localized where the bindings support it.
7. **Examples must be meaningful.** Each row in `Examples` is a different case (equivalence class, boundary, persona). Name the table after what distinguishes the rows. One row → plain `Scenario`. A column that never changes → inline it.
8. **Cover the rule, not just the happy path.** For each rule consider: success, rejection, boundary, missing or empty input, unauthorized access.
9. **Group by business rule.** Use `Rule:` to group the examples of one rule. Titles state the behavior, not the test: "The customer receives no order data without a valid session", not "Test 401".
10. **Keep steps atomic and reusable.** No conjunction steps (two facts joined by "and" in one step); use `And`. Reuse the exact wording of existing steps instead of writing near-duplicates.

## Procedure

1. **Understand the behavior.** Find the user story, rule, or acceptance criteria. List the rules and at least one concrete example per rule. If the expected outcome is unknown, ask. Never invent business rules or expected values.
2. **Choose the layer and the observer.** API (the consuming app observes responses) or UI (the user observes the screen). Test a rule at the lowest layer where it is observable; use UI scenarios for what only the UI shows (presentation, navigation, accessibility).
3. **Search existing steps first.** Find the repository's step definitions, follow their framework's binding syntax, and reuse matching step text verbatim. Do not assume a directory layout or binding format. Check whether the runner treats the same step text as one shared binding across keywords.
4. **Draft rules and scenarios.** Write the `Feature` description (who benefits and why), then `Rule` blocks with success, negative, and boundary examples.
5. **Write the steps** following the rules, then run the [review checklist](#review-checklist).
6. **Implement or verify the step definitions.**
   - Hide mechanics (selectors, gestures, HTTP calls, tokens) in step definitions and helpers.
   - Make each `Then` step assert precisely what it promises and report expected versus actual values when it fails.
   - Wait for a condition instead of fixed sleeps where possible.
   - If the framework generates files from feature files, edit the source `.feature` file and let the normal generation process update derived files.
7. **Run the scenario** using the repository's documented test command and, where practical, confirm it fails for the right reason when the behavior is broken.
8. **Self-review** against the [anti-pattern catalog](./references/anti-patterns.md).

## Review checklist

- [ ] The feature description says who benefits and why
- [ ] Each scenario illustrates one rule and has one event
- [ ] No clicks, taps, swipes, field names, selectors, URLs, or JSON in steps, unless the interaction is the requirement — framework binding ids or their declared display labels are syntax, not leakage
- [ ] `Given` steps describe state, not actions
- [ ] Every `Then` describes an outcome observable by the stated actor (user sees / app receives)
- [ ] Every `Then` is asserted by its step definition; the wording does not over-promise
- [ ] No vague outcomes ("correct", "successful", "as expected", "works") without a criterion
- [ ] The scenario passes on its own; any cross-test data dependency is explicit
- [ ] Example tables: each row is a distinct case, the label matches the rows, no commented-out rows, no constant columns
- [ ] Negative and boundary cases exist for each rule
- [ ] Vocabulary matches other features and existing step definitions
- [ ] Tags are correct, including tags that activate hooks

## Example: before and after

Before: UI scripting, a vague outcome, and a one-row outline.

```gherkin
Scenario Outline: A customer opens the details of an order
  Given a signed-in customer with customer number '<customer number>'
  And the customer views the order overview
  When the customer swipes down to see more details
  And the customer clicks the Order button
  Then the customer is successfully navigated to the order details

  Examples: Customers
    | customer number |
    | K-104           |
```

After:

```gherkin
Scenario: The customer views the details of an order
  Given a signed-in customer with an existing order
  When the customer views the order
  Then the customer sees the order details
```

The swipe and the button tap move into the step definition for "the customer views the order". The single-row outline becomes a plain scenario.

- Full good examples (API and UI): [examples](./references/examples.md)
- Bad practices and how to detect them: [anti-patterns](./references/anti-patterns.md)

## Repository conventions

This repository's parser accepts these English keywords: `Feature`, `Rule`, `Background`, `Scenario`, `Scenario Outline`, `Examples`, `Given`, `When`, `Then`, `And`, and `But`. Localized Gherkin keywords and `# language:` declarations are not supported by the parser; keep the keywords in English even when domain wording is localized.

- **Bindings:** locate the existing step definitions and follow their syntax, naming, and organization.
- **Binding references in step text:** a feature that declares a binding `label` may name the binding by that label instead of its id (`"promo code field"` rather than `"shopping.promoInput"`); both resolve through the generated `fromId`. The id stays canonical, the label is an optional readability alias, and a feature may use either consistently.
- **Tags and hooks:** check runner configuration and hook registrations before changing tags; a tag may affect setup or test selection.
- **Test data:** make each scenario's setup explicit. Avoid relying on data created by another test unless the dependency is documented and intentional.
- **Generated output:** edit source feature files rather than generated artifacts, when the framework generates them.
- **Execution:** use the repository's documented test command and prerequisites for the selected scenario or tag.
