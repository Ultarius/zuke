# spec-begin
# schemaVersion: 1
# id: FEAT-CALC-001
# epic: EPIC-CALC-001
# owner: calculator-team
# status: active
# targets:
#   - flutter
#   - backend
# pbis:
#   - PBI-CALC-001
#   - PBI-CALC-002
# bindings:
#   required:
#     - id: calculator.firstOperand
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: calculator.operatorSelector
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: calculator.secondOperand
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: calculator.calculateAction
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: calculator.display
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: calculator.errorMessage
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
# endpoints:
#   - id: calculator.evaluate
#     target: backend
#     method: POST
#     contract: packages/calculator_contracts/evaluate.schema.json
# events:
#   - calculator.calculation.completed
#   - calculator.calculation.rejected
# featureFlags:
#   - calculator_remote_engine_v1
# performance:
#   - id: PERF-CALC-EVALUATE-P95
#     target: backend
#     threshold: 100ms
#     percentile: 95
#     profile: calculator-standard-load
# spec-end

@EPIC-CALC-001 @FEAT-CALC-001
Feature: Evaluate basic arithmetic operations
  As a calculator user
  I want to evaluate common arithmetic operations
  So that I can obtain reliable results without understanding implementation details.

  The backend is authoritative while the remote calculator feature is enabled.
  Flutter presents inputs, results, and safe errors. Scientific functions,
  expression chaining, history synchronization, and accounts are excluded.

  Background:
    Given the calculator application is ready
    And the remote calculator feature is enabled

  # rule-spec-begin
  # id: RULE-CALC-ADDITION
  # requiredEvidence: [{type: domain-unit, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: api-contract, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-api, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-001 @RULE-CALC-ADDITION
  Rule: Addition returns the arithmetic sum of two valid operands

    @SCN-CALC-ADD-INTEGERS-API @positive @domain @api @pr
    Scenario: Add two positive integers through the API
      Given the first operand is "2"
      And the selected operator is "+"
      And the second operand is "3"
      When the user requests the calculation
      Then the API response status must be 200
      And the API result must be "5"
      And event "calculator.calculation.completed" must be emitted once
      And the event must identify rule "RULE-CALC-ADDITION"

    @SCN-CALC-ADD-INTEGERS-UI @positive @ui @pr
    Scenario: Add two positive integers in the UI
      Given the first operand is "2"
      And the selected operator is "+"
      And the second operand is "3"
      When the user requests the calculation
      Then element "calculator.display" must display "5"

    @SCN-CALC-ADD-VALUES @positive @boundary @domain @api @merge
    Scenario Outline: Add representative valid operands
      Given the first operand is "<first>"
      And the selected operator is "+"
      And the second operand is "<second>"
      When the user requests the calculation
      Then the API response status must be 200
      And the API result must be "<result>"
      And no calculation error must be displayed

      Examples: Zero, negative, and decimal values
        | first | second | result |
        | 0     | 0      | 0      |
        | -2    | 3      | 1      |
        | 2.5   | 1.25   | 3.75   |
        | -4.5  | -0.5   | -5     |

  # rule-spec-begin
  # id: RULE-CALC-SUBTRACTION
  # requiredEvidence: [{type: domain-unit, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: api-contract, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-api, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-001 @RULE-CALC-SUBTRACTION
  Rule: Subtraction returns the second operand subtracted from the first operand

    @SCN-CALC-SUBTRACT @positive @domain @api @ui @pr
    Scenario: Subtract a larger second operand
      Given the first operand is "3"
      And the selected operator is "-"
      And the second operand is "5"
      When the user requests the calculation
      Then the API response status must be 200
      And the API result must be "-2"
      And element "calculator.display" must display "-2"

  # rule-spec-begin
  # id: RULE-CALC-MULTIPLICATION
  # requiredEvidence: [{type: domain-unit, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: api-contract, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-api, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-001 @RULE-CALC-MULTIPLICATION
  Rule: Multiplication returns the arithmetic product of two valid operands

    @SCN-CALC-MULTIPLY @positive @domain @api @ui @pr
    Scenario: Multiply decimal operands
      Given the first operand is "2.5"
      And the selected operator is "×"
      And the second operand is "4"
      When the user requests the calculation
      Then the API response status must be 200
      And the API result must be "10"
      And element "calculator.display" must display "10"

  # rule-spec-begin
  # id: RULE-CALC-DIVISION
  # requires:
  #   - kind: control
  #     id: CTRL-CALC-ERROR-REDACTION
  #     target: backend
  #     cardinality: oneOrMore
  # requiredEvidence: [{type: domain-unit, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: api-contract, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: security-integration, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-api, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-002 @RULE-CALC-DIVISION
  Rule: Division returns the first operand divided by a non-zero second operand

    @SCN-CALC-DIVIDE @positive @domain @api @ui @pr
    Scenario: Divide two exactly divisible integers
      Given the first operand is "10"
      And the selected operator is "÷"
      And the second operand is "2"
      When the user requests the calculation
      Then the API response status must be 200
      And the API result must be "5"
      And element "calculator.display" must display "5"

    @SCN-CALC-DIVIDE-DECIMAL @positive @boundary @domain @api @merge
    Scenario: Divide operands producing a decimal result
      Given the first operand is "1"
      And the selected operator is "÷"
      And the second operand is "4"
      When the API client requests a calculation
      Then the API response status must be 200
      And the API result must be "0.25"

    @SCN-CALC-DIVIDE-ZERO @negative @security @domain @api @ui @pr
    Scenario: Reject division by zero without leaking an internal error
      Given the first operand is "10"
      And the selected operator is "÷"
      And the second operand is "0"
      When the user requests the calculation
      Then the API response status must be 422
      And the API error code must be "DIVISION_BY_ZERO"
      And element "calculator.errorMessage" must display message key "calculator.error.divisionByZero"
      And the previous successful result must not be replaced with a numeric result
      And the response must not contain a stack trace
      And the response must not contain a source file path
      And event "calculator.calculation.rejected" must be emitted once
      And the rejected event must not contain raw request headers

  # rule-spec-begin
  # id: RULE-CALC-UI-VALIDATION
  # requiredEvidence: [{type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-002 @RULE-CALC-UI-VALIDATION
  Rule: Flutter validates required operands before submitting

    @SCN-CALC-MISSING-FIRST @negative @validation @ui @pr
    Scenario: Reject a calculation with no first operand in Flutter
      Given the first operand is empty
      And the selected operator is "+"
      And the second operand is "3"
      When the user requests the calculation
      Then the calculation request must not be sent by the Flutter application
      And element "calculator.errorMessage" must display message key "calculator.error.firstOperandRequired"
      And focus must move to element "calculator.firstOperand"

    @SCN-CALC-MISSING-OPERATOR @negative @validation @ui @pr
    Scenario: Reject a calculation with no selected operator in Flutter
      Given the first operand is "2"
      And no operator is selected
      And the second operand is "3"
      When the user requests the calculation
      Then the calculation request must not be sent by the Flutter application
      And element "calculator.errorMessage" must display message key "calculator.error.unsupportedOperator"

    @SCN-CALC-MISSING-SECOND @negative @validation @ui @pr
    Scenario: Reject a calculation with no second operand in Flutter
      Given the first operand is "2"
      And the selected operator is "+"
      And the second operand is empty
      When the user requests the calculation
      Then the calculation request must not be sent by the Flutter application
      And element "calculator.errorMessage" must display message key "calculator.error.secondOperandRequired"
      And focus must move to element "calculator.secondOperand"

  # rule-spec-begin
  # id: RULE-CALC-UI-FAILURE
  # requiredEvidence: [{type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-002 @RULE-CALC-UI-FAILURE
  Rule: Flutter presents a safe generic message for unexpected calculation failures

    @SCN-CALC-CALCULATION-FAILED @negative @resilience @ui @pr
    Scenario: Show a generic message when the calculator service fails unexpectedly
      Given the calculator service returns an unexpected calculation failure
      When the user requests the calculation
      Then element "calculator.errorMessage" must display message key "calculator.error.calculationFailed"

  # rule-spec-begin
  # id: RULE-CALC-VALIDATION
  # requires:
  #   - kind: control
  #     id: CTRL-CALC-INPUT-VALIDATION
  #     target: backend
  #     cardinality: oneOrMore
  # requiredEvidence: [{type: domain-unit, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: api-contract, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: security-integration, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}, {type: gherkin-api, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}]
  # rule-spec-end
  @PBI-CALC-002 @RULE-CALC-VALIDATION
  Rule: Only supported finite numeric operands and operators are accepted

    @SCN-CALC-BAD-OPERATOR @negative @validation @api @security @merge
    Scenario: Reject an operator outside the registered operator set
      Given an API client supplies first operand "2"
      And the API client supplies operator "exec"
      And the API client supplies second operand "3"
      When the API client requests a calculation
      Then the API response status must be 400
      And the API error code must be "UNSUPPORTED_OPERATOR"
      And no calculation-completed event must be emitted
      And no executable input must be evaluated

    @SCN-CALC-BAD-OPERAND @negative @validation @api @security @merge
    Scenario Outline: Reject non-numeric operand input
      Given an API client supplies first operand "<input>"
      And the API client supplies operator "+"
      And the API client supplies second operand "3"
      When the API client requests a calculation
      Then the API response status must be 400
      And the API error code must be "INVALID_OPERAND"
      And the response must not reflect the raw invalid operand
      And no calculation-completed event must be emitted

      Examples: Representative invalid input classes
        | input                     |
        | one                       |
        | NaN                       |
        | Infinity                  |
        | <script>alert(1)</script> |
        | ../../configuration       |

  # rule-spec-begin
  # id: RULE-CALC-ACCESSIBILITY
  # requiredEvidence: [{type: flutter-widget, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: accessibility-integration, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}, {type: gherkin-ui, target: flutter, sourcePackage: calculator-mobile, sourceAdapter: flutter-test, variant: default}]
  # rule-spec-end
  @PBI-CALC-002 @RULE-CALC-ACCESSIBILITY
  Rule: Calculator controls expose understandable accessible names and results

    @SCN-CALC-ACCESSIBLE @accessibility @ui @merge
    Scenario: Complete a calculation using accessible controls
      Given the calculator is operated using keyboard navigation
      When the user enters first operand "2"
      And the user selects operator "+"
      And the user enters second operand "3"
      And the user activates the calculate action
      Then element "calculator.display" must display "5"
      And element "calculator.display" must expose accessible name "Result: 5"
      And the calculate action must expose accessible name "Calculate"
      And focus order must follow first operand, operator, second operand, calculate action, and result

  # rule-spec-begin
  # id: RULE-CALC-PERFORMANCE
  # requiredEvidence: [{type: performance, target: backend, sourcePackage: calculator-api, sourceAdapter: dart-source, variant: default}]
  # rule-spec-end
  @PBI-CALC-002 @RULE-CALC-PERFORMANCE
  Rule: Calculation latency remains within the service budget

    @SCN-CALC-P95 @performance @api @nightly
    Scenario: Standard load satisfies the p95 latency budget
      Given load profile "calculator-standard-load" is active
      When calculations are requested for the configured performance duration
      Then endpoint "calculator.evaluate" must complete within 100 milliseconds at percentile 95
      And the error rate must remain below 1 percent
