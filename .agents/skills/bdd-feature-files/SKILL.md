---
name: bdd-feature-files
description: 'BDD Gherkin feature files (Given/When/Then) and their step definitions. Use when writing, reviewing, or refactoring scenarios or step bindings, choosing API or UI coverage, auditing evidence declarations on rules, or deciding whether a scenario is done.'
argument-hint: 'Feature file or folder to write or review'
---

# BDD feature files

A feature file is an executable **specification**: concrete examples of business rules, in the domain's language, automated by step definitions. People read it; the runner executes it. Every step is a **promise**: the product must be able to keep it, and the binding must check it. A green run proves only what the bindings executed.

The parser keywords, natural language, binding syntax, tags, and test command come from the project in front of you. This skill holds the discipline, not the framework.

## The scenario

| Part | Keyword | Holds | Lives in the step definition |
|---|---|---|---|
| Context | `Given` | State before the event | How the state is reached: sign-in, navigation, setup data |
| Event | `When` | One action by one actor, or one system event | Gestures, selectors, HTTP calls, tokens |
| Outcome | `Then` | What the observer sees or receives, with a criterion | How it is read: locators, response parsing |

- **Actor**: who performs the `When`. A user in a UI feature, a consuming client in an API feature, or the system itself (startup, a timer).
- **Observer**: who sees the `Then`. The user sees a screen; a client receives data, a refusal, a status code. A log or event is an outcome only when a named party relies on it (audit, security monitoring).
- **`And` / `But`** continue the previous keyword; runners give `But` no logic. Keep `But` for contrast of the same kind (`Then the user sees the save button` / `But the user does not see the delete button`). A condition that contradicts the state or changes the outcome is a second scenario.

## Rules

Apply every rule to every scenario.

**Writing**

1. **What, not how.** Test: would the wording change if the UI or implementation changed? Then rewrite it. "The customer views the order" survives a redesign; "the customer swipes down and taps Order" does not. The interaction appears in step text only when it is the requirement: gesture support, keyboard-only operation, screen-reader labels.
2. **`Given` is state.** "Given a signed-in customer with an existing order". Reaching that state is the binding's job.
3. **One behavior per scenario.** Exactly one `When`, ideally 3 to 5 steps. `Then` → `When` → `Then` is two scenarios: the first outcome becomes the second's `Given`.
4. **Every outcome carries a criterion.** "the order has status 'confirmed'", not "the order is processed correctly".
5. **Scenarios are independent.** Each passes alone and in any order. A data dependency on another test is stated in its `Given`.
6. **One term per concept**: the business's term, in the natural language and keyword set the parser accepts. Reuse existing step text verbatim.
7. **Atomic steps.** Two facts joined by "and" become two steps.
8. **Honest examples.** Each `Examples` row is a distinct case (equivalence class, boundary, persona), and the table label names what distinguishes the rows. One row becomes a plain `Scenario`; a constant column is inlined; commented-out rows are deleted or enabled.
9. **Cover the rule.** Per rule: success, rejection, boundary, missing input, unauthorized.
10. **Group by `Rule:`.** Titles state behavior: "The customer receives no order data without a valid session", not "Test 401".

**Promises.** These separate a green suite from a working product. Failure modes and the audit ledger: [reachability](./references/reachability.md).

11. **Every `When` has an actor path**: a screen, command, or API the product exposes to that actor. A system event is raised by production code: the startup path, the scheduler.
12. **Every user-configurable `Given` state has a scenario where the actor sets it**, or is marked **fixture-only** with the reason.
13. **Every surface named in a `Then` exists and is asserted**: panel, list, dialog, banner, notice.
14. **Advice names a mechanism.** An explanation, warning, or instruction, whether in a `Then` or in product copy, names a step the product provides, and a scenario makes that step possible.
15. **"Applies to" names a consumer.** A setting said to drive behavior is asserted where the behavior changes, not where the value is stored.
16. **The binding keeps the promise.** It drives the actor's **entry point** (or the real trigger of a system event), asserts exactly what the step text says, and reports expected versus actual. A binding that calls a service directly while the step names a user is **borrowed coverage**.
17. **Evidence slots match observed layers.** When the project declares per rule which kinds of evidence may prove it (`requiredEvidence` or an equivalent), a user-operated `When` needs a UI slot, and a `Then` about an **artifact** (saved file, render, log payload, external response: anything that can be wrong while the screen looks right) needs a domain or integration slot. A **mirrored state** the screen already shows (playing, selected, a marked range) needs only the UI slot. Audit: [evidence](./references/evidence.md).

