with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast;     use Fabula.Ast;
with Fabula.Format;  use Fabula.Format;
with Fabula.Limits;
with Fabula.Parse;   use Fabula.Parse;
with Fabula.Results; use Fabula.Results;

with Fabula_Fixtures; use Fabula_Fixtures;

package body Fabula_Format_Tests is

   use AUnit.Test_Cases.Registration;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;
   P   : Parser;

   procedure Load (Name : String) is
   begin
      Parse_Corpus (Name, P, Doc);
      Assert (not Failed (P), Name & " must parse");
   end Load;

   function Nth_Step (S : Scenario_Index; N : Positive) return Step_Node
   is (Step (Doc, Scenario (Doc, S).Steps.First + Step_Handle (N) - 1));

   ---------------------------------------------------------------------
   --  TDD item 1: status words, bracket labels, byte-exact against the
   --  oracle's own step-prefix formatter.
   ---------------------------------------------------------------------

   procedure Test_Status_Words (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Status_Word (Passed) = "PASSED", "passed word");
      Assert (Status_Word (Failed) = "FAILED", "failed word");
      Assert (Status_Word (Skipped) = "SKIPPED", "skipped word");
      Assert (Status_Word (Undefined) = "UNDEFINED", "undefined word");
   end Test_Status_Words;

   procedure Test_Bracket_Labels (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Bracket_Label (Passed) = "[   PASSED    ] ", "passed bracket");
      Assert (Bracket_Label (Failed) = "[   FAILED    ] ", "failed bracket");
      Assert (Bracket_Label (Skipped) = "[   SKIPPED   ] ", "skipped bracket");
      Assert
        (Bracket_Label (Undefined) = "[   UNDEFINED ] ", "undefined bracket");
   end Test_Bracket_Labels;

   procedure Test_Style_Of (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Style_Of (Passed) = Passed, "passed style");
      Assert (Style_Of (Failed) = Failed, "failed style");
      Assert (Style_Of (Skipped) = Skipped, "skipped style");
      Assert (Style_Of (Undefined) = Undefined, "undefined style");
   end Test_Style_Of;

   procedure Test_Header_Step_Location
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Header_Text ("Feature", "This represents tables")
         = "Feature: This represents tables",
         "feature header text");
      Assert
        (Step_Text ("Given", "An empty box") = "Given An empty box",
         "a Given step's text");
      Assert
        (Step_Text ("*", "a step") = "* a step",
         "a star step prints the same one-space rule");
      Assert (Location_Text ("a.feature", 8) = "  a.feature:8", "a location");
   end Test_Header_Step_Location;

   ---------------------------------------------------------------------
   --  TDD item 2: count summaries. The three oracle-probed lines are
   --  byte-exact (6_tables.feature, 11_manual_fails.feature); the
   --  mixed cases exercise the comma-joining and category order the
   --  probes never combine in one run.
   ---------------------------------------------------------------------

   procedure Test_Scenarios_Summary_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant Counts := (others => 0);
   begin
      Assert
        (Scenarios_Summary (C) = "0 Scenario ()",
         "a zero-scenario run, oracle-probed with -v -t on 5_tagged_hooks");
   end Test_Scenarios_Summary_Zero;

   procedure Test_Scenarios_Summary_Oracle_Runs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      All_Passed : constant Counts := (Scenarios_Passed => 10, others => 0);
      All_Failed : constant Counts := (Scenarios_Failed => 2, others => 0);
   begin
      Assert
        (Scenarios_Summary (All_Passed) = "10 Scenarios (10 passed)",
         "6_tables.feature's oracle summary");
      Assert
        (Scenarios_Summary (All_Failed) = "2 Scenarios (2 failed)",
         "11_manual_fails.feature's oracle summary");
   end Test_Scenarios_Summary_Oracle_Runs;

   procedure Test_Scenarios_Summary_Mixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant Counts :=
        (Scenarios_Failed  => 1,
         Scenarios_Skipped => 2,
         Scenarios_Passed  => 3,
         others            => 0);
   begin
      Assert
        (Scenarios_Summary (C) = "6 Scenarios (1 failed, 2 skipped, 3 passed)",
         "failed, skipped, passed in that order, comma-joined");
   end Test_Scenarios_Summary_Mixed;

   procedure Test_Steps_Summary_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant Counts := (others => 0);
   begin
      Assert (Steps_Summary (C) = "0 Step ()", "a zero-step run");
   end Test_Steps_Summary_Zero;

   procedure Test_Steps_Summary_Oracle_Runs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      All_Passed : constant Counts := (Steps_Passed => 28, others => 0);
      Mixed      : constant Counts :=
        (Steps_Skipped => 3, Steps_Passed => 3, others => 0);
   begin
      Assert
        (Steps_Summary (All_Passed) = "28 Steps (28 passed)",
         "6_tables.feature's oracle summary");
      Assert
        (Steps_Summary (Mixed) = "6 Steps (3 skipped, 3 passed)",
         "11_manual_fails.feature's oracle summary");
   end Test_Steps_Summary_Oracle_Runs;

   procedure Test_Steps_Summary_All_Four
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant Counts :=
        (Steps_Failed    => 1,
         Steps_Undefined => 2,
         Steps_Skipped   => 3,
         Steps_Passed    => 4,
         others          => 0);
   begin
      Assert
        (Steps_Summary (C)
         = "10 Steps (1 failed, 2 undefined, 3 skipped, 4 passed)",
         "failed, undefined, skipped, passed in that order");
   end Test_Steps_Summary_All_Four;

   ---------------------------------------------------------------------
   --  TDD item 3: step lines from a parsed corpus fixture -- a table
   --  (6_tables.feature) and a doc string (7_doc_strings.feature),
   --  both byte-verified against the rebuilt oracle.
   ---------------------------------------------------------------------

   procedure Test_Table_Row_Rendering
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Node   : Step_Node;
      Widths : Column_Widths;
   begin
      Load ("6_tables.feature");
      Node := Nth_Step (1, 2);
      Widths := Table_Widths (Doc, Node.Table, 0, 0);
      Assert (Widths (1) = 10, "widened to ""strawberry""");
      Assert (Widths (2) = 1, "every quantity is one digit");
      declare
         Rows : constant Row_Range := Table (Doc, Node.Table).Rows;
      begin
         Assert
           (Table_Row_Text (Doc, Rows.First, 0, 0, Widths)
            = "  | apple      | 2 |",
            "row 1, byte-verified against the rebuilt oracle");
         Assert
           (Table_Row_Text (Doc, Row_Handle (Rows.First + 1), 0, 0, Widths)
            = "  | strawberry | 3 |",
            "row 2");
         Assert
           (Table_Row_Text (Doc, Rows.Last, 0, 0, Widths)
            = "  | banana     | 5 |",
            "row 3");
      end;
   end Test_Table_Row_Rendering;

   procedure Test_Stale_Table_Row (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Widths : constant Column_Widths := [others => 0];
   begin
      Load ("6_tables.feature");
      Assert
        (Table_Row_Text (Doc, 0, 0, 0, Widths) = "  |",
         "a null row handle renders as the bare opening pipe");
   end Test_Stale_Table_Row;

   procedure Test_Doc_String_Rendering
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Label : Doc_String_Node;
   begin
      Load ("7_doc_strings.feature");
      Label := Doc_String (Doc, Nth_Step (1, 1).Doc);
      Assert (Doc_Fence_Text = """""""", "the fence is always """"""");
      Assert
        (Doc_Content_Text (Doc, Label.Lines.First, 0, 0)
         = "This is a docstring with quotes",
         "content line 1");
      Assert
        (Doc_Content_Text (Doc, Label.Lines.Last, 0, 0) = "after a step",
         "content line 2, oracle-probed regardless of the source fence"
         & " (this scenario opens with backticks in a sibling case)");
   end Test_Doc_String_Rendering;

   ---------------------------------------------------------------------
   --  TDD item 4: parse-error lines for both corpus refusal files, the
   --  "at end" shape, and the trailer constant.
   ---------------------------------------------------------------------

   procedure Test_Parse_Error_Examples_Before_Scenario
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name  : constant String :=
        "tests/data/cwt/parser/" & "edge_examples_before_any_scenario.feature";
      Local : Parser;
      D     : Document;
   begin
      Parse_Corpus ("edge_examples_before_any_scenario.feature", Local, D);
      Assert (Failed (Local), "the manifest says this file refuses");
      Assert (Error (Local).Kind = Expected_Scenario, "the refusal kind");
      Assert (Error (Local).Line = 5, "the refusal line");
      Assert
        (Parse_Error_Text
           (Name, Error (Local).Line, Error (Local).Kind, False, "Examples:")
         = Name
           & ":5: Error at 'Examples:': Expect Tags, Scenario or Scenario"
           & " Outline",
         "byte shape matches the oracle's own text (source-read), less"
         & " the divergent path");
   end Test_Parse_Error_Examples_Before_Scenario;

   procedure Test_Parse_Error_Unterminated_Doc_String
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name  : constant String :=
        "tests/data/cwt/parser/edge_unterminated_docstring.feature";
      Local : Parser;
      D     : Document;
   begin
      Parse_Corpus ("edge_unterminated_docstring.feature", Local, D);
      Assert (Failed (Local), "the manifest says this file refuses");
      Assert
        (Error (Local).Kind = Unterminated_Doc_String, "the refusal kind");
      Assert (Error (Local).Line = 1, "the refusal line");
      Assert
        (Parse_Error_Text
           (Name, Error (Local).Line, Error (Local).Kind, False, "")
         = Name & ":1: Error : Unterminated doc string.",
         "the no-token shape, byte-verified against the rebuilt oracle");
   end Test_Parse_Error_Unterminated_Doc_String;

   procedure Test_Parse_Error_At_End
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Parse_Error_Text ("a.feature", 9, Expected_Feature, True, "")
         = "a.feature:9: Error at end: Expect FeatureLine",
         "an end-of-input refusal never quotes a token");
      Assert
        (Parse_Error_Trailer = "Error while parsing script",
         "the trailer line the oracle always prints after one");
   end Test_Parse_Error_At_End;

   --  Review: the oracle's tag scanner consumes "@a" as one tag, then
   --  chokes on "b" wanting Tags, Scenario or Scenario Outline -- the
   --  same shape as Expected_Scenario, reached through a different
   --  kind. Tag_Line_Malformed keeps its own kind; only the rendering
   --  (message and token) now matches.
   procedure Test_Parse_Error_Tag_Line_Malformed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Local : Parser;
      D     : Document;
   begin
      Fabula_Fixtures.Parse_Lines
        ([+"Feature: f", +"@a b", +"Scenario: s"], Local, D);
      Assert (Failed (Local), "a token without '@' on a tag line refuses");
      Assert (Error (Local).Kind = Tag_Line_Malformed, "the refusal kind");
      Assert (Error (Local).Line = 2, "the refusal line");
      Assert
        (Parse_Error_Text
           ("a.feature", Error (Local).Line, Error (Local).Kind, False, "@a b")
         = "a.feature:2: Error at 'b': Expect Tags, Scenario or Scenario"
           & " Outline",
         "the oracle's own analogue: token is the first non-tag word");
   end Test_Parse_Error_Tag_Line_Malformed;

   ---------------------------------------------------------------------
   --  Review item 4: -v's non-hook lines, each byte-copied from a
   --  rebuilt-oracle probe (5_tagged_hooks.feature and 4_tags.feature,
   --  -v). The hook "executing hook" / "not executing hook" lines are
   --  a ledgered gap: no notice carries which hooks ran or were
   --  skipped.
   ---------------------------------------------------------------------

   procedure Test_Verbose_Separator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Verbose_Separator
         = "[   VERBOSE   ] ----------------------------------",
         "34 dashes, counted from the probe, not eyeballed");
   end Test_Verbose_Separator;

   procedure Test_Verbose_Scenario_Start
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Verbose_Scenario_Start
           ("We want to ship cucumbers", "5_tagged_hooks.feature", 4)
         = "[   VERBOSE   ] Scenario Start 'We want to ship cucumbers' -"
           & " File: 5_tagged_hooks.feature:4",
         "byte-verified against the rebuilt oracle's -v output");
   end Test_Verbose_Scenario_Start;

   procedure Test_No_Tags_Given (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (No_Tags_Given = "[   VERBOSE   ] No tags given, continuing",
         "printed once per scenario when no -t filter is given");
   end Test_No_Tags_Given;

   procedure Test_Verbose_Tag_Check
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Verbose_Tag_Check ("@ship", "@fresh", False)
         = "[   VERBOSE   ] Scenario tags '@ship'"
           & ASCII.LF
           & "                checked against tag expression '@fresh' ->"
           & " 'False', stopping scenario",
         "the two-line form, 16-space continuation indent from the probe");
      Assert
        (Verbose_Tag_Check ("@ship", "@ship", True)
         = "[   VERBOSE   ] Scenario tags '@ship'"
           & ASCII.LF
           & "                checked against tag expression '@ship' ->"
           & " 'True', continuing with scenario",
         "the passing wording");
   end Test_Verbose_Tag_Check;

   procedure Test_Verbose_Skip_Ignore_End
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Verbose_Skip
         = "[   VERBOSE   ] Scenario skipped with 'skip_scenario'",
         "skip_scenario, probed on 4_tags.feature -v");
      Assert
        (Verbose_Ignore
         = "[   VERBOSE   ] Scenario ignored with 'ignore_scenario'",
         "ignore_scenario, probed on 4_tags.feature -v");
      Assert
        (Verbose_End = "[   VERBOSE   ] Scenario end", "every scenario's end");
   end Test_Verbose_Skip_Ignore_End;

   ---------------------------------------------------------------------
   --  TDD item 6: the failed-scenarios store -- fill, overflow
   --  saturation, render.
   ---------------------------------------------------------------------

   procedure Test_Failed_Store_Fill
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Store : Failed_Store := Empty_Failed_Store;
   begin
      Assert (not Has_Failures (Store), "starts empty");
      Add_Failed (Store, "Steps are skipped", "a.feature", 4);
      Add_Failed (Store, "Steps aren't skipped", "a.feature", 10);
      Assert (Failed_Count (Store) = 2, "two entries recorded");
      Assert (Has_Failures (Store), "now has failures");
      Assert (Failed_Name (Store, 1) = "Steps are skipped", "first name");
      Assert (Failed_File (Store, 1) = "a.feature", "first file");
      Assert (Failed_Line (Store, 1) = 4, "first line");
      Assert (Failed_Name (Store, 2) = "Steps aren't skipped", "second name");
      Assert (Failed_Line (Store, 2) = 10, "second line");
   end Test_Failed_Store_Fill;

   --  The trailer P10 renders from a filled store, byte-verified
   --  against the oracle's own 11_manual_fails.feature trailer.
   procedure Test_Failed_Store_Rendered_Trailer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Store : Failed_Store := Empty_Failed_Store;
   begin
      Add_Failed
        (Store,
         "Steps are skipped",
         "examples/features/11_manual_fails.feature",
         4);
      Add_Failed
        (Store,
         "Steps aren't skipped",
         "examples/features/11_manual_fails.feature",
         10);
      declare
         Rendered : constant String :=
           Failed_Scenarios_Header
           & ASCII.LF
           & Failed_Name (Store, 1)
           & Location_Text (Failed_File (Store, 1), Failed_Line (Store, 1))
           & ASCII.LF
           & Failed_Name (Store, 2)
           & Location_Text (Failed_File (Store, 2), Failed_Line (Store, 2));
      begin
         Assert
           (Rendered
            = "Failed Scenarios:"
              & ASCII.LF
              & "Steps are skipped"
              & "  examples/features/11_manual_fails.feature:4"
              & ASCII.LF
              & "Steps aren't skipped"
              & "  examples/features/11_manual_fails.feature:10",
            "the rendered trailer, got: " & Rendered);
      end;
   end Test_Failed_Store_Rendered_Trailer;

   procedure Test_Failed_Store_Saturation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Store : Failed_Store := Empty_Failed_Store;
   begin
      for I in 1 .. Fabula.Limits.Max_Failed_Scenarios + 5 loop
         Add_Failed (Store, "s", "f.feature", I);
      end loop;
      Assert
        (Failed_Count (Store) = Fabula.Limits.Max_Failed_Scenarios,
         "saturates at the shipped capacity, never overflows");
      Assert
        (Failed_Line (Store, 1) = 1,
         "the earliest entries are kept, not the latest");
   end Test_Failed_Store_Saturation;

   ---------------------------------------------------------------------

   --  Status words, bracket labels, header/step/location text and the
   --  count summaries (TDD items 1 and 2).
   procedure Add_Status_And_Summary_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Status_Words'Access, "status words");
      Register_Routine
        (T, Test_Bracket_Labels'Access, "bracket labels, oracle byte-exact");
      Register_Routine (T, Test_Style_Of'Access, "status to role");
      Register_Routine
        (T,
         Test_Header_Step_Location'Access,
         "header, step and location text");
      Register_Routine
        (T, Test_Scenarios_Summary_Zero'Access, "a zero-scenario summary");
      Register_Routine
        (T,
         Test_Scenarios_Summary_Oracle_Runs'Access,
         "scenario summaries the oracle printed");
      Register_Routine
        (T,
         Test_Scenarios_Summary_Mixed'Access,
         "a mixed scenario summary, all three categories");
      Register_Routine
        (T, Test_Steps_Summary_Zero'Access, "a zero-step summary");
      Register_Routine
        (T,
         Test_Steps_Summary_Oracle_Runs'Access,
         "step summaries the oracle printed");
      Register_Routine
        (T,
         Test_Steps_Summary_All_Four'Access,
         "a step summary with all four categories");
   end Add_Status_And_Summary_Tests;

   --  Tables, doc strings and parse-error lines (TDD items 3 and 4).
   procedure Add_Rendering_Tests (T : in out Test) is
   begin
      Register_Routine
        (T,
         Test_Table_Row_Rendering'Access,
         "a table's rows, oracle byte-exact");
      Register_Routine (T, Test_Stale_Table_Row'Access, "a null table row");
      Register_Routine
        (T,
         Test_Doc_String_Rendering'Access,
         "a doc string's fence and content lines");
      Register_Routine
        (T,
         Test_Parse_Error_Examples_Before_Scenario'Access,
         "a parse error naming its token");
      Register_Routine
        (T,
         Test_Parse_Error_Unterminated_Doc_String'Access,
         "a parse error with no token");
      Register_Routine
        (T, Test_Parse_Error_At_End'Access, "an end-of-input parse error");
      Register_Routine
        (T,
         Test_Parse_Error_Tag_Line_Malformed'Access,
         "a malformed tag line, the oracle's own analogue");
   end Add_Rendering_Tests;

   --  -v's non-hook lines (review item 4).
   procedure Add_Verbose_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Verbose_Separator'Access, "the verbose separator");
      Register_Routine
        (T, Test_Verbose_Scenario_Start'Access, "Scenario Start");
      Register_Routine (T, Test_No_Tags_Given'Access, "no tags given");
      Register_Routine
        (T, Test_Verbose_Tag_Check'Access, "the tag-check two-line form");
      Register_Routine
        (T, Test_Verbose_Skip_Ignore_End'Access, "skip, ignore and end");
   end Add_Verbose_Tests;

   --  The failed-scenarios store (TDD item 6). The JSON structural
   --  glue, escaping, descriptions and scenario ids (TDD item 5) moved
   --  to Fabula_Format_Json_Tests once this file passed the shipped
   --  file-length limit (R8).
   procedure Add_Store_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Failed_Store_Fill'Access, "the failed-scenarios store fills");
      Register_Routine
        (T,
         Test_Failed_Store_Saturation'Access,
         "the failed-scenarios store saturates");
      Register_Routine
        (T,
         Test_Failed_Store_Rendered_Trailer'Access,
         "the rendered trailer, oracle byte-exact");
   end Add_Store_Tests;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Add_Status_And_Summary_Tests (T);
      Add_Rendering_Tests (T);
      Add_Verbose_Tests (T);
      Add_Store_Tests (T);
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Format (console and JSON text building)"));

end Fabula_Format_Tests;
