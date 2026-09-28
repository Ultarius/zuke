# Analyzer plugin contract and cache recovery

`zuke doctor` audits local plugin caches. `zuke doctor --fix` resolves and
recompiles affected synthetic plugin packages, then writes content receipts.
Restart the analysis server or reload the editor after repair: replacing an AOT
file does not replace an isolate already running in the editor.

`zuke analyze -- <dart analyze arguments>` performs repair before starting a
fresh `dart analyze` process and returns its exit status. Run it at the workspace
root, or pass `--root`. `zuke generate` audits without modifying the plugin cache
(except that `--quiet` skips this optional audit).
`zuke init --editor vscode` installs a folder-open Doctor Check task and a manual
Doctor Fix task. VS Code still controls whether automatic tasks are permitted.

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
| Repair scope | All synthetic cache entries resolving the same local `zuke_analyzer` or `zuke_cli` roots as the workspace package configuration or a direct analyzer-plugin path in its options. Unrelated clones and hosted-only installations are not rebuilt. |
| Severity | Error, enabled by default. All other Zuke rules are suppressed on a contract mismatch. Users can still explicitly disable rules through analyzer configuration. |
| Version location | `contractVersion` in the analyzer index only; the constant lives in `zuke_cli/src/index_contract.dart` and is exported through `editor.dart`. |
| Missing version | Ordinary stale-index behavior; regenerate. `doctor --fix` regenerates a missing, malformed, or incompatible header. |
| Deletion vs rebuilding | Rebuild the selected snapshot instead of deleting its directory. A synthetic package can contain other plugins, and a rebuild permits a trustworthy content receipt. |

The contract is checked before decoding the rest of the index. This handles
both older and newer producer contracts even when their JSON shapes cannot be
read by the compiled plugin. The message describes a generator/plugin mismatch
rather than assuming which side is old.

## Content validation

A receipt binds the snapshot's SHA-256 to a deterministic digest of the synthetic
pubspec, lockfile, package configuration, entrypoint, selected SDK identity, and
every resolved path dependency's pubspec, overrides, and complete `lib` tree.
That includes local dependencies other than Zuke and detects new/deleted files,
not just edits to existing files. Each audit hashes content again. Touching a
file alone does not invalidate the receipt; preserving timestamps cannot hide
changed content. Hosted dependency identity comes from the lock/configuration;
editing supposedly immutable hosted-cache sources is outside this audit.

Repair runs `dart pub get` using the selected SDK, fingerprints the resulting
graph, compiles a temporary AOT with a depfile, replaces the snapshot, and records
the receipt only if sources remained unchanged and the installed snapshot
matches the compiler output. Compiler failures preserve the old snapshot.
Concurrent doctor repairs are serialized. The analysis server does not honor
that lock; a later external snapshot replacement invalidates the receipt on
the next audit. Stop analysis and retry if a concurrent write is detected.

Cache paths are `%LOCALAPPDATA%/.dartServer/.plugin_manager` on Windows and
`~/.dartServer/.plugin_manager` elsewhere. Linked cache entries are not repaired.
Missing local sources are reported without deletion. Age-based orphan cleanup
is intentionally deferred: age does not establish that another workspace no
longer needs a cache, and unrelated plugins may share an entry.

## Release checks

`zuke_analyzer` remains repository-only (`publish_to: none`). The guide must not
advertise a nonexistent hosted release. Its first contract-aware version is
`0.1.1`; the initial versioned index contract is `1`.

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
