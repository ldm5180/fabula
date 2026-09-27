Feature: Scenarios dropped before and after entry

  @ignore
  Scenario: Dropped before entry, first in the feature
    Given An empty box

  Scenario: Kept
    Given An empty box
    When I place 1 x "apple" in it
    Then The box contains 1 item

  @ignore
  Scenario: Dropped before entry, after a kept one
    Given An empty box

  @ignore_after
  Scenario: Dropped after entry, its steps already run
    Given An empty box
    When I place 1 x "apple" in it

  Scenario: Kept after the drops
    Given An empty box
