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

--  Where each value sits among a step's captures, named by its role.
Count_Capture : constant := 1;
Item_Capture  : constant := 2;

Step_Defs : constant Steps.Step_Table :=
  [Step ("An empty box")                    >= Init_Box,
   Step ("I place {int} x {string} in it")  >= Add_Item,
   Step ("The box contains {int} item(s)")  >= Check_Count];

Hook_Defs : constant Steps.Hook_Table :=
  [After >= Close_Box];

--  What a failed read of the count names.
Count_Name : constant String := "The count";

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
        declare
           N : constant Fabula.Numbers.Integer_Reads.Read :=
             Fabula.Args.Int (A, Count_Capture);
        begin
           if N.Ok then
              Add (Ctx, Fabula.Args.Text (A, Item_Capture), N.Value);
           else
              Fabula.Check.Ints.Fail_Read (R, N.Error, Count_Name);
           end if;
        end;
      when Check_Count =>
        Fabula.Check.Ints.Equal
          (R, Count (Ctx), Fabula.Args.Int (A, Count_Capture));
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
  across the core boundary. Numeric reads are results too: a value,
  or the reason (`Malformed`, `Out_Of_Range`) there is none, which a
  SPARK caller must test before it reads the value. An integer is
  `-?[0-9]+` and a real is `-?[0-9]*\.?[0-9]+`, the capture grammars;
  blanks, `+`, `_`, based literals, exponents, `"5."`, `"inf"` and
  `"nan"` are `Malformed`. A real too large for `Long_Float` is
  `Out_Of_Range`; one too small reads as `0.0`, since underflow is not
  an error. A refusal never exits 0 — the two cases that do,
  a missing path and an empty file, copy the reference
  interpreter's behavior, so check the scenario count in scripts.

The proof runs at level 2 with checks and warnings as errors:
**2,954 checks proved** across 27 core units, zero `pragma Assume`,
one waiver (the decimal-to-`Long_Float` conversion, deliberately
outside the proof; its grammar check is proved). A proof-closure
lint fails the build if any core unit — or any generic without an
instance — escapes analysis.

A contributor meets two more gates, both in `tools/shape_check.py`.
One leading early-exit guard aside, a body holds one top-level block
(an `if`, a `case`, a loop, a `declare` or an extended return), so a
body that dispatches on an enumeration reads as one `case` and
nothing else. A bare numeral, character or string literal in logic is
refused unless a declaration names it: a constant whose initializer
is that one literal, a named table's aggregate, a type or subtype, or
a pragma. Four idioms stay bare: a step of one (`X + 1`), a range or
slice origin (`1 ..`), an emptiness test on a count, and a counter
reset. A function that is only a `case` over its parameter, one
literal per arm and every choice a name, counts as the naming itself
— an "enum-indexed table" waiver. Every other known violation is
waived at its exact count in `tools/shape-waivers`: a count that
grows fails the build, and so does one that shrinks without its
waiver line following it down, so the list can only ever excuse less
over time.

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
| A capture or table cell that is not a number | logs a C++ error, reads as `0` / `0.0`, the step still runs | fails the step with a named reason (`Malformed`, `Out_Of_Range`); strict grammar (`-?[0-9]+`, `-?[0-9]*\.?[0-9]+`) |
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
skip and ignore lines name no call. Two more are stated behavior
changes: cwt's own numeric conversion catches its C++ exception, logs
it and returns `0` or `0.0`, so a bad number never fails the step;
fabula's numeric grammars are strict (`-?[0-9]+` and
`-?[0-9]*\.?[0-9]+`, so a leading `+`, an underscore, a based literal
or an exponent that a C++ conversion would accept here reads as
`Malformed`), and a capture or table cell that does not read fails
the step with the type and the reason.

## The API in brief

