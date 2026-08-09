# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-002
# epic: EPIC-CALC-001
# owner: platform-security
# status: active
# targets:
#   - backend
# pbis:
#   - PBI-CALC-003
# endpoints:
#   - id: calculator.evaluate
#     target: backend
#     usage: reference
# spec-end

@EPIC-CALC-001 @FEAT-CALC-002 @security
Feature: Protect the calculator service from malformed and abusive requests
  The API accepts only the small documented calculation contract. Oversized,
  excessive, and malformed requests are rejected before domain evaluation.
  Rejections must not expose implementation details or place raw malicious
  input into logs.

  Background:
    Given endpoint "calculator.evaluate" is available

  # rule-spec-begin
  # id: RULE-CALC-BODY-SIZE
  # securityProfile: calculator-public-endpoint
  # requires:
  #   - kind: control
  #     id: CTRL-CALC-BODY-SIZE
  #     target: backend
  #     cardinality: oneOrMore
  #     acceptableAssurance: [proven]
  # requiredEvidence: [api-contract, security-integration, gherkin-api]
  # rule-spec-end
  @PBI-CALC-003 @RULE-CALC-BODY-SIZE
  Rule: Requests exceeding the body-size limit are rejected before evaluation

    @SCN-CALC-OVERSIZED-BODY @negative @api @security @release
    Scenario: Reject an oversized request body
      Given an API request body exceeds the calculator body-size limit
      When the API client requests a calculation
      Then the API response status must be 413
      And the API error code must be "REQUEST_TOO_LARGE"
      And the calculator domain service must not be invoked
      And the response must not contain the rejected request body
      And the security event must contain only the correlation identifier and size category

  # rule-spec-begin
  # id: RULE-CALC-RATE-LIMIT
  # securityProfile: calculator-public-endpoint
  # requires:
  #   - kind: control
  #     id: CTRL-CALC-RATE-LIMIT
  #     target: backend
  #     cardinality: oneOrMore
  #     acceptableAssurance: [proven]
  # requiredEvidence: [security-integration, gherkin-api]
  # rule-spec-end
  @PBI-CALC-003 @RULE-CALC-RATE-LIMIT
  Rule: Excessive requests from one rate-limit identity are temporarily rejected

    @SCN-CALC-RATE-LIMIT @negative @api @security @merge
    Scenario: Apply rate limiting after the request budget is exhausted
      Given one API client has exhausted the calculator request budget
      When that API client requests another calculation
      Then the API response status must be 429
      And the response must include a valid retry-after value
      And the calculator domain service must not be invoked for the rejected request
      And other rate-limit identities must remain able to calculate

  # rule-spec-begin
  # id: RULE-CALC-ERROR-REDACTION
  # requires:
  #   - kind: control
  #     id: CTRL-CALC-ERROR-REDACTION
  #     target: backend
  #     cardinality: oneOrMore
  #     acceptableAssurance: [proven]
  #   - kind: control
  #     id: CTRL-CALC-LOG-REDACTION
  #     target: backend
  #     cardinality: oneOrMore
  #     acceptableAssurance: [proven]
  # requiredEvidence: [api-contract, security-integration, logging-verification, gherkin-api]
  # rule-spec-end
  @PBI-CALC-003 @RULE-CALC-ERROR-REDACTION
  Rule: Unexpected failures return a stable public error without internal details

    @SCN-CALC-UNEXPECTED-FAILURE @negative @resilience @api @security @release
    Scenario: Sanitize an unexpected internal calculation failure
      Given the calculator domain service raises an unexpected internal failure
      When the API client requests a calculation
      Then the API response status must be 500
      And the API error code must be "CALCULATION_FAILED"
      And the response must not contain an exception class
      And the response must not contain a stack trace
      And the response must not contain a source file path
      And the internal error log must contain the correlation identifier
      And the internal error log must not contain raw request headers
