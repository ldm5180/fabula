@feature_tag
Feature: Every element shape
  A description
  over two lines

  @scenario_tag
  Scenario: Passing, failing, then skipped
    Given An empty box
    Then The box contains 2 items
    And The box contains 0 items

  Scenario: An undefined step
    Given a step nobody defined

  Scenario Outline: An outline row with <count>
    Given An empty box
    When I place <count> x "pen" in it
    Then The box contains <count> items

    Examples:
      | count |
      | 1     |
      | 3     |

  Scenario: A table and a doc string
    Given An empty box
    When I add all items with the raw function:
      | apple | 2 |
    Then The box gets a shipping label
      """
      Ship to: Lisbon
      """

  Scenario: No steps
