# cwt parser corpus manifest

The 21 files in this directory are cwt-cucumber's `fuzz/corpus/parser/`
at SHA 662b4e4, copied byte for byte. cwt's MIT notice is in
`../LICENSE`. `Fabula_Corpus_Tests` parses every file with
`Fabula.Parse` and asserts its row below. A corpus file without a row,
or a row without a file, fails the suite.

## Verdicts and counts

A file either `parses` or `refuses <Error_Kind> at line <N>`. For a
file that parses, the counts are what the document must report, as
authored:

- `plain`: plain scenarios.
- `outlines`: scenario outlines.
- `rows`: Examples data rows (header rows are not counted).
- `steps`: background and scenario steps (an outline's steps once).
- `tables`: step data tables (Examples tables are not counted).
- `docs`: doc strings.

`oracle` is the scenario count that cwt-cucumber's example binary,
built at the same SHA, reports for the file. The suite checks `plain + rows = oracle`
for each file that parses, unless `note` gives the reason it differs.

| file | verdict | plain | outlines | rows | steps | tables | docs | oracle | note |
|---|---|---|---|---|---|---|---|---|---|
| 10_continue_on_failure.feature | parses | 1 | 0 | 0 | 5 | 0 | 0 | 1 | |
| 11_manual_fails.feature | parses | 2 | 0 | 0 | 6 | 0 | 0 | 2 | |
| 1_first_scenario.feature | parses | 2 | 0 | 0 | 8 | 0 | 0 | 2 | |
| 2_scenario_outline.feature | parses | 0 | 2 | 4 | 6 | 0 | 0 | 4 | |
| 3_background.feature | parses | 2 | 0 | 0 | 7 | 0 | 0 | 2 | |
| 4_tags.feature | parses | 6 | 1 | 3 | 21 | 0 | 0 | 8 | the oracle's count drops the `@ignore` scenario, which its hook ignores at run time; the parser keeps all 9 |
| 5_tagged_hooks.feature | parses | 2 | 0 | 0 | 6 | 0 | 0 | 2 | |
| 6_tables.feature | parses | 3 | 5 | 7 | 23 | 8 | 0 | 10 | |
| 7_doc_strings.feature | parses | 4 | 1 | 2 | 12 | 0 | 7 | 6 | |
| 8_custom_parameters.feature | parses | 3 | 0 | 0 | 11 | 0 | 0 | 3 | |
| 9_rules.feature | parses | 2 | 0 | 0 | 6 | 0 | 0 | 2 | |
| edge_docstring_no_content_lines.feature | parses | 1 | 0 | 0 | 1 | 0 | 1 | 1 | |
| edge_examples_before_any_scenario.feature | refuses Expected_Scenario at line 5 | | | | | | | 0 | |
| edge_keyword_then_eof_comment.feature | parses | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| edge_scenario_outline_missing_examples_key.feature | parses | 0 | 1 | 1 | 1 | 0 | 0 | 1 | |
| edge_step_text_escaped_quote.feature | parses | 1 | 0 | 0 | 2 | 0 | 0 | 1 | |
| edge_table_cell_escaped_pipe.feature | parses | 1 | 0 | 0 | 1 | 1 | 0 | 1 | |
| edge_table_cell_with_hash.feature | parses | 1 | 0 | 0 | 1 | 1 | 0 | 1 | |
| edge_table_cell_with_quotes.feature | parses | 1 | 0 | 0 | 1 | 1 | 0 | 1 | |
| edge_unterminated_docstring.feature | refuses Unterminated_Doc_String at line 1 | | | | | | | 0 | |
| stress-tests.feature | parses | 11 | 4 | 16 | 25 | 1 | 6 | 27 | |

## Expected cells

The cells of the one step table in each `edge_table_cell_*` file, as
the oracle binary prints them for an undefined step. Each line is
`file:row:column: value`; the value runs to the end of the line.

```text
edge_table_cell_escaped_pipe.feature:1:1: a\|b
edge_table_cell_escaped_pipe.feature:1:2: escaped pipe
edge_table_cell_escaped_pipe.feature:2:1: \\A(?P<x>same\|root)\\z
edge_table_cell_escaped_pipe.feature:2:2: a regex
edge_table_cell_with_hash.feature:1:1: #1
edge_table_cell_with_hash.feature:1:2: leading hash
edge_table_cell_with_hash.feature:2:1: issue #7
edge_table_cell_with_hash.feature:2:2: after space
edge_table_cell_with_hash.feature:3:1: a#b
edge_table_cell_with_hash.feature:3:2: inside word
edge_table_cell_with_quotes.feature:1:1: ["x = 1"]
edge_table_cell_with_quotes.feature:1:2: plain
edge_table_cell_with_quotes.feature:2:1: ["m 7", "eval n"]
edge_table_cell_with_quotes.feature:2:2: two quotes
edge_table_cell_with_quotes.feature:3:1: "unterminated
edge_table_cell_with_quotes.feature:3:2: odd quote
```
