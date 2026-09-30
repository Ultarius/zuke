# Anti-patterns in feature files

Named failures of the writing rules (1 to 10) and the binding's assertion (rule 16), each with **Spot**, **Why it hurts**, and **Fix**. Examples use an imaginary order domain; adapt vocabulary and keywords to the project. Promise failures (rules 11 to 16) live in [reachability](./reachability.md); evidence mismatches (rule 17) in [evidence](./evidence.md).

## Quick scan

Case-insensitive searches over `**/*.feature`. A hit is a candidate, not a defect. The patterns are English: add the project's own natural-language verbs, nouns, and Gherkin keywords (for example `Gegeven|Als|Dan|En|Maar` for Dutch).

```text
UI mechanics          \b(clicks?|clicked|clicking|taps?|tap(?:ping|ped)|swipes?|swip(?:ing|ed)|scrolls?|scroll(?:ing|ed)|types|typed|typing|button|field|selector|xpath)\b   # 1
Technical leakage     https?://|/v\d+/|\bjson\b|\btoken\b|\bcookie|\bendpoint\b|status\s?code                                                                          # 2
Vague outcomes        \b(correct\w*|successfully|properly|works?|as expected|good|fine|invalid input handled)\b                                                          # 6
Commented-out lines   ^\s*#\s*(\||(Given|When|Then|And|But)\b)                                                                                                         # 10
Trailing punctuation  ^\s*(Given|When|Then|And|But)\s+.*[.!]\s*$                                                                                                        # 17
Conjunction steps     ^\s*(Given|When|Then|And|But)\s+.+ (and) .+                                                                                                        # 14
Contrast clauses      ^\s*But\b                                                                                                                                         # 18
```

Known false positives:

- **Binding ids.** Some frameworks let steps name abstract bindings (`<actor> taps "<binding id>"`, `endpoint "<id>" is available`). The verb and id are the binding contract; the selector lives in the step definition.
- **Control nouns in outcomes.** "the checkout button is disabled" names what the user observes. Only a gesture or imperative interaction ("swipes down to reveal…") is the defect.
- **Tool metadata.** `#` lines carrying requirement ids, evidence types, profiles, or a language header (`# language: nl`) are spec input, not commented-out steps.
- **`and` inside one claim.** "the connection between "north" and "south" is established" joins values, not facts.
- **Literal product strings.** `displays "Order placed successfully!"` quotes what the product shows. Flag it only when the wording is the team's, not the product's.
- **API status codes.** In an API contract feature, a status code is an outcome the client observes (see 2).

These need reading rather than searching: several `When` blocks per scenario (5), one-row outlines and constant columns (10), and `Then` steps whose binding checks something else (7).

## 1. UI scripting (rule 1)

**Spot:** steps name gestures, controls, or screens as mechanics (*clicks, taps, swipes, scrolls, types, button, field*). The scenario reads like a manual test script.

```gherkin
When the customer swipes down to see more details
And the customer clicks the Order button
```

**Why it hurts:** it couples the specification to the current layout. A redesign breaks scenarios whose behavior did not change, and readers cannot see the intent.

**Fix:** state the intent and move the mechanics into the step definition.
```gherkin
When the customer views the order
```

**Allowed when** the interaction is the requirement: gesture support, keyboard-only operation, screen-reader labels.

## 2. Technical leakage (rule 1)

**Spot:** URLs, endpoint paths, query strings, JSON field names, tokens, cookies, or selectors in step text.

```gherkin
Given an unauthenticated customer accesses the protected endpoint '/api/orders/123?include=items'
```

**Why it hurts:** the path is an implementation detail that changes between versions. The reader has to parse a URL to learn the behavior: no login, no data.

**Fix:** name the capability; keep the path in the step definition or configuration.
```gherkin
Given no user is signed in
When the client requests a protected order's data
Then the service refuses the request because authentication is missing (401)
```

In API contract features, status and error codes are outcomes the consuming app observes, so mentioning them is fine. Paths and payload structure usually are not.

## 3. Wrong observer (rule 16)

**Spot:** "the user sees …" in a feature whose step definitions never touch a screen; they call an API and inspect the response.

