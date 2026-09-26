Feature: A scenario outline where one row fails

  Scenario Outline: Placing <count> items
    Given An empty box
    When I place <count> x "widget" in it
    Then The box contains <expected> items

    Examples:
      | count | expected |
      | 1     | 1        |
      | 2     | 99       |
      | 3     | 3        |
