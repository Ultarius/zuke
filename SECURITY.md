# Security policy

## Reporting a vulnerability

Report security vulnerabilities in Zuke privately through GitHub Security
Advisories on [Ultarius/zuke](https://github.com/Ultarius/zuke). Open a draft
advisory at:

https://github.com/Ultarius/zuke/security/advisories/new

Choose "Report a vulnerability" so the report stays private until a fix is
available. Do **not** open a public issue, discussion, or pull request for an
unfixed vulnerability.

Include in the report:

- The affected Zuke SDK package(s) (for example `zuke_core`, `zuke_cli`,
  `zuke_runner_flutter`) and version(s), or the commit SHA if unreleased.
- A clear description of the issue, its security impact, and the conditions
  required to trigger it.
- Reproduction steps or a minimal proof of concept.
- Any known workarounds or suggested fixes.
- Your preferred credit name, or a request to remain anonymous.

## Scope

In scope:

- The published Zuke SDK packages under `vendor-sdk/` that ship to pub.dev
  (`zuke`, `zuke_core`, `zuke_annotations`, `zuke_frontend`, `zuke_runner`,
  `zuke_runner_flutter`, `zuke_http_runtime`, `zuke_cli`,
  `zuke_dart_build_hook`).
- The release signing, evidence verification, and assurance lock/history
  tooling in this repository, including weaknesses that would let a consumer be
  fooled by forged, swapped, or stale evidence.

Out of scope:

- The example applications under `examples/` (reference material, not shipped).
- Vulnerabilities in third-party dependencies — report those upstream; GitHub
  dependency advisories are tracked automatically by the dependency review
  workflow.
- Denial of service against GitHub, pub.dev, or this repository's availability.
- Social engineering, physical attacks, and issues requiring access to a
  consumer's already-compromised environment.

## Response expectations

- A maintainer acknowledges valid reports within **7 days**.
- Triage status is updated at least every **14 days** after acknowledgment until
  resolution.
- Fixes are developed privately in a draft advisory; a CVE is requested through
  GitHub when warranted.
- Public disclosure is coordinated: the advisory is published when a patched
  release is available (or an agreed date is reached if a fix is not possible).
- Reporters are credited in the advisory unless they request anonymity.

These are best-effort targets for a solo-maintainer project; if a report is out
of scope, you will be told so during triage.

## What not to include publicly

- No exploit details, proof-of-concept code, credentials, private keys, or
  signing material in public issues, discussions, PRs, or the advisory
  discussion before a fix ships.
- No secrets or production data of any kind — attach sensitive artifacts only
  inside the private advisory timeline.
- Do not test against infrastructure you do not own (for example the
  `release-signing` environment or Azure signing provider).
- Once a fix is released, keep working exploit details in the private advisory;
  the public summary should stay at the level needed for consumers to judge
  impact and upgrade.
