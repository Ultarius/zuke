# spec-begin
# schemaVersion: 1
# id: FEAT-LIBRARY-001
# epic: EPIC-LIBRARY-001
# owner: library-team
# status: active
# targets:
#   - catalog
# pbis:
#   - PBI-LIBRARY-001
# bindings:
#   required:
#     - id: library.isbnInput
#       target: catalog
#       cardinality: exactlyOne
#       interaction: input
#     - id: library.checkoutButton
#       target: catalog
#       cardinality: exactlyOne
#       interaction: action
#     - id: library.loanList
#       target: catalog
#       cardinality: exactlyOne
#       interaction: output
#     - id: library.loanCountDisplay
#       target: catalog
#       cardinality: exactlyOne
#       interaction: output
#     - id: library.errorMessage
#       target: catalog
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: library.statusMessage
#       target: catalog
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
# spec-end

@EPIC-LIBRARY-001 @FEAT-LIBRARY-001
Feature: Library book checkout desk
  As a librarian
  I want to check out books by ISBN and track active loans
  So that the catalog stays accurate and overdue loans are prevented.

  The checkout controller validates ISBN shape and loan limits before
  mutating the loan register. Generated contracts are the source of truth
  for binding and requirement identifiers.

  Background:
    Given the checkout desk is open
    And the loan register is empty

  # rule-spec-begin
  # id: RULE-LIBRARY-CHECKOUT
  # requiredEvidence: [{type: domain-unit, target: catalog, sourcePackage: library-catalog, sourceAdapter: dart-source, variant: default}]
  # securityProfile: library-validation-profile
  # rule-spec-end
  @PBI-LIBRARY-001 @RULE-LIBRARY-CHECKOUT
  Rule: Valid ISBNs create a loan and invalid input is rejected

    @SCN-LIBRARY-CHECKOUT-VALID @pr @merge @release
    Scenario: Check out a book with a valid ISBN
      When the librarian enters ISBN "9780134685991" into "library.isbnInput"
      And the librarian taps "library.checkoutButton"
      Then element "library.loanCountDisplay" displays "1 loan"
      And element "library.loanList" displays "Effective Dart"

    @SCN-LIBRARY-CHECKOUT-BAD-ISBN @negative @pr @merge
    Scenario: Reject a malformed ISBN
      When the librarian enters ISBN "not-an-isbn" into "library.isbnInput"
      And the librarian taps "library.checkoutButton"
      Then element "library.errorMessage" displays "ISBN must be 10 or 13 digits"
      And element "library.loanCountDisplay" displays "0 loans"

    @SCN-LIBRARY-CHECKOUT-EMPTY @negative @pr @merge
    Scenario: Reject an empty ISBN
      When the librarian enters ISBN "" into "library.isbnInput"
      And the librarian taps "library.checkoutButton"
      Then element "library.errorMessage" displays "ISBN must be 10 or 13 digits"

    @SCN-LIBRARY-CHECKOUT-LIMIT @negative @pr @merge
    Scenario: Reject checkout beyond the active loan limit
      Given the librarian has 3 active loans
      When the librarian enters ISBN "9780134685991" into "library.isbnInput"
      And the librarian taps "library.checkoutButton"
      Then element "library.errorMessage" displays "Active loan limit reached"

  # rule-spec-begin
  # id: RULE-LIBRARY-BOOK-RETURN
  # requiredEvidence: [{type: domain-unit, target: catalog, sourcePackage: library-catalog, sourceAdapter: dart-source, variant: default}]
  # rule-spec-end
  @PBI-LIBRARY-001 @RULE-LIBRARY-BOOK-RETURN
  Rule: Returning a book removes the loan and updates the count

    @SCN-LIBRARY-RETURN @pr @merge
    Scenario: Return a checked-out book
      Given the librarian has an active loan for ISBN "9780134685991"
      When the librarian returns the loan for ISBN "9780134685991"
      Then element "library.loanCountDisplay" displays "0 loans"
      And element "library.statusMessage" displays "Loan returned"

  # rule-spec-begin
  # id: RULE-LIBRARY-BRANCH-PEER
  # requiredEvidence: [{type: domain-unit, target: catalog, sourcePackage: library-catalog, sourceAdapter: dart-source, variant: default}]
  # rule-spec-end
  @PBI-LIBRARY-001 @RULE-LIBRARY-BRANCH-PEER
  Rule: Branches connect peer-to-peer to share loan state

    @SCN-LIBRARY-PEER-CONNECT @pr @merge
    Scenario: Two branches establish a peer connection
      Given branch "north" is listening for peers
      And branch "south" is listening for peers
      When branch "north" connects to branch "south"
      Then the peer connection between "north" and "south" is established
      And branch "north" reports peer state "connected"

    @SCN-LIBRARY-PEER-SYNC @pr @merge @release
    Scenario: Share active loans across a peer connection
      Given branch "north" is listening for peers
      And branch "south" is listening for peers
      And branch "north" connects to branch "south"
      And branch "north" has local loan ISBN "9780134685991"
      When branch "north" shares its loan register with branch "south"
      Then branch "south" receives loan ISBN "9780134685991"
