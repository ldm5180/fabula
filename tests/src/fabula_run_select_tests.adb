with Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Results;
with Fabula.Tags;

with Fabula_Fixtures;    use Fabula_Fixtures;
with Fabula_Run_Fixture; use Fabula_Run_Fixture;
with Fabula_Run_Script;  use Fabula_Run_Script;

package body Fabula_Run_Select_Tests is

   use AUnit.Test_Cases.Registration;
   use all type Fabula.Results.Status;

   ---------------------------------------------------------------------
   --  Tagged hooks against effective tags, in table order.
   ---------------------------------------------------------------------

   Tagged_Doc : constant Lines :=
     [+"@from_feature",
      +"Feature: tags",
      +"  @ship",
      +"  Scenario: shipped",
      +"    Given a passing step",
      +"  @quiet",
      +"  Scenario: quiet",
      +"    Given a passing step",
      +"  Scenario Outline: rows <n>",
      +"    Given a passing step",
      +"    @from_examples",
      +"    Examples:",
      +"      | n |",
      +"      | 1 |",
      +"    Examples:",
      +"      | n |",
      +"      | 2 |"];

   Tagged_Trace : constant Lines :=
     [+"open shipped",
      +"hook open_note",
      +"hook open_tagged",
      +"hook open_loud",
      +"enter shipped",
      +"step pass",
      +"passed a passing step",
      +"hook dispatch",
      +"close passed shipped",
      +"open quiet",
      +"hook open_note",
      +"enter quiet",
      +"step pass",
      +"passed a passing step",
      +"close passed quiet",
      +"open rows 1",
      +"hook open_note",
      +"hook open_loud",
      +"hook open_both",
      +"enter rows 1",
      +"step pass",
      +"passed a passing step",
      +"close passed rows 1",
      +"open rows 2",
      +"hook open_note",
      +"hook open_loud",
      +"enter rows 2",
      +"step pass",
      +"passed a passing step",
      +"close passed rows 2"];

   --  An untagged scenario evaluates every expression against the empty
   --  set: "not @quiet" holds there.
   Untagged_Doc : constant Lines :=
     [+"Feature: untagged", +"  Scenario: bare", +"    Given a passing step"];

   Untagged_Trace : constant Lines :=
     [+"open bare",
      +"hook open_note",
      +"hook open_loud",
      +"enter bare",
      +"step pass",
      +"passed a passing step",
      +"close passed bare"];

   procedure Test_Tagged_Hooks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Labeled_Run.Runner;
   begin
      Labeled.Run_One
        (Tagged_Doc, (others => <>), Labeled_Run.All_Lines, Log, R);
      Assert_Trace (Log, Tagged_Trace);
      Labeled.Run_One
        (Untagged_Doc, (others => <>), Labeled_Run.All_Lines, Log, R);
      Assert_Trace (Log, Untagged_Trace);
   end Test_Tagged_Hooks;

   ---------------------------------------------------------------------
   --  Outlines: one scenario per data row, the background before each,
   --  the data row's line, and no scenario for a row-less block.
   ---------------------------------------------------------------------

   Outline_Doc : constant Lines :=
     [+"Feature: outline",
      +"  Background:",
      +"    Given a background step",
      +"  Scenario Outline: place <count> <item>",
      +"    When I place <count> x <item>",
      +"    Examples:",
      +"      | count | item |",
      +"      | 1     | pen  |",
      +"      | 2     | cup  |",
      +"  Scenario Outline: empty <x>",
      +"    Given a passing step",
      +"    Examples:",
      +"      | x |"];

   Outline_Trace : constant Lines :=
     [+"open place 1 pen",
      +"enter place 1 pen",
      +"step pass",
      +"passed a background step",
      +"step place 1 pen @8:5",
      +"passed I place 1 x pen",
      +"close passed place 1 pen",
      +"open place 2 cup",
      +"enter place 2 cup",
      +"step pass",
      +"passed a background step",
      +"step place 2 cup @9:5",
      +"passed I place 2 x cup",
      +"close passed place 2 cup"];

   procedure Test_Outline (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Bare_Run.Runner;
   begin
      Bare.Run_One (Outline_Doc, (others => <>), Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Outline_Trace);
      Assert_Counts
        (Bare_Run.Counts_Of (R),
         (Scenarios => [Passed => 2, others => 0],
          Steps     => [Passed => 4, others => 0],
          others    => 0));
   end Test_Outline;

   ---------------------------------------------------------------------
   --  The tag filter runs after the before-hooks: a scenario it leaves
   --  out is dropped, its hooks' controls with it.
   ---------------------------------------------------------------------

   Filter_Doc : constant Lines :=
     [+"Feature: tag filter",
      +"  @ship @skip @fail_before",
      +"  Scenario: filtered out but hooked",
      +"    Given a passing step",
      +"  @important",
      +"  Scenario: selected one",
      +"    Given a passing step",
      +"  Scenario: untagged one",
      +"    Given a passing step"];

   Important_Trace : constant Lines :=
     [+"open filtered out but hooked",
      +"hook open_skip",
      +"hook open_fail",
      +"drop filtered out but hooked",
      +"open selected one",
      +"enter selected one",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed selected one",
      +"open untagged one",
      +"drop untagged one"];

   Not_Ship_Trace : constant Lines :=
     [+"open filtered out but hooked",
      +"hook open_skip",
      +"hook open_fail",
      +"drop filtered out but hooked",
      +"open selected one",
      +"enter selected one",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed selected one",
      +"open untagged one",
      +"enter untagged one",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed untagged one"];

   function Filtered (Expr : String) return Control_Run.Options
   is ((Filter     => Fabula.Tags.Compile (Expr),
        Has_Filter => True,
        others     => <>));

   procedure Test_Tag_Filter (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Filter_Doc, Filtered ("@important"), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Important_Trace);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios => [Passed => 1, others => 0],
          Steps     => [Passed => 1, others => 0],
          others    => 0));
      Control.Run_One
        (Filter_Doc, Filtered ("not @ship"), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Not_Ship_Trace);
   end Test_Tag_Filter;

   ---------------------------------------------------------------------
   --  Name patterns match the concrete, substituted name, and select
   --  before any hook runs.
   ---------------------------------------------------------------------

   Names_Doc : constant Lines :=
     [+"Feature: names",
      +"  Scenario: Plain one",
      +"    Given a passing step",
      +"  Scenario Outline: place <count> <item>",
      +"    When I place <count> x <item>",
      +"    Examples:",
      +"      | count | item |",
      +"      | 1     | pen  |",
      +"      | 2     | cup  |"];

   Names_Trace : constant Lines :=
     [+"open place 2 cup",
      +"hook open_note",
      +"enter place 2 cup",
      +"step place 2 cup @9:5",
      +"passed I place 2 x cup",
      +"hook close_note",
      +"close passed place 2 cup"];

   No_Trace : constant Lines := [];

   function Named (Patterns : String) return Noted_Run.Options is
      Result : Noted_Run.Options;
   begin
      Noted_Run.Set_Names (Result, Patterns);
      return Result;
   end Named;

   procedure Test_Name_Filter (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Noted_Run.Runner;
   begin
      Noted.Run_One
        (Names_Doc, Named ("place 2*:plain*"), Noted_Run.All_Lines, Log, R);
      Assert_Trace (Log, Names_Trace);
      Noted.Run_One
        (Names_Doc, Named ("*<item>*"), Noted_Run.All_Lines, Log, R);
      Assert_Trace (Log, No_Trace);
      Noted.Run_One (Names_Doc, Named (""), Noted_Run.All_Lines, Log, R);
      Assert
        (Noted_Run.Counts_Of (R).Scenarios (Passed) = 3,
         "an empty pattern list selects every scenario");
   end Test_Name_Filter;

   ---------------------------------------------------------------------
   --  Line selection: a plain scenario by its header line, a concrete
   --  scenario by its data row's line, nothing by any other line.
   ---------------------------------------------------------------------

   Lines_Doc : constant Lines :=
     [+"Feature: lines",
      +"  Scenario: plain",
      +"    Given a passing step",
      +"  Scenario Outline: row <n>",
      +"    Given a passing step",
      +"    Examples:",
      +"      | n |",
      +"      | 1 |",
      +"      | 2 |"];

   Row_Trace : constant Lines :=
     [+"open row 2",
      +"hook open_note",
      +"enter row 2",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed row 2"];

   Plain_Trace : constant Lines :=
     [+"open plain",
      +"hook open_note",
      +"enter plain",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed plain"];

   function Selecting (Numbers : Lines) return Noted_Run.Line_Selection is
      Result : Noted_Run.Line_Selection;
   begin
      for Number of Numbers loop
         Noted_Run.Add_Line
           (Result, Positive'Value (Ada.Strings.Unbounded.To_String (Number)));
      end loop;
      return Result;
   end Selecting;

   procedure Test_Line_Selection (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Noted_Run.Runner;
   begin
      Noted.Run_One
        (Lines_Doc,
         (others => <>),
         Selecting ([+"4", +"6", +"7", +"9", +"3"]),
         Log,
         R);
      Assert_Trace (Log, Row_Trace);
      Noted.Run_One (Lines_Doc, (others => <>), Selecting ([+"2"]), Log, R);
      Assert_Trace (Log, Plain_Trace);
   end Test_Line_Selection;

   ---------------------------------------------------------------------
   --  Dry-run: no step runs and no step hook, but scenario hooks do,
   --  as in the reference interpreter.
   ---------------------------------------------------------------------

   Dry_Doc : constant Lines :=
     [+"Feature: dry",
      +"  Scenario: plain dry",
      +"    Given a passing step",
      +"    When a failing step",
      +"  @fail_before",
      +"  Scenario: fails before dry",
      +"    Given a passing step",
      +"  @fail_after",
      +"  Scenario: fails after dry",
      +"    Given a passing step",
      +"  Scenario: undefined dry",
      +"    Given a passing step",
      +"    When nothing defines this",
      +"    Then a passing step"];

   Dry_Trace : constant Lines :=
     [+"open plain dry",
      +"enter plain dry",
      +"skipped a passing step",
      +"skipped a failing step",
      +"hook close_note",
      +"close skipped plain dry",
      +"open fails before dry",
      +"hook open_fail",
      +"enter fails before dry",
      +"skipped a passing step",
      +"close failed fails before dry: open_fail failed",
      +"open fails after dry",
      +"enter fails after dry",
      +"skipped a passing step",
      +"hook close_fail",
      +"hook close_note",
      +"close failed fails after dry: close_fail failed",
      +"open undefined dry",
      +"enter undefined dry",
      +"skipped a passing step",
      +"undefined nothing defines this",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed undefined dry"];

   Dry_Lifecycle_Doc : constant Lines :=
     [+"Feature: dry lifecycle",
      +"  Scenario: one",
      +"    Given a passing step"];

   Dry_Lifecycle_Trace : constant Lines :=
     [+"before_all start_note",
      +"open one",
      +"hook open_note",
      +"enter one",
      +"skipped a passing step",
      +"hook close_note",
      +"close skipped one",
      +"after_all end_note"];

   procedure Test_Dry_Run (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log  : Trace;
      R    : Control_Run.Runner;
      Life : Lifecycle_Run.Runner;
   begin
      Control.Run_One
        (Dry_Doc,
         (Dry_Run => True, others => <>),
         Control_Run.All_Lines,
         Log,
         R);
      Assert_Trace (Log, Dry_Trace);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios => [Failed => 3, Skipped => 1, others => 0],
          Steps     => [Skipped => 6, Undefined => 1, others => 0],
          others    => 0));
      Lifecycle.Run_One
        (Dry_Lifecycle_Doc,
         (Dry_Run => True, others => <>),
         Lifecycle_Run.All_Lines,
         Log,
         Life);
      Assert_Trace (Log, Dry_Lifecycle_Trace);
   end Test_Dry_Run;

   ---------------------------------------------------------------------
   --  Counts over a whole run: two features and a parse error between.
   ---------------------------------------------------------------------

   Mixed_Doc : constant Lines :=
     [+"Feature: mixed",
      +"  Scenario: passes",
      +"    Given a passing step",
      +"  Scenario: fails",
      +"    Given a failing step",
      +"    Then a passing step",
      +"  @skip",
      +"  Scenario: skipped",
      +"    Given a passing step",
      +"  @ignore",
      +"  Scenario: ignored",
      +"    Given a passing step",
      +"  Scenario: undefined",
      +"    Given nothing defines this"];

   Second_Doc : constant Lines :=
     [+"Feature: second",
      +"  Scenario: also passes",
      +"    Given a passing step"];

   procedure Test_Counts (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Control_Run;
      Log : Trace;
      R   : Runner;
   begin
      Start_Run (R, (others => <>));
      Load (Mixed_Doc);
      Start_Feature (R, Doc_Ref, "mixed.feature", All_Lines);
      Control.Drain (R, Log);
      Note_Parse_Error (R);
      Load (Second_Doc);
      Start_Feature (R, Doc_Ref, "second.feature", All_Lines);
      Control.Drain (R, Log);
      Finish_Run (R);
      Control.Drain (R, Log);
      Assert (Run_Finished (R), "the run is over");
      Assert_Counts
        (Counts_Of (R),
         (Scenarios    =>
            [Passed => 2, Failed => 2, Skipped => 1, Undefined => 0],
          Steps        =>
            [Passed => 2, Failed => 1, Skipped => 2, Undefined => 1],
          Parse_Errors => 1,
          Hook_Errors  => 0));
      Assert
        (Fabula.Results.Run_Failed (Counts_Of (R)), "failures fail the run");
   end Test_Counts;

   First_Doc : constant Lines :=
     [+"Feature: a", +"  Scenario: first", +"    Given a passing step"];

   Two_Features_Trace : constant Lines :=
     [+"before_all start_note",
      +"open first",
      +"hook open_note",
      +"enter first",
      +"hook step_in",
      +"step pass",
      +"hook step_out",
      +"passed a passing step",
      +"hook close_note",
      +"close passed first",
      +"open also passes",
      +"hook open_note",
      +"enter also passes",
      +"hook step_in",
      +"step pass",
      +"hook step_out",
      +"passed a passing step",
      +"hook close_note",
      +"close passed also passes",
      +"after_all end_note"];

   --  Before_All and After_All run once for the run, not per feature.
   procedure Test_Two_Features (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Lifecycle_Run;
      Log : Trace;
      R   : Runner;
   begin
      Start_Run (R, (others => <>));
      Lifecycle.Drain (R, Log);
      Load (First_Doc);
      Start_Feature (R, Doc_Ref, "a.feature", All_Lines);
      Lifecycle.Drain (R, Log);
      Assert (Between_Features (R), "between the two features");
      Load (Second_Doc);
      Start_Feature (R, Doc_Ref, "second.feature", All_Lines);
      Lifecycle.Drain (R, Log);
      Finish_Run (R);
      Lifecycle.Drain (R, Log);
      Assert_Trace (Log, Two_Features_Trace);
   end Test_Two_Features;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Tagged_Hooks'Access, "tagged hooks on effective tags");
      Register_Routine
        (T, Test_Outline'Access, "outline rows, background, data-row lines");
      Register_Routine
        (T, Test_Tag_Filter'Access, "the tag filter drops after before-hooks");
      Register_Routine
        (T, Test_Name_Filter'Access, "name patterns on concrete names");
      Register_Routine
        (T,
         Test_Line_Selection'Access,
         "line selection, header and data rows");
      Register_Routine
        (T, Test_Dry_Run'Access, "dry-run skips steps, runs scenario hooks");
      Register_Routine
        (T, Test_Counts'Access, "counts over two features and a parse error");
      Register_Routine (T, Test_Two_Features'Access, "all-hooks once per run");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Run (hooks, outlines, selection, dry-run)"));

end Fabula_Run_Select_Tests;
