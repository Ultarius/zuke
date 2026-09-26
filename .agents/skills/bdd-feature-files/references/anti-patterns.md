# Anti-patterns in feature files

Each entry lists how to spot the problem, a bad example, why it hurts, and the fix. The examples are illustrative; adapt the vocabulary and syntax to the target feature language and test framework.

## Quick scan

Run these case-insensitive regex searches over `**/*.feature` and review each hit. A hit is a candidate, not an automatic defect. English keywords are the only supported syntax in this repository. Dutch terms are listed as candidates for identifying unsupported localized keywords.

```text
UI mechanics          \b(klikt|tikt|tapt|swipe\w*|scrollt|typt|vult .+ in|knop|veld|clicks?|clicked|clicking|taps?|tap(?:ping|ped)|swipes?|swip(?:ing|ed)|scrolls?|scroll(?:ing|ed)|types|typed|typing|button|field|selector|xpath)\b
Technical leakage     https?://|/v\d+/|\bjson\b|\btoken\b|\bcookie|\bendpoint\b|status\s?code
Vague outcomes        \b(correct\w*|succesvol|naar ontwerp|werkt|goed|juist|successfully|properly|works?|as expected|good|fine)\b
Commented-out lines   ^\s*#\s*(\|(?:Gegeven|Als|Wanneer|Dan|En|Maar|Given|When|Then|And|But)\b)
Trailing punctuation  ^\s*(Gegeven|Als|Wanneer|Dan|En|Maar|Given|When|Then|And|But)\s+.*[.!]\s*$
Conjunction steps     ^\s*(Gegeven|Als|Wanneer|Dan|En|Maar|Given|When|Then|And|But)\s+.+ (en|and) .+
```

Known false positives, and what to do with them:

- **Framework binding syntax.** Steps of the form `<actor> taps "<binding id>"`, `element "<id>" displays …`, or `endpoint "<id>" is available` refer to identifiers declared in the feature's own `# spec-begin` block and resolved by the runner. The verb and the id are the binding contract; the real selector lives in step definitions. Procedure step 3 says to follow the framework's binding syntax — these are not UI scripting.
- **Control nouns in outcomes.** "the checkout button state must be disabled" names what the user observes, not how they interact with it. Only a gesture or imperative interaction (`swipes down to reveal…`) is the defect.
- **Metadata lines.** `# requiredEvidence:` and `# securityProfile:` are spec metadata, not commented-out steps.
- **`and` inside one assertion.** "the peer connection between "north" and "south" is established" joins quoted values or a list, not two facts. Read the hit; only split it when the step really carries two independent claims.
- **Literal application strings.** `displays "Order placed successfully!"` quotes a message the product actually shows. Flag it only if the wording is the team's choice rather than the product's.

These need reading, not searching: several `When` blocks per scenario, one-row outlines, constant example columns, and `Then` steps whose binding checks something else.

---

## 1. UI scripting (imperative steps)

**Spot:** steps name gestures, controls, or screens as mechanics (*klikt, tikt, swipet, scrollt, vult in, knop, veld* / *clicks, taps, swipes, scrolls, types, button, field*). The scenario reads like a manual test script.

```gherkin
When de klant omlaag swipet om meer details te zien
And de klant op de knop Bestelling klikt
```

**Why it hurts:** it couples the specification to the current layout. A redesign breaks scenarios whose behavior did not change, and readers cannot see the intent.

**Fix:** state the intent and move the mechanics into the step definition.
```gherkin
When de klant de bestelling bekijkt
```

**Allowed when** the interaction is the requirement: gesture support, keyboard-only operation, screen-reader labels.

## 2. Technical leakage

**Spot:** URLs, endpoint paths, query strings, JSON field names, tokens, cookies, or selectors in step text.

```gherkin
Given een niet-ingelogde klant het beschermde endpoint '/api/orders/123?include=items' benadert
```

**Why it hurts:** the path is an implementation detail that changes between versions. The reader has to parse a URL to learn the behavior: no login, no data.

