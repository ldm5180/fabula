# Fabula.Format wiring — the notice-to-output call sequence

This is the authority `fabula-format.ads` points to (its own comment
budget is 8 lines per block). It names, for each piece of console or
JSON output, which `Fabula.Format` function the composition root
calls, when, and every
probe-verified rule behind the choice. The oracle referred to
throughout is the pinned reference interpreter (SHA 662b4e4); probes
were run against a rebuilt copy with JSON reporting enabled (the
original pinned binary lacked `nlohmann_json` at its own configure
time).

## Console, one feature file at a time

1. **Feature header.** There is no feature-level notice in
   `Fabula.Run` — the composition root prints it itself, right when
   it calls
   `Start_Feature`, using the Document's `Feature (Doc).Head` and the
   file path: `Header_Text` then `Location_Text`, then one blank line.
   Rule and Background headers never print at all — the oracle's own
   console printer has no such overload (source-read, `log_util.cpp`:
   only a `feature_node` and a `scenario_node` overload exist).

2. **Scenario header.** On `Scenario_Entered` (never `Scenario_Opened`
   — a dropped scenario prints nothing, since `is_scenario_ignored`
   returns before the header call in the oracle's own pipeline).
   `Header_Text (Keyword, Name)` then `Location_Text (File, Line)`.
   For a concrete outline scenario, Name and Line come from
   `Fabula.Expand.Concrete_Name` and `Concrete_Line` against the
   current `Example_Ref`, not the outline's own stored header.

3. **Step lines**, one per `Step_Closed` notice: `Bracket_Label
   (Status)` (styled `Style_Of (Status)`) then `Step_Text (Keyword,
   Text)` then `Location_Text`. Keyword comes from
   `Fabula.Scan.Spelling`; Text is the notice's expanded (or
   raw-if-undefined) text. An undefined step in an outline prints its
   **raw, unsubstituted** text (`<placeholder>` left as written) — the
   oracle's own outline expansion never attaches a table or doc string
   to a step it could not match (source-read: the unmatched branch of
   its concrete-scenario builder constructs a step node with no table
   or doc-string argument at all), so neither renders for it, in
   console or JSON.

4. **A step's table, then its doc string**, in that order, immediately
   after the step's own line (never before it):
   - Table: one `Table_Widths` call, then one `Table_Row_Text` call
     per row, each printed Plain on its own line.
   - Doc string: `Doc_Fence_Text`, then one `Doc_Content_Text` call per
     line, then `Doc_Fence_Text` again — **unless the doc string has
     zero content lines**, in which case nothing prints at all, not
     even the fences (source-read and probe-confirmed on
     `edge_docstring_no_content_lines.feature`: the oracle's own
     `info` call for a doc string is skipped entirely when its line
     vector is empty, the same check that drops the JSON `"content"`
     argument, item 10 below).

5. **A failure message's position depends on which failure it is.**
   - A step-body assertion, or a `Fail_Step` from a before-step hook,
     prints its message **before** that step's own bracketed line —
     the oracle's assert path (and its manual-fail path) both print
     inline, mid-pipeline, before the step's teardown call.
   - A whole-scenario failure (`Fail`, from a hook or a step) prints
     its message **after the scenario's last step**, once, styled
     Error — the oracle's `update_scenario_status` runs after every
     step and every after-hook.

6. **The blank line after every scenario** (`Scenario_Closed`, not
   dropped) is unconditional and always prints, whatever the outcome —
   the oracle's own `verbose_end_print` calls `log::info (new_line)`
   with no guard. It does **not** print for a dropped scenario (item 2).

## After the run (`Run_Finished`)

7. **The trailer**, only if `Has_Failures (Store)`:
   `Failed_Scenarios_Header`, then one line per entry (`Failed_Name`
   styled Failed, then `Location_Text` styled Location). Then **one
   more unconditional blank line** (the oracle's `print_results`:
   `print_failed_scenarios(); log::report (new_line);` — this blank
   prints whether or not the trailer did). Then `Scenarios_Summary`
   and `Steps_Summary`, one line each.
   - **When no scenario failed**, the trailer is skipped but the
     report-level blank still prints, landing right after the
     scenario-close blank from item 6 — the two blanks back to back
     that the byte samples show for an all-green run.

