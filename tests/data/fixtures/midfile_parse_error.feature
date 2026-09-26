Feature: A parse error in the middle of the file

  Scenario: Before the bad line
    Given An empty box
    When I place 1 x "apple" in it
    Then The box contains 1 item

  Examples:
    | count | item |
    | 1     | pen  |

  Scenario: After the bad line
    Given An empty box
    When I place 1 x "banana" in it
    Then The box contains 1 item