## Writing a feature

Each step ends on its completion criterion. Move to the next step only when it holds.

### Step 1: Read the project

Find the parser's natural language and keyword set (and its language header, if it needs one), the step definitions and their binding syntax, whether the runner shares one binding across `Given`/`When`/`Then` for identical text, every tag consumed by hooks or runner configuration, the metadata format (requirement ids, evidence types), files generated from `.feature` sources, and the documented test command. Where the framework lets steps name abstract binding ids, the id is the contract and the selector stays in the binding.

Done when you can name the step-definition location, the test command, and every tag that changes execution.

### Step 2: Pin the behavior

From the story or acceptance criteria, list the rules and at least one concrete example per rule. Expected values come from a source: the story, a domain expert, the product. When an outcome is unknown, ask.

Done when every rule has an example whose expected value you can cite.

### Step 3: Choose the layer

Test each rule at the lowest layer where it is observable: API when a client observes a response; UI for what only the screen shows (presentation, navigation, accessibility).

Done when every rule has a layer, and its observer matches what bindings at that layer can verify.

### Step 4: Draft

Write the `Feature` description (who benefits and why), then `Rule:` blocks with success, rejection, and boundary scenarios, reusing existing step text. Complete API and UI features to model on: [examples](./references/examples.md).

Done when every hit of the [quick scan](./references/anti-patterns.md#quick-scan) is fixed or justified.

### Step 5: Audit the promises

Fill the reachability ledger: one row per distinct `When`, user-configurable `Given`, named surface, and instruction in product copy. When rules carry evidence metadata, run the evidence audit.

Done when every ledger row reads reachable, fixture-only, product gap with an action, or unverified with the observation that would settle it, and every rule's slots cover the layers its scenarios observe.

### Step 6: Bind

Mechanics (selectors, gestures, HTTP calls, tokens) live in step definitions and helpers. Drive the real entry point; wait on conditions rather than fixed sleeps. When the product cannot perform a step, that is a finding: fix the product or the scenario. Edit the source `.feature` and let generation update derived files. Record the entry point each binding drives next to its coverage claim.

Done when you have read every binding the scenario uses, and each one's assertions match its step text.

### Step 7: Run

Run the project's test command filtered to the scenario or tag. Where practical, break the behavior and watch the scenario go red for the right reason.

Done when you have shown the command and its output, and the scenario passes when run alone.

## Reviewing

Run steps 1, 3, 5, and 6 of writing a feature against the existing files, then apply every rule to every scenario. Name each finding after its [anti-pattern](./references/anti-patterns.md) or [reachability](./references/reachability.md) entry, which carries the rule number (or by the rule alone when no entry fits), quote the step, and give the fix. Report promise findings (rules 11 to 17) before wording findings (rules 1 to 10): a readable scenario the product cannot keep is the worse defect.

Label every finding with where the fix lands, so the reader can route it without re-deriving it:

- **feature file** — the step, scenario, or rule metadata can be corrected in place (fixture-only markers, evidence slots, wording, splits).
- **binding** — the step definition or test must change (borrowed coverage, over- or under-assertions).
- **product** — the actor path, trigger, surface, or consumer must be built (unreachable capability, orphaned event, named surface, inert configuration).

A finding whose fix spans layers gets the smallest label that unblocks it, plus the follow-up. Never downgrade a product gap to a feature-file edit by weakening a promise the product is supposed to keep.

Done when every scenario has been checked against all 17 rules and every finding carries an entry or rule number, a quoted step, a fix, and a fix location.
