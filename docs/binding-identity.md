# Binding Identity and Proof Ownership

Zuke separates placement, semantic binding, and proof:

- the workspace owns **where** a binding runs: target and package membership;
- an annotation owns **what** it binds: requirement/control ID, variant, and slot;
- the proof engine owns **how** it is established: one validator for each
  obligation.

## Binding identity

Every source binding has the normalized identity:

```text
(subjectKind, subjectId, target, role, variant, slot)
```

`variant` defaults to `default` and describes a semantic alternative. `slot`
defaults to `primary` and identifies an independent occurrence of the same
meaning. They are not interchangeable:

```dart
@ImplementsRequirement(['RULE-ACCESS-NORMALIZATION'], slot: 'create')
class CreateLobbyUseCase {}

@ImplementsRequirement(['RULE-ACCESS-NORMALIZATION'], slot: 'join')
class JoinLobbyUseCase {}
```

`create` and `join` are two AND obligations. A passing test for one does not
prove the other. Use a different requirement or variant for OR semantics.
Slots are stable lowercase kebab-case tokens. Do not derive them from class
names, files, routes, HTTP methods, versions, or other incidental names.

Annotations do not choose a workspace target. Remove placement `target` fields
from `ImplementsRequirement`, `PresentsRequirement`, `ZukeBinding`, and
`VerifiesRequirement`. The CLI resolves placement from package membership and
the active extraction target. Ambiguous or unassigned placement fails closed;
there is no `backend` or `flutter` fallback.

## Proof ownership

The CLI builds obligations before validators run. Structural controls and
topology-authoritative implementation bindings go to graph reachability and
dominance validation. Verification-backed controls and annotation-governed
implementation bindings go to provider/evidence validation. A control or
binding is never sent to both owners.

Topology-authoritative packages require an exact reachable implementation node;
managed evidence cannot replace reachability. Annotation-governed packages
require the exact extracted binding plus current passing managed evidence. All
implementation slots are required by default.

Ordinary control/evidence obligations remain specification-defined and are not
copied once per implementation slot. Only evidence that explicitly claims
implementation coverage carries implementation slot claims.

The public adapter compatibility ID `dart-source-package-v1` remains stable;
identity or proof-engine changes use internal cache/engine revisions unless the
serialized adapter contract changes.
