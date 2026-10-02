# Analyzer plugin contract and cache recovery

`zuke doctor` audits local plugin caches. `zuke doctor --fix` resolves and
recompiles affected synthetic plugin packages, then writes content receipts.
Run `zuke doctor` first to see which entries need repair. For a large cache,
`zuke doctor --fix --max-plugin-repairs 10` repairs at most ten stale entries in
deterministic path order. The remaining entries are reported as **deferred** and
the command still exits zero, because a bound the caller asked for is not a
failure; the exit code reflects entries that are still broken. Repeat the
command to work
through the rest. An unbounded `--fix` still repairs every stale entry. Repairs
use up to four workers and report progress as each entry finishes; one failed
entry does not stop other entries in the batch.
For the usual active-workspace repair, use
`zuke doctor --fix --current-context --root <workspace-root>`. This scopes the
audit and repair to the synthetic entry keyed by that analysis context root;
the ordinary doctor command still sees all entries for the local clone. Pass
the actual context root used by the editor. `--current-context` and
`--plugin-cache-entry` are alternative scopes.
If no entry matches that exact path spelling, doctor returns
`ZUKE-PLUGIN-CACHE-CONTEXT` as an error, and `zuke analyze` stops before invoking
`dart analyze`. Inspect the full `zuke doctor` inventory for the editor's path.
On a workspace the analysis server has never opened, run `dart analyze` once to
let Dart create its entry, then retry the scoped command.
To repair known entries from the audit, pass `--plugin-cache-entry <path>` once
per entry (optionally together with the count limit). Other stale entries are out
of scope for that run and are not reported; a plain `zuke doctor` still lists
them. The path must identify an entry owned by the local Zuke
clone; the command will not repair an arbitrary directory.
Restart the analysis server or reload the editor after repair: replacing an AOT
file does not replace an isolate already running in the editor.

`zuke analyze -- <dart analyze arguments>` repairs the current context before starting a
fresh `dart analyze` process and returns its exit status. Run it at the workspace
root, or pass `--root`. `zuke generate` audits without modifying the plugin cache
(except that `--quiet` skips this optional audit). Generate checks only the
synthetic entry for its current analysis context and prints at most one cache
advisory; `zuke doctor` gives the full inventory, including entry paths, states,
and snapshot size.
`zuke init --editor vscode` installs a folder-open Doctor Check task and a manual
Doctor Fix task. VS Code still controls whether automatic tasks are permitted.

## Cache lifecycle and selective cleanup

Dart 3.12 names a synthetic plugin cache entry from the analysis **context root
path**. Similar dependency resolutions do not establish that two entries are
interchangeable: they may belong to different live workspaces, and one synthetic
package may contain several plugins. Zuke therefore does not automatically
delete entries during `doctor --fix` or infer unused entries from age or a build
fingerprint. Repair continues to work per entry. If compilation produces the
same AOT bytes as the installed snapshot, repair leaves that snapshot in place
and writes the content receipt; this avoids needless replacement of a live file.

To reclaim a known, unused entry, first inspect the full `zuke doctor` output.
Stop **all analysis servers** using the selected entries, then preview:

```sh
zuke doctor --prune-cache --dry-run --plugin-cache-entry <absolute-entry-path>
```

If the preview says `ready`, remove only those same explicitly selected entries:

```sh
zuke doctor --prune-cache --analysis-server-stopped --plugin-cache-entry <absolute-entry-path>
```

Repeat `--plugin-cache-entry` to select several entries. The command refuses
paths outside the cache, linked entries, the current context root, entries
containing another plugin, and entries not resolving to this local Zuke clone.
The preview reports reclaimable bytes; the removal reports reclaimed bytes.
Restart the analysis servers afterward. This operation does not establish that
an entry belongs to no other active context, so only select entries for which
you know the corresponding workspaces are closed. If unsure, leave the entry in
place; Dart can recreate a removed synthetic package when that workspace is
analyzed again.

## What was verified

