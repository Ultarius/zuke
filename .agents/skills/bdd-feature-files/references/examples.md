# Examples of good feature files

These examples use English Gherkin keywords and an imaginary order domain only to demonstrate structure. Treat names, rules, tags, and data as placeholders; confirm real behavior with domain experts before using them.

Step wording should match existing bindings where possible. New wording needs a corresponding step definition.

## API feature: the consuming app is the observer

```gherkin
@api @authentication @orders
Feature: Ordergegevens opvragen
  Een client kan gegevens van een bestelling opvragen zodat de klant de actuele status en inhoud kan zien.

  Rule: Een geauthenticeerde client ontvangt de gegevens van een bestaande bestelling

    Scenario Outline: De client ontvangt een samenvatting van een bestelling
      Given een geauthenticeerde klant met een bestaande bestelling in status '<status>'
      When de client de bestelgegevens opvraagt
      Then ontvangt de client een samenvatting van de bestelling
      And heeft de bestelling de status '<status>'
      And bevat de samenvatting:
        | veld          |
        | bestelnummer  |
        | status        |
        | totaalbedrag  |

      Examples: Bestellingen per status
        | status     |
        | ontvangen  |
        | verzonden  |

  Rule: Zonder geldige authenticatie zijn beschermde bestelgegevens niet beschikbaar

    Scenario: Een client zonder geldige authenticatie kan geen bestelgegevens opvragen
      Given de client heeft geen geldige authenticatie
      When de client gegevens van een beschermde bestelling opvraagt
      Then wordt het verzoek afgewezen wegens ontbrekende authenticatie (401)
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
Feature: Bestelling bekijken
  Een klant kan de inhoud en status van een bestelling bekijken, zodat die weet wat er geleverd wordt.

  Background:
    Given een ingelogde klant met een bestaande bestelling

  Rule: De klant ziet welke artikelen zijn besteld

    Scenario: De klant bekijkt de artikelen in een bestelling
      When de klant de bestelling bekijkt
      Then ziet de klant de bestelde artikelen:
        | artikel       |
        | product       |
        | hoeveelheid   |

  Rule: De klant ziet het totaalbedrag van de bestelling

    Scenario: De klant bekijkt het totaalbedrag
      When de klant het besteloverzicht bekijkt
      Then ziet de klant het totaalbedrag van de bestelling

  Rule: De klant kan de bestelbevestiging openen

    Scenario: De klant opent de bevestiging vanuit de bestelgegevens
      Given de klant bekijkt de bestelgegevens
      When de klant de bestelbevestiging opent
      Then ziet de klant de bestelbevestiging
```

Why this works:
- No swipes, taps, or buttons: "de klant bekijkt de bestelling" hides navigation; "de klant opent de bestelbevestiging" hides the button.
- The login context is short and shared, so it belongs in `Achtergrond`.
- Data tables replace long chains of near-identical `En ziet de gebruiker …` steps.
- One-row outlines became plain scenarios.

## Boundary examples in an outline

```gherkin
  Rule: Een bestelling kan niet vragen om meer artikelen dan er op voorraad zijn

    Scenario Outline: De gevraagde hoeveelheid wordt vergeleken met de beschikbare voorraad
      Given er zijn <beschikbaar> exemplaren van een artikel beschikbaar
      When de klant <gevraagd> exemplaren bestelt
      Then wordt de bestelling <resultaat>

      Examples: Onder, op en boven de voorraadgrens
        | beschikbaar | gevraagd | resultaat |
        | 5           | 4        | geaccepteerd |
        | 5           | 5        | geaccepteerd |
        | 5           | 6        | afgewezen    |
```

Why this works: the rows sit on both sides of the boundary, the table label says so, and each row can only pass if the rule is implemented correctly.

## Before and after: rewrites of repository steps

**Vague outcome → criterion.** The binding can assert a specific, observable result.

```gherkin
# Before
Then wordt de bestelling correct verwerkt
# After
Then heeft de bestelling de status 'bevestigd'
```

**Wrong observer → real observer.** An API feature whose binding checks the response.

```gherkin
# Before
Then ziet de klant de bestelbevestiging
# After
Then ontvangt de client de bestelbevestiging
```

**Misleading table → honest scenario.** One active row, a constant column, and a label claiming "all".

```gherkin
# Before
Then ontvangt de client de bestelgegevens binnen <maxSeconden> seconden

Examples: Alle bestellingen
  | bestelnummer | maxSeconden |
  | ORD-104      | 3           |
  # | ORD-205      | 3           |

# After (one case)
Scenario: De client ontvangt bestelgegevens binnen 3 seconden
  Given een geauthenticeerde klant met een bestaande bestelling
  When de client de bestelgegevens opvraagt
  Then ontvangt de client de bestelgegevens binnen 3 seconden

# After (several cases): include meaningful rows and name the table after what distinguishes them
```

**Duplicate phrasing → one phrase.** `Given de klant is op de bestelpagina` and `When de klant de bestelling bekijkt` may perform the same navigation. Keep one phrase per behavior, and use state wording for context and event wording for the action.