**Fix:** name the capability; keep the path in the step definition or configuration.
```gherkin
Given er is geen gebruiker ingelogd
When de client de gegevens van een beschermde bestelling opvraagt
Then weigert de dienst het verzoek omdat authenticatie ontbreekt (401)
```

In API contract features, status and error codes are outcomes the consuming app observes, so mentioning them is fine. Paths and payload structure usually are not.

## 3. Wrong actor or observer

**Spot:** "de gebruiker ziet …" in a feature whose step definitions never touch a screen; they call an API and inspect the response.

API feature; the binding checks the HTTP response:
```gherkin
Then ziet de klant de bestelgegevens
```

**Why it hurts:** the scenario claims a UI outcome that is never verified. Readers believe the screen is covered.

**Fix:** name the real observer.
```gherkin
Then ontvangt de client de bestelgegevens
```

## 4. Actions in context steps (`Gegeven` / `Given`)

**Spot:** context steps (before the event) with interaction verbs: *klikt, opent, navigeert, vult in, tikt* / *clicks, opens, navigates, enters, taps*.

```gherkin
Given de klant opent de toepassing
And de klant tikt op Bestellingen
```

**Why it hurts:** context and event blur together; the scenario appears to test navigation.

**Fix:** describe the resulting state.
```gherkin
Given de klant bekijkt een bestaande bestelling
```

How that state is reached (navigation, deep link, API setup) is the step definition's job.

## 5. Several behaviors in one scenario

**Spot:** more than one `Als`/`Wanneer` block, a `Dan` followed by another `Wanneer`, or a title where "en" joins two behaviors.

```gherkin
When de gebruiker een taak toevoegt
Then ziet de gebruiker 1 openstaande taak
When de gebruiker de taak afrondt
Then ziet de gebruiker 0 openstaande taken
```

**Why it hurts:** a failure does not show which behavior broke, and later behaviors go untested after the first failure.

**Fix:** write one scenario per behavior, and turn the earlier outcome into the next scenario's `Gegeven`.
```gherkin
Given de gebruiker heeft 1 openstaande taak
When de gebruiker de taak afrondt
Then ziet de gebruiker 0 openstaande taken
```

## 6. Vague outcomes

**Spot:** *correct, succesvol, naar ontwerp, werkt, goed, juist*: adjectives without a criterion.

```gherkin
And wordt de bestelling correct verwerkt
And ziet de klant alle correcte bestelgegevens
```

**Why it hurts:** the text does not tell anyone what passes; the meaning lives only in code.

**Fix:** state the criterion the step definition checks:
```gherkin
And heeft de bestelling de status 'bevestigd'
And bevat de bestelbevestiging het verwachte totaalbedrag
```

## 7. Step text promises more than the binding checks

**Spot:** open the step definition, list its assertions, and compare them with the step text. Watch for assertions that accept empty values, "all" in the text but a subset in code, or "correct" validated only by format.

"ziet de klant het bestelnummer" can pass when the value is empty. "alle correcte bestelgegevens" may check field presence and format without checking the expected values.

**Why it hurts:** green tests give false confidence, and the living documentation is wrong.

**Fix:** strengthen the assertion (compare against an independent expected value), or weaken the wording to what is actually checked ("bevat een veld voor het e-mailadres", "voldoet aan het contract").

## 8. Asserting internals

**Spot:** `Dan` step definitions that query a database, read internal state, or inspect private fields.

```gherkin
Then staat er een record in de tabel Relaties met status 'ACTIEF'
```

**Why it hurts:** it tests implementation instead of behavior and breaks on refactoring. No user ever sees that table.

**Fix:** assert what an actor observes: a response, the screen, or a message. Exception: events and logs that another party depends on (audit trail, security monitoring) are contracts. Name that party, for example "Then security monitoring receives an alert …".

## 9. Hidden or shared state

**Spot:** the scenario fails when run alone or in another order; step definitions read files or data produced by other tests; or an outcome refers to something no `Gegeven` created ("het vorige resultaat").