8. **`-q` (quiet) keeps only error-level and report-level lines; `-v`
   always wins over it.** The oracle's logger has five levels (verbose,
   info, quiet, error, report). `-q` raises the threshold to quiet;
   `-v`, checked second and unconditionally (`options.cpp`'s own two
   sequential `set_level` calls, the second never guarded on the
   first), lowers it back to verbose regardless — so `-q -v` together
   restores everything, verbose lines included.
   - **Info-level, dropped under a plain `-q`:** the feature and
     scenario headers, every step line, the item-6 scenario-close
     blank, and item 5's **step-body** half (a step-body assertion or a
     before-step `Fail_Step`, printed inline before that step's own
     line — `asserts.hpp` logs it at info level, not error).
   - **Error-level, always printed:** item 5's **whole-scenario**
     half (`Fail`, from a hook or a step) — a materially different
     message from the step-body one above, not the same text at a
     different level.
   - **Report-level, always printed:** the trailer and its header, its
     own blank, both summaries.

   Probe-confirmed against the pinned oracle on a step-assertion
   fixture: under `-q` alone, only "Failed Scenarios:" and the two
   summary lines print; under `-q -v` together, the feature header,
   the scenario's own header, every step line, and the assertion
   message all come back, byte-identical to a plain run. The
   composition root must reproduce this asymmetry — including which
   half of the failure-message rule sits at which level — not skip
   a fixed set of calls.

9. **`--report-json` silences the console path entirely.** The oracle
   never calls any of items 1-8 when a JSON report is requested — it
   is one or the other, chosen once per run (source-read,
   `cucumber.cpp`'s `print_results`). An empty run (no feature files
   matched) writes exactly `[]`, two bytes, no trailing newline
   (probe-confirmed against an empty directory).

## JSON, per feature/scenario/step

Built from `Fabula.Format`'s generic glue (`Open_Object`,
`Open_Named_Object`, `Close_Object`, `Open_Array`, `Close_Array`,
`Empty_Array_Field`, `String_Field`, `String_Item`, `Number_Field`),
one call per field or array boundary, at the named `*_Depth` constant.
Every key is alphabetical (the oracle's JSON library sorts an
object's keys regardless of insertion order) — never re-derive an
order from the oracle's own field-construction code.

10. **Feature**: `description` (`Description_Content`, escaped),
    `elements` (array of scenarios), `id` (feature name), `keyword`,
    `line`, `name`, `tags` (array of `String_Item`, each tag already
    carrying its `@`), `uri` (the file path as given on the command
    line, not resolved).

11. **Scenario** (an `elements` entry): `description`
    (`Description_Content`), `id` (`Scenario_Id` — see item 12),
    `keyword`, `line` (`Concrete_Line` for an outline row), `name`
    (`Concrete_Name` for an outline row — **never** carries the
    `Scenario_Id` occurrence prefix), `steps`, `tags`, and **`type`,
    which holds the scenario's own name again** (the oracle's own
    `field_scenario["type"] = scenario.name`, byte-verified, not a
    Format invention — do not "fix" this into something more sensible).
    No run-status field of any kind lives on a scenario object.

