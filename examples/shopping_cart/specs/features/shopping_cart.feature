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
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: dart-source, variant: default}]
  # securityProfile: cart-validation-profile
  # rule-spec-end
  @RULE-CART-ITEM-MANAGEMENT
  Rule: Adding a catalog item updates the quantity and subtotal

    @SCN-CART-ADD-ITEM @pr @merge
    Scenario: Adding an item updates the cart subtotal
      Given the catalog item "Wireless Headphones" is listed at price "$100.00"
      When the user taps "shopping.addToCartHeadphones"
      Then element "shopping.cartBadge" displays "1"
      And element "shopping.subtotalDisplay" displays "$100.00"

    @SCN-CART-ADD-SECOND-ITEM @pr @merge
    Scenario: Adding the same item twice updates the quantity and subtotal
      Given the catalog item "Wireless Headphones" is listed at price "$100.00"
      When the user taps "shopping.addToCartHeadphones"
      And the user taps "shopping.addToCartHeadphones"
      Then element "shopping.cartBadge" displays "2"
      And element "shopping.subtotalDisplay" displays "$200.00"

  # rule-spec-begin
  # id: RULE-CART-PROMO-DISCOUNT
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: dart-source, variant: default}]
  # securityProfile: promo-validation-profile
  # rule-spec-end
  @RULE-CART-PROMO-DISCOUNT
  Rule: A promo code discounts the total only when it is valid and the cart is not empty

    @SCN-CART-APPLY-PROMO @pr @merge
    Scenario Outline: A known discount code reduces the order total
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user enters "<promo>" into "shopping.promoInput"
      And the user taps "shopping.applyPromoButton"
      Then element "shopping.discountStatusDisplay" displays "Discount Applied: <discount>"
      And element "shopping.totalDisplay" displays "<total>"

      Examples: Discount codes and their discounts
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
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: dart-source, variant: default}]
  # securityProfile: cart-validation-profile
  # rule-spec-end
  @RULE-CART-EMPTY-CHECKOUT
  Rule: The cart cannot be checked out while it is empty

    @SCN-CART-EMPTY-CHECKOUT @negative @pr @merge @release
    Scenario: The checkout button is disabled for an empty cart
      Given the cart is completely empty
      When the user views the checkout summary
      Then the checkout button state must be disabled

  # rule-spec-begin
  # id: RULE-CART-SUCCESSFUL-CHECKOUT
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: dart-source, variant: default}]
  # securityProfile: cart-validation-profile
  # rule-spec-end
  @RULE-CART-SUCCESSFUL-CHECKOUT
  Rule: Placing an order empties the cart and clears the discount

    @SCN-CART-SUCCESS-CHECKOUT @pr @merge
    Scenario: Placing an order resets the cart and the discount
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
  # requiredEvidence: [{type: gherkin-ui, target: flutter, sourcePackage: shopping-cart, sourceAdapter: dart-source, variant: default}]
  # securityProfile: cart-accessible-profile
  # rule-spec-end
  @RULE-CART-ACCESSIBILITY
  Rule: The checkout summary exposes the order total to assistive technology

    @SCN-CART-ACCESSIBLE @pr @merge
    Scenario: The screen reader announces the order total
      Given the cart contains item "Wireless Headphones" at price "$100.00"
      When the user views the checkout summary
      Then the semantics tree must contain label matching "Order Total: $100.00"
