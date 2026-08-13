# spec-begin
# schemaVersion: 1
# id: FEAT-HOSTED-001
# epic: EPIC-HOSTED-001
# owner: zuke-release
# status: active
# targets:
#   - fixture
# spec-end

@EPIC-HOSTED-001 @FEAT-HOSTED-001
Feature: Hosted consumer certification

  # rule-spec-begin
  # id: RULE-HOSTED-ADD
  # requiredEvidence: [{type: domain-unit, target: fixture, sourcePackage: hosted-consumer, sourceAdapter: dart-source, variant: default}]
  # rule-spec-end
  @RULE-HOSTED-ADD
  Rule: Add values

    @SCN-HOSTED-ADD @pr @merge @release @nightly
    Scenario: Add two values
      Given the hosted consumer is configured
      Then adding two values returns the expected sum
