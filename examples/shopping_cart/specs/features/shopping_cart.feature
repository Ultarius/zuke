# spec-begin
# schemaVersion: 1
# id: FEAT-CART-001
# epic: EPIC-SHOPPING-001
# owner: shopping-team
# status: active
# targets:
#   - flutter
# pbis:
#   - PBI-CART-001
# bindings:
#   required:
#     - id: shopping.addToCartHeadphones
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: shopping.promoInput
#       target: flutter
#       cardinality: exactlyOne
#       interaction: input
#     - id: shopping.applyPromoButton
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: shopping.checkoutButton
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: shopping.cartBadge
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: shopping.subtotalDisplay
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: shopping.discountStatusDisplay
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: shopping.totalDisplay
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: shopping.statusMessageDisplay
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: zeroOrOne
#       interaction: output
#     - id: shopping.catalogItemName
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
#     - id: shopping.catalogItemPrice
#       target: flutter
#       cardinality: exactlyOne
#       interaction: output
# spec-end

@EPIC-SHOPPING-001 @FEAT-CART-001
Feature: E-Commerce Shopping Cart & Checkout
  As a shopper
  I want to add items to my shopping cart, apply promotional discount codes, and complete checkout
  So that I can purchase desired products with accurate subtotal, discount, and order totals.

  The Flutter UI presents item selection, subtotal calculation, promo code application, and accessible order summary handles.

  Background:
    Given the shopping application is open

  # rule-spec-begin
  # id: RULE-CART-ITEM-MANAGEMENT
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: cart-validation-profile
  # rule-spec-end
  @RULE-CART-ITEM-MANAGEMENT
  Rule: Item Selection and Cart Subtotal Calculation

    @SCN-CART-ADD-ITEM @pr @merge
    Scenario: Add item to cart and verify updated subtotal
      Given the catalog item "Wireless Headphones" is listed at price "$100.00"
      When the user taps "shopping.addToCartHeadphones"
      Then element "shopping.cartBadge" displays "1"
      And element "shopping.subtotalDisplay" displays "$100.00"

    @SCN-CART-ADD-SECOND-ITEM @pr @merge
    Scenario: Add same item twice and verify updated quantity and subtotal
      Given the catalog item "Wireless Headphones" is listed at price "$100.00"
      When the user taps "shopping.addToCartHeadphones"
      And the user taps "shopping.addToCartHeadphones"
      Then element "shopping.cartBadge" displays "2"
      And element "shopping.subtotalDisplay" displays "$200.00"

  # rule-spec-begin
  # id: RULE-CART-PROMO-DISCOUNT
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: promo-validation-profile
  # rule-spec-end
  @RULE-CART-PROMO-DISCOUNT
  Rule: Promo Code Application and Validation

    @SCN-CART-APPLY-PROMO @pr @merge
    Scenario Outline: Apply valid discount code and recalculate grand total
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user enters "<promo>" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      Then element "shopping.discountStatusDisplay" displays "Discount Applied: <discount>"
      And element "shopping.totalDisplay" displays "<total>"

      Examples:
        | promo  | discount | total  |
        | SAVE20 | 20%      | $80.00 |
        | SAVE50 | 50%      | $50.00 |
        | save20 | 20%      | $80.00 |

    @SCN-CART-INVALID-PROMO @negative @pr @merge
    Scenario: Reject an invalid promo code
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user enters "NOPE" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      Then element "shopping.statusMessageDisplay" displays "Invalid promo code"
      And element "shopping.totalDisplay" displays "$100.00"

    @SCN-CART-PROMO-EMPTY-CART @negative @pr @merge
    Scenario: Reject promo code on empty cart
      Given the cart is completely empty
      When the user enters "SAVE20" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      Then element "shopping.statusMessageDisplay" displays "Add an item before applying a promo code"

    @SCN-CART-EMPTY-PROMO @negative @pr @merge
    Scenario: Reject submitting an empty promo code
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user enters "" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      Then element "shopping.statusMessageDisplay" displays "Please enter a promo code"
      And element "shopping.totalDisplay" displays "$100.00"

  # rule-spec-begin
  # id: RULE-CART-EMPTY-CHECKOUT
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: cart-validation-profile
  # rule-spec-end
  @RULE-CART-EMPTY-CHECKOUT
  Rule: Empty Cart Checkout Prevention

    @SCN-CART-EMPTY-CHECKOUT @negative @pr @merge @release
    Scenario: Prevent checkout when the cart is empty
      Given the cart is completely empty
      Then the checkout button state must be disabled

  # rule-spec-begin
  # id: RULE-CART-SUCCESSFUL-CHECKOUT
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: cart-validation-profile
  # rule-spec-end
  @RULE-CART-SUCCESSFUL-CHECKOUT
  Rule: Successful Checkout

    @SCN-CART-SUCCESS-CHECKOUT @pr @merge
    Scenario: Successfully place order with items in cart and reset promo state
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user enters "SAVE20" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      And the user taps "shopping.checkoutButton"
      Then element "shopping.statusMessageDisplay" displays "Order placed successfully!"
      And element "shopping.cartBadge" displays "0"
      And element "shopping.subtotalDisplay" displays "$0.00"
      And element "shopping.totalDisplay" displays "$0.00"
      And element "shopping.discountStatusDisplay" is not present

  # rule-spec-begin
  # id: RULE-CART-ACCESSIBILITY
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: flutter-test, variant: default}]
  # securityProfile: cart-accessible-profile
  # rule-spec-end
  @RULE-CART-ACCESSIBILITY
  Rule: Cart Summary Screen Reader Accessibility

    @SCN-CART-ACCESSIBLE @pr @merge
    Scenario: Expose total order summary via semantics handle
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user views the checkout summary
      Then the semantics tree must contain label matching "Order Total: $100.00"