The Dart 3.12.2 plugin manager already compiles a depfile and checks its source
timestamps before reusing an AOT snapshot. It does not blindly reuse every
snapshot forever. Timestamp-preserving copies/checkouts can evade that check,
and restarting a running plugin can reuse its existing `PluginFiles` rather
than recomputing them. See the SDK's
[plugin manager implementation](https://github.com/dart-lang/sdk/blob/3.12.2/pkg/analysis_server/lib/src/plugin/plugin_manager.dart).

An old plugin with no contract handshake cannot acquire that handshake without
being rebuilt once. No producer-only index change can retrofit its behavior.
The first audit therefore reports **unverified**, not a claim that the snapshot
is definitely stale. Only a successful rebuild can establish its provenance.

## Analyzer compatibility without a workspace-version pin

`zuke_analyzer` accepts analyzer `>=12.1.0 <15.0.0`, matching the upper bound of
`zuke_cli`. The workspace lock currently resolves 12.1.0, while the analysis
server's synthetic plugin package resolved 14.4.0 in the fresh-build test. Both
compile and the missing-evidence-types diagnostic is exercised in both lanes.
The constraint is a tested compatibility range, not a pin to the workspace lock.
The upper bound still excludes an untested future breaking major.

Analyzer 12 represents a named argument as `NamedExpression`; analyzer 14 uses
`NamedArgument`. The editor-facing `declaresReadableEvidenceTypes` helper accepts
their common `AstNode` interface. It checks the first token and following colon
to identify the exact `evidenceTypes:` name, then examines the argument's final
expression child for an empty list or set. It does not depend on either named
argument class or parse the argument's source text. A positional callback named
`evidenceTypesCallback` therefore cannot hide a missing argument. Nonliteral
values remain unknown until runtime and are treated as declared.

The plugin and `zuke_cli/editor.dart` still use analyzer APIs elsewhere. For
each new analyzer major, run the workspace unit tests and the real
`plugin_locations_test.dart` integration suite. The latter forces the analysis
server to resolve and AOT-compile a synthetic plugin package and checks the
missing-evidence-types rule in that build. Review compiler failures and rule
behavior before raising the range's upper bound. Out of scope for that rule are
harness-level defaults such as
`ZukeFlutterEvidenceHarness.defaultEvidenceTypes`: it reports a registration
that would throw, not one that is covered.

## Decisions

| Question | Decision |
|---|---|
| Diagnostic location | Prefer the configured barrel; otherwise choose a stable existing generated contract, indexed source, or source under `lib`, `bin`, or `test`. Callback order never selects the anchor. A workspace with no analyzable Dart file must use doctor for diagnosis. |
| Repair scope | All synthetic cache entries resolving the same local `zuke_analyzer` or `zuke_cli` roots as the workspace package configuration or a direct analyzer-plugin path in its options. Unrelated clones and hosted-only installations are not rebuilt. `--max-plugin-repairs` bounds one repair run, but the cache does not identify which workspace created an entry, so it cannot automatically prioritize the editor's active workspace. |
| Severity | Error, enabled by default. All other Zuke rules are suppressed on a contract mismatch. Users can still explicitly disable rules through analyzer configuration. |
| Version location | `contractVersion` in the analyzer index only; the constant lives in `zuke_cli/src/index_contract.dart` and is exported through `editor.dart`. |
| Missing version | Ordinary stale-index behavior; regenerate. `doctor --fix` regenerates a missing, malformed, or incompatible header. |
| Deletion vs rebuilding | `doctor --fix` rebuilds selected snapshots and never prunes automatically. Explicit `--prune-cache` removes only selected, Zuke-only entries after a preview and all relevant analysis servers have stopped. |

The contract is checked before decoding the rest of the index. This handles
both older and newer producer contracts even when their JSON shapes cannot be
read by the compiled plugin. The message describes a generator/plugin mismatch
rather than assuming which side is old.

## Binding coverage in the editor: `zuke_binding_unbound`

`zuke_binding_unbound` is a **warning** rule reporting evidence slots a rule
declares for which no managed test registration exists. It answers the same
question as the CLI check, through the same `BindingVerdictEngine`, so the two
cannot disagree about whether a slot is bound. It is a different surface, not a
different verdict.

Enable it like any other plugin diagnostic, in `analysis_options.yaml`:

```yaml
plugins:
  zuke_analyzer:
    diagnostics:
      zuke_binding_unbound: true
```

**What it establishes.** That a matching registration exists. Nothing more. A
registration it credits may call a service directly and never perform the user's
action, so `bound` means "a test exists", not "the promised behaviour ran".
Deciding that needs the entry point that actually ran, observed at runtime.

**Why it needs the index.** A slot is unbound only if *no* registration anywhere
satisfies it, so the question is about the whole workspace and a per-file
analysis cannot answer it. `zuke generate` records the registrations, the declared
slots, the runner scopes and the count of registrations it could not resolve.
Because "unresolved" is workspace-wide, one unreadable registration makes every
slot `unverified` rather than `unbound`.

**Findings appear and disappear with `zuke generate`.** The rule reads a
snapshot. Freshness gating stops it from reporting a gap the workspace has
already closed, but the index is not refreshed by a diagnostic callback: writing
to the workspace from analysis is not something a rule may do, and a debounced
refresh belongs to the editor. The sequence is therefore:

1. Add the widget test that closes the gap.
2. Run `zuke generate`.
3. The squiggle disappears.

While the index is stale the rule says nothing at all, in either direction.

**Gate.** It requires *both* fact families current. The slots come from the
specifications and the registrations from the Dart sources, so a drift on either
side makes the comparison unsound; a stale specification would otherwise be
compared against today's registrations and report a gap that no longer exists.
This is the same `_needsSpecificationAndSourceFacts` decision
`zuke_unimplemented_requirement` uses.

**Scope differs from the CLI, deliberately.** An editor has no profile, so the
rule names every affected scenario in the workspace. A `zuke validate` run with a
tag filter, or with a profile lock that selects scenarios, names fewer. The
underlying verdicts are identical; only the named set differs. Compare an
unfiltered `zuke validate` run when reconciling counts.

**One owner per finding.** Each finding is anchored on the generated constant for
its own rule (`static const someRule = 'RULE-…';`), only in the contract
generated from that rule's feature, and at most once per rule/slot even when the
contract spells the same rule again as an alias or a `RuleId('…')` companion. The
`.feature` file and line are carried in the message.

**Suppression.** `// ignore:` and `// ignore_for_file:` do not suppress this — the
same limitation as the other plugin diagnostics. The only supported relief is the
`diagnostics:` map above, which is per workspace.

**Known-facts are strict by design.** `managedRegistrations`,
`unresolvedManagedRegistrations`, `evidenceObligations` and `runnerScopes` are
required keys, and an unknown field is written as an explicit `null` rather than
omitted. A registration whose evidence kinds could not be read may be exactly the
one satisfying a slot, so an index that dropped it, or coerced it to an empty
list, would turn `unverified` into a false `unbound`. An index from an earlier
contract is therefore *incompatible* rather than leniently read, and
`zuke doctor --fix` regenerates it. All four fact families participate in
`inputDigest`, so a hand-edited index fails its own digest check.

### Reconciling the two front ends' numbers

Three things make an editor count and a CLI count disagree without either being
wrong. All three have cost time on this repository, so they are written down.

**A finding appears twice in the JSON report.** `zuke validate --format json`
emits a combined `diagnostics` list *and* per-severity `errors`, `warnings` and
`infos` arrays. Every finding is in both, so counting `"code":` occurrences over
the whole document counts each one twice. A workspace with nine findings
produces eighteen. Count one array, or the `diagnostics` list, never the document.
This has silently halved and doubled real numbers before.

**Findings are on stderr; progress is on stdout.** A text-mode run prints
`Scenario bindings: N registered` to stdout and every finding line to stderr.
Parsing stdout alone therefore reports zero findings on a run that found plenty.

**Scope differs by design, and the CLI is always narrower.** The editor has no
profile and reports the whole workspace. `zuke validate` resolves a
`ScenarioSelector` first, and a profile must declare a non-empty
`tagExpression` — there is no unfiltered CLI mode to compare against. A
profile-scoped run can name fewer features and fewer affected scenarios while
reaching the same verdicts on everything it evaluates. Compare an editor total
with an editor total; compare CLI against CLI across two runs. Where they must be
compared directly, compare the verdict counts (`unbound`, `unverified`), which
are scope-independent, rather than the per-feature summaries, which are not.

## Content validation

A receipt binds the snapshot's SHA-256 to a deterministic digest of the synthetic
pubspec, lockfile, package configuration, entrypoint, selected SDK identity, and
every resolved path dependency's pubspec, overrides, and complete `lib` tree.
That includes local dependencies other than Zuke and detects new/deleted files,
not just edits to existing files. Each audit hashes content again. Touching a
file alone does not invalidate the receipt; preserving timestamps cannot hide
changed content. Hosted dependency identity comes from the lock/configuration;
editing supposedly immutable hosted-cache sources is outside this audit.
SDK identity stays in the receipt: the same package configuration can compile
to a different AOT under a different Dart SDK, so removing it would let an old
snapshot appear verified. A toolchain upgrade may make many receipts stale;
`--current-context` limits the immediate repair to the entry being used.

Repair runs `dart pub get` using the selected SDK, fingerprints the resulting
graph, compiles a temporary AOT with a depfile, replaces the snapshot, and records
the receipt only if sources remained unchanged and the installed snapshot
matches the compiler output. Compiler failures preserve the old snapshot.
Repairs of different entries can run concurrently; a per-entry lock serializes
two doctor runs repairing the same entry. The analysis server does not honor
that lock; a later external snapshot replacement invalidates the receipt on
the next audit. Stop analysis and retry if a concurrent write is detected.
Each repair hashes local sources both before and after compilation because an
editor or checkout can change them during the compile. Removing the second hash
would allow a mixed-source snapshot to receive a trusted receipt.

Cache paths are `%LOCALAPPDATA%/.dartServer/.plugin_manager` on Windows and
`~/.dartServer/.plugin_manager` elsewhere. Linked cache entries are not repaired.
Missing local sources are reported without deletion. Age-based orphan cleanup
is intentionally deferred: age does not establish that another workspace no
longer needs a cache, and unrelated plugins may share an entry.

## Release checks

`zuke_analyzer` remains repository-only (`publish_to: none`). The guide must not
advertise a nonexistent hosted release. Its first contract-aware version is
`0.1.1`; the initial versioned index contract is `1`. Contract `2` and
`zuke_analyzer` `0.1.2` add the binding-coverage facts described above; the
strictness of that read is the reason a contract bump was required rather than an
optional field.

For each JSON shape **or editor-visible semantic** change:

1. Increase `zukeIndexContract` and `zuke_analyzer`'s package version; update the
   release matrix and add behavior regression tests.
2. Run `dart run tool/update_editor_contract.dart` and regenerate committed
   example indexes.
3. Run the CLI contract test, analyzer tests, and
   `dart run tool/check_editor_contract.dart <base-ref>`.

The golden extracts literal serializer keys from the AST, including conditional
fields, rather than relying on a fixture that may omit optional fields. PR CI
compares it with the base commit and rejects schema changes without a contract
bump, or contract changes without a plugin version change. Key snapshots cannot
detect arbitrary semantic changes or every type change; those still require
review and behavior tests. Do not treat a golden as a proof of compatibility.

If the plugin is published later, use an explicitly updated supported plugin
version/spec with matching CLI releases. For Git consumption, pin a commit and
ensure the complete dependency graph is distributable. Merely bumping a package
version does not guarantee that an unchanged plugin constraint selects a new
cache key. A guarantee that released users can *never* encounter mixed versions
would be stronger than this mechanism provides; the handshake makes the mixed
state explicit and recoverable.

## Commit review: eb448d9

The earlier three items are addressed: generation projects implementation and
verification claims from one resolved scan, constant lookup uses Dart element
identity rather than workspace-global names, and `_inputDigest` uses named
arguments. Target scoping is shared by the editor and validator, and imported
workspace constants participate in freshness checks. The parser change records
metadata locations under their correct fields.

This follow-up fixes delimiter-based claim and spec-finding deduplication, adds the compatibility
boundary that the new index shape lacked, corrects hosted-install instructions,
and nests the repository's diagnostic configuration under its plugin. The
existing `editor.dart` API already avoids importing the full extractor into the
plugin. Moving index diagnostics to a smaller standalone package or a generated
diagnostics feed remains a separate architectural change; it is not required to
ship the handshake and recovery command.

## Upstream proposals (prepared, not submitted)

For dart-lang/sdk: request content-based plugin snapshot invalidation (including
local transitive dependencies), and recomputation of plugin files when analysis
is restarted. Reproduce with a local constant change while restoring the
original file timestamp. A request merely to add timestamp checks would repeat
functionality already present in Dart 3.12.2.

For Dart-Code: propose a scoped **Dart: Clear Analyzer Plugin Cache** command
that coordinates cache invalidation with stopping/restarting plugin isolates,
and explains effects on synthetic entries shared by several plugins. Zuke's
doctor command provides local recovery while these upstream changes are assessed.

Content-addressed copying of the complete plugin closure and rewriting
`analysis_options.yaml` is deferred. It adds machine-specific configuration and
dependency-copying complexity without being necessary for the current recovery
workflow.
