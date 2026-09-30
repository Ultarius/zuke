# Reachability: does the product keep the promise?

A scenario can be readable, bound, and green while no actor can do what it describes. This is the audit for rules 11 to 16. It reads product code and step definitions, not only `.feature` files.

## Find candidates

Case-insensitive searches. Each hit names a step to trace, not a defect.

```text
Capability verbs     \b(records?|imports?|exports?|zooms?|trims?|assigns?|scans?|inserts?|renames?|attaches?|uploads?|downloads?|signs? in|signs? out|configures?)\b
Advisory outcomes    \b(explains?|warns?|informs?|tells?|instructs?|reminds?|explanation|warning|notice)\b
System events        \b(application starts|on startup|next launch|interval elapses|playback crosses|at launch|after a restart)\b
Named surfaces       \b(panel|list|dialog|screen|banner|menu|notice)\b
Causal claims        \b(applies to|drives|is used (by|for)|takes effect)\b
Instructional copy   \b(go to|open|configure|enable|set up|add .{1,30} in|turn on|choose|select)\b   # run over user-facing strings and message catalogs
```

Run the first five over `**/*.feature`, the last over the product's user-facing strings.

## The ledger

One row per distinct `When`, user-configurable `Given`, named surface, and instruction in product copy; repeats across scenarios share a row. Trace the **actor path** in the product and the **entry point** the binding drives; they must be the same.

```text
| Item                          | Actor path in product            | Binding entry point        | Verdict      | Action                    |
| SCN-RECORDING-001  When       | none (no record control)         | service call               | product gap  | build control, drive UI   |
| SCN-RECOVERY-001   When       | none (scheduler never started)   | service call               | product gap  | schedule ticks at startup |
| SCN-EXPORT-005     When       | export action skips the guard    | app export action          | product gap  | honour confirmation       |
| SCN-ACCOUNT-001    Then       | none (no account panel)          | store call                 | product gap  | build panel or rename     |
| SCN-EDITOR-SNAP-1  Given      | fixture-only snap                | fixture                    | fixture-only | mark in Given             |
| SCN-ORDER-002      When       | order screen, "View" action      | order screen               | reachable    | none                      |
| Copy "add X in Settings"      | no Settings section              | n/a                        | product gap  | add scenario and section  |
```

Every row ends in one of four verdicts: **reachable**, **fixture-only** (with the reason in the `Given`), **product gap** (with an action), or **unverified** when the product code or a running product is out of reach (with the observation that would settle it). A product gap is fixed in the product, or the scenario is reworded to the actor that really exists. Keep the ledger where the team reviews it: the PR, the coverage artifact, or a test name.

## Failure modes

### Unreachable capability (rule 11)

**Spot:** a `When` names an action (record, import, sign in, rename), the binding calls a service, controller, or repository, and the product has no control for the actor.

```gherkin
When the user records for two bars
```

Bound to `recordingService.record(...)`; the product has no record control.

**Fix:** build the product path and bind the step through it. When the behavior is genuinely a lower-layer contract, move the scenario to a feature whose actor is the client.

### Orphaned system event (rule 11)

**Spot:** a `When` is a process event, the binding calls the underlying service, and production never raises the event: no startup hook, no scheduler, no polling loop.

```gherkin
When the autosave interval elapses
```

Bound to `autosave.tick()`; the app never schedules ticks.

**Fix:** bind to the production trigger (run the real startup path, advance the real scheduler) and confirm it fires in the app. When the trigger does not exist yet, building it is part of the scenario.

### Hidden affordance (rule 12)

**Spot:** a user-configurable state (mode, toggle, range, snap value, channel, credential) appears only in `Given`.

```gherkin
Given the track records in replace mode
```

No scenario selects the mode, so a product with no mode selector passes.

**Fix:** decide per state. User-set: add the scenario and the control.

```gherkin
Scenario: The user selects the replace record mode
  Given a MIDI track armed for recording
  When the user selects replace record mode
  Then the track records in replace mode
```

Test setup only: mark the `Given` itself, in the step text, as `(fixture-only: <reason>)`. The reason is mandatory — it is what stops a future reader from assuming a control exists.

```gherkin
Given a MIDI track armed for recording in replace mode (fixture-only: no mode selector yet)
Given a project with a selected range from bar 1 to bar 9 (fixture-only: no range selector)
Given a project whose tempo changes from 120 to 90 BPM at bar 3 (fixture-only: no tempo editor)
```

