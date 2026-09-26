void printZukeHelp({required String version}) {
  print('''
zuke $version - Gherkin-Driven Specification Engine

Usage:
  zuke validate     Validate specification files
  zuke generate     Generate contract code from specifications
  zuke extract dart Extract resolved Dart annotations
  zuke trace RULE-ID Show requirement trace
  zuke report       Emit compiled spec model JSON (zuke-model.json)
  zuke lock --profile <name>|--all-profiles  Write or check profile locks
  zuke lock --update                     Refresh selected locks transactionally
  zuke lock --refresh                    Regenerate contracts, reuse current evidence or run tests, and refresh locks
  zuke lock --refresh --retest           Execute managed tests even when evidence is current
  zuke gate         Run validate, generation, and lock gates
  zuke check        Verify one or more workspaces with isolated stage output
  zuke check --coverage  Collect coverage from test runners during the test stage
  zuke manifest create|verify|export  Manage trusted Ed25519 history
  zuke attestation create           Create a signed external-control attestation
  zuke gateway canonicalize-apim    Canonicalize APIM gateway evidence
  zuke artifacts audit              Audit the exact upload artifact bundle
  zuke artifacts package            Build and audit an upload artifact bundle
  zuke contract verify --openapi    Compare OpenAPI paths with route topology
  zuke policy check                 Validate consumer risk acceptance
  zuke doctor       Diagnose project setup
  zuke doctor --check-alignment  Check the supported Zuke dependency tuple
  zuke doctor --check-overrides   Reject release-unsafe dependency overrides
  zuke doctor test-host  Explain Flutter/test SDK compatibility
  zuke clean        Remove Zuke test temporary directories
  zuke init         Create a starter configuration
  zuke watch        Run generation and validation once
  zuke affected     List requirements affected by a git change
  zuke test         Run configured verification suites
  zuke test --coverage  Collect coverage from test runners
  zuke coverage     Evaluate LCOV as an independent quality gate
  zuke certify hosted  Certify the published tuple (framework checkout only)
  zuke --help       Show this help
  zuke --version    Show version
''');
}