12. **Scenario id, two probe corrections from the first pass.**
    - **The oracle DOES fold a Rule into the id** — but only for the
      first scenario textually after the `Rule:` header; its own rule
      tracking resets on every scenario in the parse loop (source-read,
      `parser.cpp`'s `parse_scenarios`: `current_rule` is reassigned
      from `parse_rule (lex)` every iteration, which returns nothing
      once the lexer has moved past the `Rule:` line). Probe-confirmed:
      two scenarios under one Rule give ids `probe;R;first` then
      `probe;second`. fabula keeps the Rule for every scenario the Ast
      attaches to it (its own parser follows standard Gherkin), so the
      named divergence is narrower than first written: only later
      scenarios and outlines under one Rule, not the Rule-folding rule
      itself.
    - **The outline `"(N) "` prefix restarts at 1 for each Examples
      block**, not across the whole scenario (source-read, `ast.hpp`'s
      `push_example`, which numbers `i` from 1 within the block it is
      given; probe-confirmed: a two-block, three-row outline gives ids
      `(1)`, `(2)`, `(1)`). The composition root tracks
      `Example_Ref.Block` while
      walking `Fabula.Expand.Next_Example` and resets its occurrence
      counter to 1 whenever `Block` changes from the previous ref.

13. **Step**: `arguments` (empty unless the step has a table or a doc
    string — never both), `keyword`, `line`, `match` (see item 14),
    `name` (the resolved step text), `result` (`status`, plus
    `error_message` **only when** `status` is `failed` or `undefined`
    — never on `passed` or `skipped`, byte-confirmed against every
    probe). No `id` field exists on a step at all.

14. **`match.location` — a ruling, not a probe.** The oracle writes
    the C++ source file and line where the step definition was
    registered; fabula has no such analogue (Ada step definitions
    carry no source position `Fabula.Registry` records). Ruling:
    `location` holds the matched step's **registered pattern text**
    (`Fabula.Registry.Pattern_Text (Steps, Match_Index)`, `String_Field`
    into the `location` key) — stable across runs and meaningful to a
    reader, unlike a path. For a skipped or undefined step (no match
    attempted, or none found), `location` is the empty string, matching
    the oracle's own fallback for the same case.

15. **A table argument's full nesting** (one entry in `arguments`):
    `Open_Object` (the argument), `Open_Array ("rows", ...)`, one
    `Open_Object` per row, `Open_Array ("cells", ...)`, one
    `String_Item` per cell, closing each in turn. A doc-string argument
    is `Open_Object` then a single `String_Field ("content",
    Doc_String_Content, ...)` — `Doc_String_Content` space-joins the
    lines (the oracle's own join, not a newline join, confirmed against
    its JSON report specifically — its console printer joins
    differently, item 4).

## Verbose (`-v`) — non-hook lines only

`Fabula.Format` delivers the separator, `Scenario Start`, the tag-check
two-line form, `No tags given, continuing`, the skip/ignore lines and
`Scenario end`. All but the skip/ignore lines are byte-copied from a
rebuilt-oracle probe (`5_tagged_hooks.feature` and `4_tags.feature`,
`-v`). The oracle's skip/ignore lines name its C++ calls; fabula's
read `Scenario skipped` and `Scenario ignored`: they state the
outcome and name no call. Only `-d` prints the skip line; a `Skip`
from a hook does not (the gap `Program_Console.Set_Dry_Run`
discloses). Ignore and a `-t` filter both print the ignore line. No
gated capture uses `-v`, so the byte gate is unaffected. The hook
`"executing hook"` / `"not executing hook"` lines stay out: no notice
in `Fabula.Run` carries which hooks ran, were skipped, or their tag
check's result, so there is nothing for the composition root to
render them from. This is a recorded gap, not a Format defect —
closing it would need a new notice shape.

## Parse errors

`Parse_Error_Text (File, Line_No, Kind, At_End, Token)` then
`Parse_Error_Trailer` on its own line. `At_End` is true only when
the refusal came from `Fabula.Parse.Finish` (end of input, no next
line to quote a token from) rather than `Feed`;
`Fabula.Shell.Files.Load_Result.At_End` carries the distinction. `Tag_Line_Malformed` renders through the same "at token"
shape as `Expected_Scenario`, but names its token via
`First_Bad_Tag_Token`, not `First_Token`: the oracle's own tag scanner
consumes each `@...` run as one tag, then reports whatever comes next
that is not one.
