Feature: Continuing past a failing step

  Scenario: A failing assertion part way through
    Given An empty box
    Then The box contains 1 item
    When I place 1 x "apple" in it
    Then The box contains 1 item
