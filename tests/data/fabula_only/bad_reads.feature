# fabula's own expectation, not oracle output: the reference interpreter reads bad number text as 0 and does not fail the step.
Feature: Bad reads and missing table parts fail their step

  Scenario: A raw table with one bad count adds nothing
    Given An empty box
    When I add all items with the raw function:
      | apple | 2 |
      | pear  | x |
    Then The box contains 0 items

  Scenario: A hashes table with one bad count adds nothing
    Given An empty box
    When I add all items with the hashes function:
      | ITEM  | QUANTITY |
      | apple | 2        |
      | pear  | +3       |
    Then The box contains 0 items

  Scenario: A rows_hash count out of range adds nothing
    Given An empty box
    When I add the following item with the rows_hash function:
      | ITEM     | apple       |
      | QUANTITY | 99999999999 |
    Then The box contains 0 items

  Scenario: A count capture out of range adds nothing
    Given An empty box
    When I place 99999999999 x "pen" in it
    Then The box contains 0 items

  Scenario: A raw table with one column
    Given An empty box
    When I add all items with the raw function:
      | apple |
    Then The box contains 0 items

  Scenario: A hashes table with no QUANTITY column
    Given An empty box
    When I add all items with the hashes function:
      | ITEM  | COUNT |
      | apple | 2     |
    Then The box contains 0 items

  Scenario: A rows_hash table with no QUANTITY row
    Given An empty box
    When I add the following item with the rows_hash function:
      | ITEM  | apple |
      | COUNT | 2     |
    Then The box contains 0 items

  Scenario: A table step with no table
    Given An empty box
    When I add all items with the raw function:
    Then The box contains 0 items

  Scenario: A label step with no doc string
    Given An empty box with a label
    Then The box contains 0 items

  Scenario: A bad expected count and a bad index
    Given An empty box
    When I place 1 x "pen" in it
    Then The 99999999999. item is "pen"
    And The box contains 99999999999 items

  Scenario: Coordinates out of range
    Given I have 1,99999999999 as coordinates