API feature; the binding checks the HTTP response:
```gherkin
Then the customer sees the order data
```

**Why it hurts:** the scenario claims a UI outcome that is never verified. Readers believe the screen is covered.

**Fix:** name the real observer.
```gherkin
Then the client receives the order data
```

## 4. Actions in `Given` (rule 2)

**Spot:** context steps (before the event) with interaction verbs: *clicks, opens, navigates, enters, taps*.

```gherkin
Given the customer opens the application
And the customer taps Orders
```

**Why it hurts:** context and event blur together; the scenario appears to test navigation.

**Fix:** describe the resulting state.
```gherkin
Given the customer views an existing order
```

How that state is reached (navigation, deep link, API setup) is the step definition's job.

## 5. Several behaviors in one scenario (rule 3)

**Spot:** more than one `When` block, a `Then` followed by another `When`, a title where "and" joins two behaviors, or no `When` at all while a `Given` binding performs the event (navigates, submits).

```gherkin
When the user adds a task
Then the user sees 1 open task
When the user completes the task
Then the user sees 0 open tasks
```

**Why it hurts:** a failure does not show which behavior broke, and later behaviors go untested after the first failure.

**Fix:** write one scenario per behavior, and turn the earlier outcome into the next scenario's `Given`.
```gherkin
Given the user has 1 open task
When the user completes the task
Then the user sees 0 open tasks
```

## 6. Vague outcomes (rule 4)

**Spot:** *correct, successful, works, good, fine*: adjectives without a criterion.

```gherkin
And the order is processed correctly
And the customer sees all the correct order data
```

**Why it hurts:** the text does not tell anyone what passes; the meaning lives only in code.

**Fix:** state the criterion the step definition checks:
```gherkin
And the order has status 'confirmed'
And the order confirmation contains the expected total
```

## 7. Step text promises more than the binding checks (rule 16)

**Spot:** open the step definition, list its assertions, and compare them with the step text. Watch for assertions that accept empty values, "all" in the text but a subset in code, or "correct" validated only by format.

"The customer sees the order number" can pass when the value is empty. "all the correct order data" may check field presence and format without checking the expected values.

**Why it hurts:** green tests give false confidence, and the living documentation is wrong.

When the gap is between the binding and the product path rather than between the step text and the assertion (a guard the app skips, a mechanism that only approximates the promise), see [reachability](./reachability.md).

**Fix:** strengthen the assertion (compare against an independent expected value), or weaken the wording to what is actually checked ("contains a field for the e-mail address", "satisfies the contract").

## 8. Asserting internals (rule 1)

**Spot:** `Then` step definitions that query a database, read internal state, or inspect private fields.

```gherkin
Then a record exists in the Relations table with status 'ACTIVE'
```

**Why it hurts:** it tests implementation instead of behavior and breaks on refactoring. No user ever sees that table.

**Fix:** assert what an actor observes: a response, the screen, or a message. Exception: events and logs that another party depends on (audit trail, security monitoring) are contracts. Name that party, for example "Then security monitoring receives an alert …".

## 9. Hidden or shared state (rule 5)

**Spot:** the scenario fails when run alone or in another order; step definitions read files or data produced by other tests; or an outcome refers to something no `Given` created ("the previous result").

For example, a UI scenario may read expected values from a fixture produced by a separate API scenario. Even if the test reports a clear error when that scenario has not run, the dependency is still hidden from the feature file.

**Why it hurts:** flaky runs, order-dependent failures, and unreadable preconditions.

**Fix:** let each scenario create or fetch what it needs in `Given`. If a dependency is unavoidable, state it in the `Given` text or the feature description.

## 10. Misleading example tables (rule 8)

**Spot:**
- a label that does not match the rows (*"All test users"* with one active row)
- commented-out rows (`# | 450000133 |`)
- a `Scenario Outline` with exactly one row
- a column with the same value in every row
- several rows that exercise the same case

```gherkin
Examples: All test users
  | customer number | max seconds |
  | K-104           | 3           |
  # | K-205           | 3           |
```

**Why it hurts:** readers assume coverage that does not run.

