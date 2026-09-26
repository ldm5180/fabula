Feature: A failing step and an undefined step

  Scenario: The step fails
    Given An empty box
    When I place 1 x "apple" in it
    Then The box contains 2 items

  Scenario: The step is undefined
    Given An empty box
    When Nobody registered this step at all
    Then The box contains 1 item
