# Examples of good feature files

Complete features to model a draft on. The order domain, tags, and data are placeholders; real rules and expected values come from the project. Write step text in the project's natural language and keyword set, and reuse existing step wording where a binding already exists.

## API feature: the consuming app is the observer

```gherkin
@api @authentication @orders
Feature: Retrieve order data
  A client can retrieve the data of an order so the customer sees the current status and contents.

  Rule: An authenticated client receives the data of an existing order

    Scenario Outline: The client receives a summary of an order
      Given an authenticated customer with an existing order in status '<status>'
      When the client requests the order data
      Then the client receives a summary of the order
      And the order has status '<status>'
      And the summary contains:
        | field         |
        | order number  |
        | status        |
        | total amount  |

      Examples: Orders per status
        | status    |
        | received  |
        | shipped   |

  Rule: Without valid authentication, protected order data is unavailable

    Scenario: A client without valid authentication cannot retrieve order data
      Given the client has no valid authentication
      When the client requests data of a protected order
      Then the request is refused because authentication is missing (401)
```

Why this works:
- The observer is the client, which matches what the bindings can verify: an API response.
- Each rule has a success case and a rejection case.
- Each examples row covers a different order status, and the scenario asserts that status in the response.
- The data table lists *which* fields are checked; the step definition compares them with expected values.
- The 401 appears as an observable outcome for the calling app. The endpoint path stays in the step definition.

## UI feature: the user is the observer

```gherkin
@ui @orders @order-details
Feature: View an order
  A customer can view the contents and status of an order so they know what will be delivered.

  Background:
    Given a signed-in customer with an existing order

  Rule: The customer sees which items were ordered

    Scenario: The customer views the items in an order
      When the customer views the order
      Then the customer sees the ordered items:
        | item     |
        | product  |
        | quantity |

  Rule: The customer sees the total amount of the order

    Scenario: The customer views the total amount
      When the customer views the order summary
      Then the customer sees the order total

  Rule: The customer can open the order confirmation

    Scenario: The customer opens the confirmation from the order details
      Given the customer views the order details
      When the customer opens the order confirmation
      Then the customer sees the order confirmation
```

Why this works:
- No swipes, taps, or buttons: "the customer views the order" hides navigation; "the customer opens the order confirmation" hides the button.
- The login context is short and shared, so it belongs in `Background`.
- Data tables replace long chains of near-identical `And the user sees …` steps.
- One-row outlines became plain scenarios.

## Boundary examples in an outline

```gherkin
  Rule: An order cannot request more items than are in stock

    Scenario Outline: The requested quantity is compared with available stock
      Given <available> units of an item are available
      When the customer orders <requested> units
      Then the order is <result>

      Examples: Below, at, and above the stock boundary
        | available | requested | result    |
        | 5         | 4         | accepted  |
        | 5         | 5         | accepted  |
        | 5         | 6         | rejected  |
```

Why this works: the rows sit on both sides of the boundary, the table label says so, and each row can only pass if the rule is implemented correctly.

## Rewrite: a scripted outline becomes a specification

```gherkin
# Before: UI scripting (1), a vague outcome (6), a one-row outline (10)
Scenario Outline: A customer opens the details of an order
  Given a signed-in customer with customer number '<customer number>'
  And the customer views the order overview
  When the customer swipes down to see more details
  And the customer clicks the Order button
  Then the customer is successfully navigated to the order details

  Examples: Customers
    | customer number |
    | K-104           |
```

```gherkin
# After
Scenario: The customer views the details of an order
  Given a signed-in customer with an existing order
  When the customer views the order
  Then the customer sees the order details
```

The swipe and the tap move into the binding for "the customer views the order". The customer number moves into the binding's test data. The one-row outline becomes a plain scenario, and "successfully navigated" becomes the thing the customer sees.
