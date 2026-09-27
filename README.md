# fabula

Cucumber-style **BDD for Ada**: fabula parses Gherkin feature files
and runs them against step definitions written in Ada 2022, on a
SPARK-proven core built from
[sml-ada](https://github.com/ldm5180/sml-ada) state machines. The
behavior model is [cwt-cucumber](https://github.com/ThoSe1990/cwt-cucumber),
the C++20 Cucumber interpreter — close enough that fabula's example
binary reproduces its console output byte for byte, and a committed
golden gate holds it there.

*Fabula* is Latin for "story" — what a feature file tells.

```gherkin
Feature: Putting apples into a box

  Scenario: Lets start with two apples
    Given An empty box
    When I place 2 x "apple" in it
    Then The box contains 2 items
```

Step definitions follow the sml design language: an enumeration, a
table that reads like the feature, one dispatcher.

```ada
type Step_Kind is (Init_Box, Add_Item, Check_Count);
type Hook_Kind is (Close_Box);

package Steps is new Fabula.Registry
  (Step_Kind => Step_Kind, Hook_Kind => Hook_Kind,
   Context   => Box_Context);
use Steps;

Step_Defs : constant Steps.Step_Table :=
  [Step ("An empty box")                    >= Init_Box,
   Step ("I place {int} x {string} in it")  >= Add_Item,
   Step ("The box contains {int} item(s)")  >= Check_Count];

Hook_Defs : constant Steps.Hook_Table :=
  [After >= Close_Box];

procedure Execute
  (S    : Step_Kind;
   Ctx  : in out Box_Context;
   A    : Fabula.Args.List;
   Info : Fabula.Frames.Frame;
   R    : in out Fabula.Check.Outcome)
is
begin
   case S is
      when Init_Box    => Ctx := (others => <>);
      when Add_Item    =>
        Add (Ctx, Fabula.Args.Text (A, 2), Fabula.Args.Int (A, 1));
      when Check_Count =>
        Fabula.Check.Ints.Equal (R, Count (Ctx), Fabula.Args.Int (A, 1));
   end case;
end Execute;
```

The binary is one instantiation:

```ada
procedure Box_Main is new Fabula.Main
  (Steps     => Box_Steps.Steps,
   Step_Defs => Box_Steps.Step_Defs,
   Hook_Defs => Box_Steps.Hook_Defs,
   Execute   => Box_Steps.Execute,
   Run_Hook  => Box_Steps.Run_Hook);
```

```console
$ ./example/bin/release/box_main example/features/1_first_scenario.feature
Feature: My first feature  example/features/1_first_scenario.feature:1

Scenario: First Scenario  example/features/1_first_scenario.feature:4
[   PASSED    ] Given An empty box  example/features/1_first_scenario.feature:5
...
2 Scenarios (2 passed)
8 Steps (8 passed)
```

## Why this design

A Cucumber framework is usually macros plus callbacks plus a regex
engine. None of those survives contact with SPARK, and none is
needed:

- **Steps are enum-dispatched, not registered callbacks.** The table
  stays pure data, the compiler checks the `case` covers every
  kind, and the whole registry is provable. A pattern that fails to
  compile makes a *refused row*: the binary reports every bad row
  at startup and exits 1, instead of crashing.
- **The parser is an sml state machine.** Gherkin is line-oriented,
  so the document grammar is a transition table you can read: 15
  states, guarded rows with first-match-wins dispatch, unhandled
  lines becoming located refusals. The parsed document lives in one
  flat arena with typed index handles — bounded everywhere, no
  allocation.
- **The runner never calls user code.** Its lifecycle machine emits
  requests (run this hook, run this step); a thin unproved shell
  executes them and posts outcomes back. Every semantics test drives
  the proved core through a scripted double, fully offline.
- **Checks record, they never raise.** `Fabula.Check` writes into an
  `Outcome` the runner reads as data; a user exception is caught at
  the shell, becomes a failed step, and that body's context edits
  are rolled back — behavior never depends on the compiler's
  parameter-passing choice.
- **Refusals are typed values.** Overflow, malformed input, bad
  patterns, bad flags: named results with locations, not exceptions
  across the core boundary (the one exception: the numeric argument
  readers raise on a cross-typed read, which the shell turns into a
  failed step). A refusal never exits 0 — the two cases that do,
  a missing path and an empty file, copy the reference
  interpreter's behavior, so check the scenario count in scripts.

The proof runs at level 2 with checks and warnings as errors:
**2,699 checks proved** across 23 core units, zero `pragma Assume`,
one waiver (numeric text conversion, deliberately outside the
proof). A proof-closure lint fails the build if any core unit — or
any generic without an instance — escapes analysis.

## Compared to cwt-cucumber

| Capability | cwt-cucumber | fabula |
|---|---|---|
| Scenarios, Backgrounds, Rules, `And`/`But`/`*` | ✓ | ✓ |
| Scenario Outlines + Examples (+ `Example:`/`Scenarios:` synonyms) | ✓ | ✓ |
| Doc strings (`"""` and ``` fences, content types) | ✓ | ✓ |
| Data tables: raw / hashes / rows_hash + typed cells | ✓ | ✓ |
| Tags + tag expressions | equal precedence, left-assoc | **standard Cucumber precedence** (`not` > `and` > `or`), `xor` kept |
| Hooks: all / scenario / step, tagged scenario hooks | ✓ | ✓ |
| Scenario controls: skip / ignore / fail, fail-step | ✓ (flags can leak across scenarios) | ✓ (strictly scoped per scenario) |
| Cucumber expressions: `{int}` `{string}` `{word}` `{float}` `{}` … | ✓ | ✓ (unknown `{key}` = refused row, not a crash) |
| Custom parameter types | ✓ | planned (v2) |
| CLI: `-t -n -q -v -d -c`, `file:LINE`, `--exclude-file`, `--report-json` | ✓ | ✓ |
| JSON report | ✓ | ✓ (same keys, order, escaping; `match.location` and Rule-in-id differ, on purpose) |
| Localized keywords | ✓ | no — English, by decision |
| Formal verification | — | SPARK: proof + closure lint on every CI run |
| Console parity | — | byte-gated against cwt's own output, in CI |

Where the two disagree, fabula matched cwt's *code* over its docs,
and each divergence is deliberate and named in the sources. Most
replace accidents: crash paths become typed refusals (bad patterns,
unreadable directories, oversized inputs), control flags stay
scoped to their scenario, directory walks are sorted for
determinism, and doc-string line numbers are counted correctly
where cwt double-counts CRLF. A few are fabula's own limits, also
named where they live: one recorded message per step outcome where
cwt prints every failing assert, Ada-image real-number formatting,
tag expressions on standard Cucumber precedence rather than cwt's,
and two missing `-v` hook lines. Messages that name a cwt C++ call
use Ada terms instead: the default `Fail` and `Fail_Step` messages
name `Fabula.Check.Fail` and `Fabula.Check.Fail_Step`, and the `-v`
skip and ignore lines name no call.

## The API in brief

- **Args** — `Int`, `Long`, `Real`, `Text`, `Word` read captures
  left to right, 1-based; `Doc_String`, `Doc_Line`,
  `Doc_Line_Count` and `Doc_Type` expose a doc-string argument, and
  the table views (`Row_Count`, `Cell`, `Cell_Int`, `Hash_Value`,
  `Pair_Value`) a table. Outline placeholders are substituted on
  read.
- **Check** — `Equal`, `Not_Equal`, `Greater`, `Less`… as generic
  `Compare` instances (`Fabula.Check.Ints/Longs/Reals` shipped,
  `Text_Equal` for strings), plus `Is_True`/`Is_False`, each with an
  optional message; and the controls `Skip`, `Ignore`, `Fail`,
  `Fail_Step`.
- **Context** — one record type you declare; a fresh
  default-initialized value per scenario. Give every component a
  default. A very large context is copied once per step or hook
  call — keep it lean or hold big state behind your own reference.
- **Frames** — `Info` tells a step or hook its file, feature,
  scenario and step position.
- **Hooks** — `Before_All`, `After_All`, `Before ("@tag and not
  @wip")`, `After`, `Before_Step`, `After_Step`; table order is
  execution order.

## Building, testing, proving

```console
make build      # the library (Alire)
make test       # AUnit suite, -O0 and -O3   (261 tests)
make prove      # gnatprove, checks+warnings as errors, closure lint
make format     # gnatformat --check
make shape      # subprogram-shape lint + selftests
make example    # the box binary, both modes
make gate       # byte-compare the example against committed goldens
make demo       # run the whole example/features/ suite (exit 1 by design)
make ci         # all of the above, cheapest first
```

The golden gate is the parity contract: 22 captured cwt outputs —
the corpus set and every file under `example/features/` — that the
example binary must reproduce byte for byte on every `make ci` run,
locally and in CI. The two `11_manual_fails` captures come from cwt
built with `tests/data/golden/oracle_examples.patch`, which changes
only its example hook text to match fabula's example. `make demo` runs the full example suite and
checks the summary counts against the reference interpreter's own
run.

## Requirements

GNAT and `gprbuild` via [Alire](https://alire.ada.dev) (Ada 2022);
`aunit` for the tests, `gnatprove` for the proof and `gnatformat`
for the format gate, all from the Alire index; Python 3 (stdlib
only) for the lints and the gate. The crate pins
[sml-ada](https://github.com/ldm5180/sml-ada) by commit.

## License

MIT.