**Fix:** delete or enable commented rows; name tables after what distinguishes the rows; inline constant values; turn one-row outlines into plain scenarios.

## 11. Magic data (rule 8)

**Spot:** identifiers or numbers with no stated meaning (`12345`, `67890`). You cannot tell why a value was chosen or how it differs from the next row.

**Why it hurts:** the example illustrates nothing, and when test data changes nobody knows which property mattered.

**Fix:** add a column or table label for the characteristic that matters (payment method, age, membership), and assert it. Alternatively, describe the persona in the step and map it to test data in the step definition.
```gherkin
Examples: Orders by delivery method
  | customer number | delivery method |
  | 12345           | standard        |
```

## 12. Inconsistent vocabulary (rule 6)

**Spot:** synonyms for one concept across features or steps, or one word with two meanings.

For example, one feature may use `order status` while another uses `status of the order` for the same concept. A tag's meaning can also vary: one runner may treat `@browser` as setup while another uses it only for test selection.

**Why it hurts:** readers wonder whether two things differ, near-duplicate step definitions multiply, and tag-based selection misses scenarios.

**Fix:** pick the term the business uses and use it everywhere. Search existing steps before introducing a word.

## 13. Duplicate step definitions (rule 6)

**Spot:** different step texts with identical bodies, or the same body registered under both `Given` and `Then`.

For example, `Given('the customer is on the order page')` and `When('the customer views the order')` may perform the same navigation. A second `Then` phrase that asserts the same result is duplicate wording too.

**Why it hurts:** two phrases for one behavior confuse readers and double the maintenance.

**Fix:** keep one phrase per behavior, and organize step definitions by domain concept rather than by feature file.

## 14. Conjunction steps (rule 7)

**Spot:** one step joins independent facts with "and".
```gherkin
Given the customer is signed in and has an existing order
```

**Fix:** split into separate steps with `And`, so each step is reusable.
```gherkin
Given the user is signed in
And the customer has an existing order
```

A list of outcomes reads better as a data table than as a long sentence.

## 15. Happy path only (rule 9)

**Spot:** a rule with only success scenarios and no rejection, empty input, boundary, or unauthorized case.

**Fix:** for each rule ask what happens when input is missing, invalid, or at the limit, or when the user is not allowed. Add one scenario per distinct answer.

## 16. Functional tags treated as decoration (writing step 1)

**Spot:** tags added, removed, or re-cased without checking runner configuration and hook registrations. A tag can activate setup as well as categorize a test.

**Fix:** inspect where a tag is defined and consumed before changing it. Keep descriptive tags separate from tags that alter execution.

## 17. Punctuation and formatting drift (rule 6)

**Spot:** inconsistent punctuation (`Then the customer is signed in.`), indentation, or whitespace. Depending on the step matcher, punctuation may be part of the binding text.

**Why it hurts:** formatting drift can make feature files harder to scan and, depending on the matcher, can prevent a step from matching its definition.

**Fix:** no trailing punctuation in step text, and one indentation style per file.

## 18. Contrast clause hiding a second rule (rule 3)

**Spot:** `But` carries a condition that contradicts the context or changes the outcome: a negative state appended to a positive `Given`, a negated sibling outcome in a `Then`, or a "but only when" exception.

```gherkin
Given the user is a registered user
But the user has not paid for a subscription
When the user opens the dashboard
Then the user sees an upgrade prompt
```

```gherkin
Then the checkout total is $50
But shipping fees are not included
```

**Why it hurts:** the state chain reads as a contradiction, and the step definition decides which half wins. A condition that changes the outcome is a second example of the rule. Runners treat `But` exactly like `And`, so the contrast lives only in the reader's head.

**Fix:** state the positive condition, and assert the positive fact.
```gherkin
Given a user with a free account
When the user opens the dashboard
Then the user sees an upgrade prompt
```
```gherkin
Then the checkout total is $50
And the shipping fee is $0
```

**Allowed when** it contrasts outcomes of the same kind, each asserted: `Then the user sees the save button` / `But the user does not see the delete button`. A project that bans `But` outright has a style convention; follow it.