For example, a UI scenario may read expected values from a fixture produced by a separate API scenario. Even if the test reports a clear error when that scenario has not run, the dependency is still hidden from the feature file.

**Why it hurts:** flaky runs, order-dependent failures, and unreadable preconditions.

**Fix:** let each scenario create or fetch what it needs in `Gegeven`. If a dependency is unavoidable, state it in the `Gegeven` text or the feature description.

## 10. Misleading example tables

**Spot:**
- a label that does not match the rows (*"Alle testgebruikers"* with one active row)
- commented-out rows (`# | 450000133 |`)
- a `Scenario Outline` with exactly one row
- a column with the same value in every row
- several rows that exercise the same case

```gherkin
Examples: Alle testgebruikers
  | klantnummer | maxAantalSeconden |
  | K-104       | 3                 |
  # | K-205       | 3                 |
```

**Why it hurts:** readers assume coverage that does not run.

**Fix:** delete or enable commented rows; name tables after what distinguishes the rows; inline constant values; turn one-row outlines into plain scenarios.

## 11. Magic data

**Spot:** identifiers or numbers with no stated meaning (`12345`, `67890`). You cannot tell why a value was chosen or how it differs from the next row.

**Why it hurts:** the example illustrates nothing, and when test data changes nobody knows which property mattered.

**Fix:** add a column or table label for the characteristic that matters (betaalwijze, leeftijd, collectiviteit), and assert it. Alternatively, describe the persona in the step and map it to test data in the step definition.
```gherkin
Examples: Bestellingen per bezorgmethode
  | klantnummer | bezorgmethode |
  | 12345       | standaard     |
```

## 12. Inconsistent vocabulary

**Spot:** synonyms for one concept across features or steps, or one word with two meanings.

For example, one feature may use `bestelstatus` while another uses `status van de bestelling` for the same concept. A tag's meaning can also vary: one runner may treat `@browser` as setup while another uses it only for test selection.

**Why it hurts:** readers wonder whether two things differ, near-duplicate step definitions multiply, and tag-based selection misses scenarios.

**Fix:** pick the term the business uses and use it everywhere. Search existing steps before introducing a word.

## 13. Duplicate or near-duplicate step definitions

**Spot:** different step texts with identical bodies, or the same body registered under both `Given` and `Then`.

For example, `Given('de klant is op de bestelpagina')` and `When('de klant bekijkt de bestelling')` may perform the same navigation. A second `Then` phrase that asserts the same result is duplicate wording too.

**Why it hurts:** two phrases for one behavior confuse readers and double the maintenance.

**Fix:** keep one phrase per behavior, and organize step definitions by domain concept rather than by feature file.

## 14. Conjunction steps

**Spot:** one step joins independent facts with "en".
```gherkin
Given de klant is ingelogd en heeft een bestaande bestelling
```

**Fix:** split into separate steps with `En`, so each step is reusable.
```gherkin
Given de gebruiker is ingelogd
And de klant heeft een bestaande bestelling
```

A list of outcomes reads better as a data table than as a long sentence.

## 15. Happy path only

**Spot:** a rule with only success scenarios and no rejection, empty input, boundary, or unauthorized case.

**Fix:** for each rule ask what happens when input is missing, invalid, or at the limit, or when the user is not allowed. Add one scenario per distinct answer.

## 16. Functional tags treated as decoration

**Spot:** tags added, removed, or re-cased without checking runner configuration and hook registrations. A tag can activate setup as well as categorize a test.

**Fix:** inspect where a tag is defined and consumed before changing it. Keep descriptive tags separate from tags that alter execution.

## 17. Punctuation and formatting drift

**Spot:** inconsistent punctuation (`Then the customer is signed in.`), indentation, or whitespace. Depending on the step matcher, punctuation may be part of the binding text.

**Why it hurts:** formatting drift can make feature files harder to scan and, depending on the matcher, can prevent a step from matching its definition.

**Fix:** no trailing punctuation in step text, and one indentation style per file.
