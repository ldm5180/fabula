Feature: A scenario dropped after it entered
  Not a port of a reference-interpreter corpus file -- exercises an
  After hook that ignores a scenario once its own steps already
  streamed, to check the console still closes the scenario out and the
  JSON report still comes out well-formed.

  @ignore_after
  Scenario: Ignored after all its steps ran
    Given An empty box
    When I place 1 x "apple" in it
    Then The box contains 1 item

  Scenario: A normal scenario runs after it
    Given An empty box
    When I place 1 x "banana" in it
    Then The box contains 1 item