- **Args** — `Int`, `Long`, `Real`, `Text`, `Word` read captures
  left to right, 1-based; `Doc_String`, `Doc_Line`,
  `Doc_Line_Count` and `Doc_Type` expose a doc-string argument, and
  the table views (`Row_Count`, `Cell`, `Cell_Int`, `Hash_Value`,
  `Pair_Value`) a table. Outline placeholders are substituted on
  read. `Int`, `Long`, `Real` and `Cell_Int` return a read result.
- **Numbers** — `Parse_Integer`, `Parse_Long` and `Parse_Real` turn
  any text into a read result (`Ok`, then `Value` or `Error`), for
  table cells and your own strings; `Value_Or` gives a default.
- **Check** — `Equal`, `Not_Equal`, `Greater`, `Less`… as generic
  `Compare` instances (`Fabula.Check.Ints/Longs/Reals` shipped,
  `Text_Equal` for strings), plus `Is_True`/`Is_False`, each with an
  optional message; and the controls `Skip`, `Ignore`, `Fail`,
  `Fail_Step`. A comparison also takes a read result on either side;
  a failed read fails it with the type and the reason, in place of
  the optional message. `Fail_Read` fails a step the same way from a
  body that tests `Ok` itself. `Compare` for a type of your own takes
  one `Reads` instance:

  ```ada
  Money_Name : constant String := "Money";
  package Money_Reads is new Fabula.Numbers.Reads (Money, Money_Name);
  package Money_Checks is new Fabula.Check.Compare
    (Money, Image => Money_Image, Item_Reads => Money_Reads);
  ```
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
make test       # AUnit suite, -O0 and -O3   (301 tests)
make prove      # gnatprove, checks+warnings as errors, closure lint
make format     # gnatformat --check
make shape      # shape, literal and block lint + selftests
make example    # the box binary, both modes
make gate       # byte-compare the example against committed goldens
make demo       # run the whole example/features/ suite (exit 1 by design),
                #   after `make fabula-only`: fabula's own bad-input checks,
                #   not oracle output
make ci         # all of the above, cheapest first
```

`make ci` checks parity in three kinds, each named for what it is:

1. **Upstream reference captures** (12 captures): nine files of the
   reference interpreter's own parser corpus (`tests/data/cwt/`, kept
   byte-identical and labeled as its input, not fabula's) and three
   fabula fixtures (`tests/data/fixtures/`). `make gate`'s first run
   byte-compares fabula's console output against cwt's capture of each.
2. **Oracle captures of Ada-worded examples** (`example/features/`, 10
   files): `make gate`'s second run byte-compares fabula's console
   output against the pinned reference interpreter's own capture over
   the same files, now worded in Ada rather than C++. The two
   `11_manual_fails` captures come from the oracle rebuilt with
   `tests/data/golden/oracle_examples.patch`, which changes only its
   example hook text (`examples/`, never `src/`) to match. `make
   recapture-check` re-runs both oracle builds over every golden and
   compares byte for byte, reproducing all 22.
3. **Fabula's own expectations** (`tests/data/fabula_only/`,
   `tests/data/json_snapshots/`): behavior the reference interpreter
   cannot vouch for. It turns a bad number into `0` instead of failing
   the step, and its JSON report differs from fabula's in two named
   fields. `make fabula-only` checks that a bad count fails its step
   and adds nothing, runs `json_report_check.py` (2/2: a valid JSON
   report for a scenario dropped before and after entry), and runs
   `json_snapshot_check.py` (7/7: fabula's JSON report byte for byte,
   across several features, no feature, no scenario element, dropped
   scenarios and both report targets). This is regression evidence
   against fabula's own earlier output, not oracle output.

`make demo` runs the full `example/features/` suite (after
`make fabula-only`) and checks the summary counts against the
reference interpreter's own run.

## Requirements

GNAT and `gprbuild` via [Alire](https://alire.ada.dev) (Ada 2022);
`aunit` for the tests, `gnatprove` for the proof and `gnatformat`
for the format gate, all from the Alire index; Python 3 (stdlib
only) for the lints and the gate. The crate pins
[sml-ada](https://github.com/ldm5180/sml-ada) by commit.

## License

MIT.