The marker goes in the step text, not in a comment: comments are stripped from the reader's view, and the marker must travel with the state it qualifies.

### Named surface with no owner (rule 13)

**Spot:** a `Then` names a panel, list, dialog, or banner that no binding asserts and the product lacks.

```gherkin
Then the account panel shows the signed-in user
```

**Fix:** build and assert the surface, or name what exists: `Then the user sees the signed-in account name`.

### Unactionable guidance (rule 14)

**Spot:** a `Then` or a product string explains, warns, or instructs, and the step it names does not exist in the product.

```gherkin
Then the assistant explains how to configure a provider
```

The product says "Configure a provider in Settings"; Settings has no such section. The scenario passes on string content.

**Fix:** make the criterion name a mechanism, and give the mechanism its own scenario.

```gherkin
Scenario: An unconfigured assistant explains setup
  Given no AI provider is configured
  When the user opens the assistant
  Then the explanation names configuration steps available in the application

Scenario: The user configures a provider from settings
  Given no AI provider is configured
  When the user enters an endpoint and API key in settings
  Then the assistant answers questions
  And the key is stored outside the project file
```

When configuration is intentionally file-based, the criterion names the file and section instead.

### Inert configuration (rule 15)

**Spot:** a scenario says a setting applies to, drives, or is used by behavior, and the only assertion is on the stored value. Also: a default presented as data-driven ("the first available input") that is a hardcoded constant.

```gherkin
Scenario: A larger buffer size applies to the engine
  Given the audio engine is running with a small buffer
  When the user selects a larger buffer
  Then the engine runs with the larger buffer
```

The value is persisted; no engine path reads it.

**Fix:** wire the consumer and assert the engine's effective buffer, or weaken the scenario to what is true: "the chosen buffer size is remembered".

### Guard the product path bypasses (rule 16)

**Spot:** the check exists and has a green test, but the app's own path skips it.

```text
unit test:  exporter.export(path)                   → asks for confirmation → green
app action: exporter.export(path, overwrite: true)  → overwrites silently
```

**Fix:** bind the scenario to the app action. The promise belongs to the journey, not to the class that owns the check.

### Approximated promise (rule 16)

**Spot:** the path exists but only resembles the promise. The playhead advances on a fixed-rate timer while the scenario promises the project tempo; a meter computes its level once instead of following the signal.

**Fix:** compare the promised observable with the mechanism that produces it, and assert the property the step names (tempo, live level).

### Borrowed coverage (rule 16)

**Spot:** a test carries a scenario id or `Then` text, but its body calls internals; or a coverage record names the scenario without naming the entry point.

```text
test body:      recordingService.record(track, bars: 2, input: buffer)
coverage label: SCN-RECORDING-001
```

**Fix:** step definitions drive the app's record action, assert the clip and file from the product, and record the entry point with the coverage claim. When the lower layer is the intended contract, move the scenario to that layer's feature.

## Worked example: copy claims a journey

```gherkin
# Before
Rule: Backups stay off until a destination is set

  Scenario: An unconfigured application explains setup
    Given no backup destination is set
    When the user opens the backups screen
    Then the application explains how to set a destination

  Scenario: A configured application runs a backup
    Given a configured backup destination
    When the nightly trigger fires
    Then the application writes a backup
```

```text
Product copy: "Add a backup folder in Settings to enable backups."
Settings has Account and Appearance only.
The second scenario's binding saves the destination through the settings store
and calls the backup service directly.
```

Ledger findings: unactionable guidance (copy names a missing section), hidden affordance (destination set only in `Given`), orphaned system event (nightly trigger simulated).

```gherkin
# After
Rule: Backups stay off until a destination is set

  Scenario: An unconfigured application explains setup
    Given no backup destination is set
    When the user opens the backups screen
    Then the explanation names settings steps available in the application

  Scenario: The user sets a backup destination
    Given no backup destination is set
    When the user chooses a backup folder in settings
    Then the destination is remembered for the next launch

  Scenario: A configured application runs a backup
    Given a configured backup destination
    When the nightly trigger fires
    Then the application writes a backup
```

The third binding now drives the real scheduler, and the ledger records each entry point.
