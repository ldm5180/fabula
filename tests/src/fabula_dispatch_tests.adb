with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Limits;
with Fabula.Shell.Dispatch;
with Fabula.Shell.Files;

with Fabula_Dispatch_Fixture; use Fabula_Dispatch_Fixture;
with Fabula_Fixtures;         use Fabula_Fixtures;
with Fabula_Run_Script;       use Fabula_Run_Script;

package body Fabula_Dispatch_Tests is

   use AUnit.Test_Cases.Registration;

   --  A whole run of Source through drive loop D: the Before_All hooks,
   --  the feature, the After_All hooks, each driven until it idles.
   generic
      with package D is new Fabula.Shell.Dispatch (<>);
   procedure Run_Whole
     (Source    : Lines;
      Opts      : D.Runner.Options;
      Selection : D.Runner.Line_Selection;
      R         : out D.Runner.Runner);

   procedure Run_Whole
     (Source    : Lines;
      Opts      : D.Runner.Options;
      Selection : D.Runner.Line_Selection;
      R         : out D.Runner.Runner)
   is
      Ctx     : D.Reg.Context;
      All_Ctx : D.Reg.Context;
   begin
      Log.Clear;
      Load (Source);
      D.Runner.Start_Run (R, Opts);
      D.Drive (R, Ctx, All_Ctx);
      Assert (D.Runner.Between_Features (R), "Before_All drives to idle");
      D.Runner.Start_Feature (R, Doc_Ref, "tally.feature", Selection);
      D.Drive (R, Ctx, All_Ctx);
      Assert (D.Runner.Between_Features (R), "the feature drives to idle");
      D.Runner.Finish_Run (R);
      D.Drive (R, Ctx, All_Ctx);
      Assert (D.Runner.Run_Finished (R), "After_All drives to the end");
   end Run_Whole;

   procedure Run_Counting is new Run_Whole (Counting);
   procedure Run_Raising is new Run_Whole (Raising);

   Tally_Doc : constant Lines :=
     [+"Feature: tally",
      +"  Scenario: one",
      +"    Given I count",
      +"    And I count",
      +"  Scenario: two",
      +"    Given I count"];

   --  The before-hook and the steps share one scenario context, made
   --  fresh for the next scenario; the all-hooks keep their own.
   Tally_Trace : constant Lines :=
     [+"hook run_open 1",
      +"open one",
      +"hook open_count 1",
      +"enter one",
      +"step count 2",
      +"passed I count",
      +"step count 3",
      +"passed I count",
      +"close passed one",
      +"open two",
      +"hook open_count 1",
      +"enter two",
      +"step count 2",
      +"passed I count",
      +"close passed two",
      +"hook run_close 1"];

   procedure Test_Order (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Counting_Run.Runner;
   begin
      Run_Counting (Tally_Doc, (others => <>), Counting_Run.All_Lines, R);
      Assert_Trace (Log, Tally_Trace);
      Assert_Counts
        (Counting_Run.Counts_Of (R),
         (Scenarios_Passed => 2, Steps_Passed => 3, others => 0));
   end Test_Order;

   Raising_Doc : constant Lines :=
     [+"Feature: raising",
      +"  Scenario: message",
      +"    Given it raises with a message",
      +"    Then a passing step",
      +"  Scenario: bare",
      +"    Given it raises bare"];

   Raising_Trace : constant Lines :=
     [+"hook run_open 1",
      +"open message",
      +"hook open_count 1",
      +"enter message",
      +"step raise_message",
      +"failed it raises with a message: boom",
      +"skipped a passing step",
      +"close failed message",
      +"open bare",
      +"hook open_count 1",
      +"enter bare",
      +"step raise_bare",
      +"failed it raises bare: FABULA_DISPATCH_FIXTURE.BARE_ERROR",
      +"close failed bare",
      +"hook run_close 1"];

   procedure Test_Step_Exceptions (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Counting_Run.Runner;
   begin
      Run_Counting (Raising_Doc, (others => <>), Counting_Run.All_Lines, R);
      Assert_Trace (Log, Raising_Trace);
      Assert_Counts
        (Counting_Run.Counts_Of (R),
         (Scenarios_Failed => 2,
          Steps_Failed     => 2,
          Steps_Skipped    => 1,
          others           => 0));
   end Test_Step_Exceptions;

   --  Line is Prefix and then something more.
   function Carries_Message (Line, Prefix : String) return Boolean
   is (Line'Length > Prefix'Length
       and then Line (Line'First .. Line'First + Prefix'Length - 1) = Prefix);

   --  A numeric reader's Constraint_Error, with the run-time's own text.
   procedure Test_Args_Exception (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Prefix : constant String := "failed I read seven as a number: ";
      R      : Counting_Run.Runner;
   begin
      Run_Counting
        ([+"Feature: misread",
          +"  Scenario: misread",
          +"    Given I read seven as a number"],
         (others => <>),
         Counting_Run.All_Lines,
         R);
      Assert (Natural (Log.Length) = 8, "eight trace lines");
      Assert (Log (5) = "step misread", "the step ran: " & Log (5));
      Assert
        (Carries_Message (Log.Element (6), Prefix),
         "a failed step with a message: " & Log (6));
      Assert (Log (7) = "close failed misread", "the scenario: " & Log (7));
   end Test_Args_Exception;

   --  The exception's failure replaces everything the body recorded: the
   --  scenario-failing order is gone, so with -c the next step runs.
   procedure Test_Order_Dropped (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Counting_Run.Runner;
   begin
      Run_Counting
        ([+"Feature: doomed",
          +"  Scenario: doomed",
          +"    Given it fails the scenario and raises",
          +"    Then a passing step"],
         (Continue_On_Failure => True, others => <>),
         Counting_Run.All_Lines,
         R);
      Assert_Trace
        (Log,
         [+"hook run_open 1",
          +"open doomed",
          +"hook open_count 1",
          +"enter doomed",
          +"step fail_and_raise",
          +"failed it fails the scenario and raises: late boom",
          +"step pass",
          +"passed a passing step",
          +"close failed doomed",
          +"hook run_close 1"]);
   end Test_Order_Dropped;

   --  A body that raises leaves the context as it found it, although the
   --  padded context goes by reference; a body that returns keeps its
   --  edits: the hook's 1 reaches the first step, whose 2 reaches the
   --  last, while the raising step's 3 is gone.
   procedure Test_Context_Rollback
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Counting_Run.Runner;
   begin
      Assert
        (Tally_Context'Size / Character'Size >= Pad_Bytes,
         "the context is padded");
      Run_Counting
        ([+"Feature: rollback",
          +"  Scenario: rollback",
          +"    Given I count",
          +"    And I count and raise",
          +"    And I count"],
         (Continue_On_Failure => True, others => <>),
         Counting_Run.All_Lines,
         R);
      Assert_Trace
        (Log,
         [+"hook run_open 1",
          +"open rollback",
          +"hook open_count 1",
          +"enter rollback",
          +"step count 2",
          +"passed I count",
          +"step count_and_raise 3",
          +"failed I count and raise: counted boom",
          +"step count 3",
          +"passed I count",
          +"close failed rollback",
          +"hook run_close 1"]);
   end Test_Context_Rollback;

   Hooked_Doc : constant Lines :=
     [+"Feature: hooks",
      +"  @boom",
      +"  Scenario: tagged",
      +"    Given a passing step",
      +"  Scenario: plain",
      +"    Given a passing step"];

   --  A raising Before_All counts a hook error; a raising scenario hook
   --  fails its scenario with the message.
   procedure Test_Hook_Exceptions (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Raising_Run.Runner;
   begin
      Run_Raising
        (Hooked_Doc,
         (Continue_On_Failure => True, others => <>),
         Raising_Run.All_Lines,
         R);
      Assert_Trace
        (Log,
         [+"hook run_raise",
          +"open tagged",
          +"hook open_raise",
          +"enter tagged",
          +"skipped a passing step",
          +"close failed tagged: hook boom",
          +"open plain",
          +"enter plain",
          +"step pass",
          +"passed a passing step",
          +"close passed plain"]);
      Assert_Counts
        (Raising_Run.Counts_Of (R),
         (Scenarios_Passed => 1,
          Scenarios_Failed => 1,
          Steps_Passed     => 1,
          Steps_Skipped    => 1,
          Hook_Errors      => 1,
          others           => 0));
   end Test_Hook_Exceptions;

   --  Files' line numbers become the runner's selection.
   procedure Test_Selection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Lines_In : Fabula.Shell.Files.Line_Numbers;
      Picked   : Counting_Run.Line_Selection;
      R        : Counting_Run.Runner;
   begin
      Lines_In.Count := 1;
      Lines_In.Lines (1) := 5;
      Picked := Counting.Selection (Lines_In);
      Assert (Picked.Count = 1 and then Picked.Lines (1) = 5, "line 5 alone");
      Run_Counting (Tally_Doc, (others => <>), Picked, R);
      Assert_Trace
        (Log,
         [+"hook run_open 1",
          +"open two",
          +"hook open_count 1",
          +"enter two",
          +"step count 2",
          +"passed I count",
          +"close passed two",
          +"hook run_close 1"]);
      Lines_In.Count := Fabula.Limits.Max_Line_Selections;
      Lines_In.Lines := [for I in Lines_In.Lines'Range => I];
      Picked := Counting.Selection (Lines_In);
      Assert
        (Picked.Count = Fabula.Limits.Max_Line_Selections
         and then Picked.Lines (Picked.Count) = Picked.Count,
         "every line of a full selection");
   end Test_Selection;

   --  -n patterns past the runner's bound are refused, and the options
   --  keep what they had.
   procedure Test_Names (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Most : constant String (1 .. Fabula.Limits.Max_Name_Filter_Length) :=
        [others => 'a'];
      Opts : Counting_Run.Options;
      Fits : Boolean;
      R    : Counting_Run.Runner;
   begin
      Counting.Set_Names (Opts, Most, Fits);
      Assert (Fits, "the longest pattern list fits");
      Assert (Counting_Run.Name_Patterns (Opts) = Most, "and is set");
      Counting.Set_Names (Opts, Most & "b", Fits);
      Assert (not Fits, "one character more does not");
      Assert (Counting_Run.Name_Patterns (Opts) = Most, "the options keep it");
      Counting.Set_Names (Opts, "tw?", Fits);
      Assert (Fits, "a short pattern fits");
      Run_Counting (Tally_Doc, Opts, Counting_Run.All_Lines, R);
      Assert
        (Natural (Log.Length) = 8 and then Log (2) = "open two",
         "the pattern selects two alone");
   end Test_Names;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Order'Access, "notices, requests and the two contexts");
      Register_Routine
        (T, Test_Context_Rollback'Access, "a raising body's edits roll back");
      Register_Routine
        (T,
         Test_Step_Exceptions'Access,
         "a raising step fails with its message");
      Register_Routine
        (T, Test_Args_Exception'Access, "a numeric reader's exception");
      Register_Routine
        (T, Test_Order_Dropped'Access, "an exception drops the body's order");
      Register_Routine
        (T, Test_Hook_Exceptions'Access, "raising all-hooks and hooks");
      Register_Routine (T, Test_Selection'Access, "Selection from Files");
      Register_Routine (T, Test_Names'Access, "Set_Names and its bound");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Shell.Dispatch (the drive loop)"));

end Fabula_Dispatch_Tests;
