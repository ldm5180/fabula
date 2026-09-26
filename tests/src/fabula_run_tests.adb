with AUnit.Assertions;  use AUnit.Assertions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Fabula.Args;
with Fabula.Ast;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Results;

with Fabula_Fixtures;    use Fabula_Fixtures;
with Fabula_Run_Fixture; use Fabula_Run_Fixture;
with Fabula_Run_Script;  use Fabula_Run_Script;

package body Fabula_Run_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Ast.Examples_Row_Handle;
   use type Fabula.Ast.Scenario_Handle;
   use type Fabula.Ast.Step_Handle;
   use type Fabula.Results.Status;

   Passing : constant Fabula.Check.Outcome := (others => <>);

   ---------------------------------------------------------------------
   --  The lifecycle: all-hooks, scenario hooks, step hooks, background.
   ---------------------------------------------------------------------

   Happy_Doc : constant Lines :=
     [+"Feature: happy",
      +"  Background:",
      +"    Given a background step",
      +"  Scenario: one",
      +"    Given a passing step",
      +"    Then a passing step"];

   Happy_Trace : constant Lines :=
     [+"before_all start_note",
      +"open one",
      +"hook open_note",
      +"enter one",
      +"hook step_in",
      +"step pass",
      +"hook step_out",
      +"passed a background step",
      +"hook step_in",
      +"step pass",
      +"hook step_out",
      +"passed a passing step",
      +"hook step_in",
      +"step pass",
      +"hook step_out",
      +"passed a passing step",
      +"hook close_note",
      +"close passed one",
      +"after_all end_note"];

   procedure Test_Happy_Path (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Lifecycle_Run.Runner;
   begin
      Lifecycle.Run_One
        (Happy_Doc, (others => <>), Lifecycle_Run.All_Lines, Log, R);
      Assert_Trace (Log, Happy_Trace);
      Assert_Counts
        (Lifecycle_Run.Counts_Of (R),
         (Scenarios_Passed => 1, Steps_Passed => 3, others => 0));
      Assert
        (not Fabula.Results.Run_Failed (Lifecycle_Run.Counts_Of (R)),
         "an all-passing run does not fail");
   end Test_Happy_Path;

   function Frame_Text (F : Fabula.Frames.Frame) return String
   is (Fabula.Frames.Value (F.File)
       & "|"
       & Fabula.Frames.Value (F.Feature)
       & F.Feature_Line'Image
       & "|"
       & Fabula.Frames.Value (F.Scenario)
       & F.Scenario_Line'Image
       & "|"
       & Fabula.Frames.Value (F.Step)
       & F.Step_Line'Image);

   procedure Assert_Frame (R : Lifecycle_Run.Runner; Want : String) is
      Got : constant String := Frame_Text (Lifecycle_Run.Current_Frame (R));
   begin
      Assert
        (Got = Want, "frame: expected """ & Want & """, got """ & Got & """");
   end Assert_Frame;

   --  The driver surface, one request and one notice at a time.
   procedure Test_Protocol (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Lifecycle_Run;
      R : Runner;
   begin
      Load (Happy_Doc);
      Start_Run (R, (others => <>));
      Assert (Next_Request (R) = C_Before_All, "Before_All first");
      Assert (Pending_Hook (R) = 1, "hook row 1");
      Assert (Pending_Hook_Kind (R) = Start_Note, "its kind");
      Assert (not Has_Notice (R) and then not Between_Features (R), "busy");
      Assert_Frame (R, "| 0| 0| 0");
      Post_Hook_Result (R, Passing);
      Assert (Between_Features (R), "idle after Before_All");
      Assert (Next_Request (R) = C_None, "nothing pending");
      Start_Feature (R, Doc_Ref, "happy.feature", All_Lines);
      Assert (Has_Notice (R), "a scenario opens");
      Assert (Current_Notice (R).Kind = Scenario_Opened, "opened");
      Assert (Current_Notice (R).Scenario = 1, "scenario node 1");
      Assert (Current_Notice (R).Data_Row = 0, "a plain scenario");
      Assert_Frame (R, "happy.feature|happy 1|one 4| 0");
      Resume (R);
      Assert
        (Next_Request (R) = C_Hook and then Pending_Hook (R) = 3, "Before");
      Post_Hook_Result (R, Passing);
      Assert (Current_Notice (R).Kind = Scenario_Entered, "entered");
      Resume (R);
      Assert (Pending_Hook_Kind (R) = Step_In, "Before_Step");
      Assert_Frame (R, "happy.feature|happy 1|one 4|a background step 3");
      Post_Hook_Result (R, Passing);
      Assert (Next_Request (R) = C_Step, "the step body");
      Assert
        (Pending_Step (R) = 2 and then Pending_Step_Kind (R) = Pass, "row 2");
      Assert (Fabula.Args.Count (Step_Args (R)) = 0, "no captures");
      Post_Step_Result (R, Passing);
      Assert (Pending_Hook_Kind (R) = Step_Out, "After_Step");
      Post_Hook_Result (R, Passing);
      Assert (Current_Notice (R).Kind = Step_Closed, "the step closes");
      Assert (Current_Notice (R).Step = 1, "step node 1");
      Assert (Current_Notice (R).Cause = Executed, "it ran");
   end Test_Protocol;

   --  More moves than the happy document takes, so a stuck runner
   --  fails the assertions below rather than hanging.
   Max_Moves : constant := 100;

   --  The after-hooks see the scenario but no step.
   procedure Test_After_Frame (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Lifecycle_Run;
      R : Runner;
   begin
      Load (Happy_Doc);
      Start_Run (R, (others => <>));
      Post_Hook_Result (R, Passing);
      Start_Feature (R, Doc_Ref, "happy.feature", All_Lines);
      for Move in 1 .. Max_Moves loop
         exit when
           Next_Request (R) = C_Hook
           and then Pending_Hook_Kind (R) = Close_Note;
         if Has_Notice (R) then
            Resume (R);
         elsif Next_Request (R) = C_Step then
            Post_Step_Result (R, Passing);
         else
            Post_Hook_Result (R, Passing);
         end if;
      end loop;
      Assert (Pending_Hook (R) = 4, "After is hook row 4");
      Assert_Frame (R, "happy.feature|happy 1|one 4| 0");
      Post_Hook_Result (R, Passing);
      Assert (Current_Notice (R).Kind = Scenario_Closed, "closed");
      Assert (Current_Notice (R).Status = Fabula.Results.Passed, "passed");
      Resume (R);
      Assert (Between_Features (R), "the feature is done");
      Finish_Run (R);
      Assert (Next_Request (R) = C_After_All, "After_All last");
      Assert_Frame (R, "| 0| 0| 0");
      Post_Hook_Result (R, Passing);
      Assert (Run_Finished (R) and then not Between_Features (R), "finished");
   end Test_After_Frame;

   ---------------------------------------------------------------------
   --  A failed step, with and without continue-on-failure.
   ---------------------------------------------------------------------

   Failing_Doc : constant Lines :=
     [+"Feature: failing",
      +"  Scenario: step fails mid way",
      +"    Given a passing step",
      +"    Then a failing step",
      +"    When a passing step",
      +"    Then a passing step"];

   Failing_Stops : constant Lines :=
     [+"open step fails mid way",
      +"enter step fails mid way",
      +"step pass",
      +"passed a passing step",
      +"step fail_check",
      +"failed a failing step: checked",
      +"skipped a passing step",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed step fails mid way"];

   Failing_Continues : constant Lines :=
     [+"open step fails mid way",
      +"enter step fails mid way",
      +"step pass",
      +"passed a passing step",
      +"step fail_check",
      +"failed a failing step: checked",
      +"step pass",
      +"passed a passing step",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close failed step fails mid way"];

   Continuing : constant Control_Run.Options :=
     (Continue_On_Failure => True, others => <>);

   procedure Test_Failed_Step (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Failing_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Failing_Stops);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios_Failed => 1,
          Steps_Passed     => 1,
          Steps_Failed     => 1,
          Steps_Skipped    => 2,
          others           => 0));
      Control.Run_One (Failing_Doc, Continuing, Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Failing_Continues);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios_Failed => 1,
          Steps_Passed     => 3,
          Steps_Failed     => 1,
          others           => 0));
   end Test_Failed_Step;

   Background_Doc : constant Lines :=
     [+"Feature: failing background",
      +"  Background:",
      +"    Given a failing step",
      +"  Scenario: after a failed background",
      +"    Given a passing step"];

   Background_Trace : constant Lines :=
     [+"open after a failed background",
      +"enter after a failed background",
      +"step fail_check",
      +"failed a failing step: checked",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed after a failed background"];

   --  A failed background step skips the scenario's own steps.
   procedure Test_Failed_Background
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Background_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Background_Trace);
   end Test_Failed_Background;

   ---------------------------------------------------------------------
   --  Undefined steps: the scenario fails, never counts as undefined.
   ---------------------------------------------------------------------

   Undefined_Doc : constant Lines :=
     [+"Feature: undefined",
      +"  Scenario: undefined then undefined then defined",
      +"    Given a passing step",
      +"    When nothing defines this",
      +"    And nothing defines this either",
      +"    Then a passing step"];

   Undefined_Stops : constant Lines :=
     [+"open undefined then undefined then defined",
      +"enter undefined then undefined then defined",
      +"step pass",
      +"passed a passing step",
      +"undefined nothing defines this",
      +"undefined nothing defines this either",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed undefined then undefined then defined"];

   Undefined_Continues : constant Lines :=
     [+"open undefined then undefined then defined",
      +"enter undefined then undefined then defined",
      +"step pass",
      +"passed a passing step",
      +"undefined nothing defines this",
      +"undefined nothing defines this either",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close failed undefined then undefined then defined"];

   Outline_Undefined_Doc : constant Lines :=
     [+"Feature: outline undefined",
      +"  Scenario Outline: row <n>",
      +"    Given nothing defines <n>",
      +"    And I place <n> x <item>",
      +"    Examples:",
      +"      | n | item |",
      +"      | 3 | pen  |"];

   Outline_Undefined_Trace : constant Lines :=
     [+"open row 3",
      +"enter row 3",
      +"undefined nothing defines <n>",
      +"step place 3 pen @7:4",
      +"passed I place 3 x pen",
      +"hook close_note",
      +"close failed row 3"];

   procedure Test_Undefined (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Undefined_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Undefined_Stops);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios_Failed => 1,
          Steps_Passed     => 1,
          Steps_Undefined  => 2,
          Steps_Skipped    => 1,
          others           => 0));
      Assert
        (Fabula.Results.Run_Failed (Control_Run.Counts_Of (R)),
         "an undefined step fails the run");
      Control.Run_One
        (Undefined_Doc, Continuing, Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Undefined_Continues);
      Control.Run_One
        (Outline_Undefined_Doc, Continuing, Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Outline_Undefined_Trace);
   end Test_Undefined;

   ---------------------------------------------------------------------
   --  Scenario controls from before- and after-hooks.
   ---------------------------------------------------------------------

   Hook_Control_Doc : constant Lines :=
     [+"Feature: hook controls",
      +"  @skip",
      +"  Scenario: skipped by a before hook",
      +"    Given a passing step",
      +"  @ignore",
      +"  Scenario: ignored by a before hook",
      +"    Given a passing step",
      +"  @fail_before",
      +"  Scenario: failed by a before hook",
      +"    Given a passing step",
      +"  @check_before",
      +"  Scenario: failed check in a before hook",
      +"    Given a passing step",
      +"  @fail_after",
      +"  Scenario: failed by an after hook",
      +"    Given a passing step",
      +"  @skip @fail_after",
      +"  Scenario: skipped then an after hook fails",
      +"    Given a passing step",
      +"  @skip",
      +"  Scenario: skipped with an undefined step",
      +"    Given a passing step",
      +"    When nothing defines this",
      +"  @skip_after",
      +"  Scenario: skipped by an after hook",
      +"    Given a passing step",
      +"  @ignore_after",
      +"  Scenario: ignored by an after hook",
      +"    Given a passing step",
      +"  @check_after",
      +"  Scenario: after-hook check fails",
      +"    Given a passing step",
      +"  @skip @check_after",
      +"  Scenario: skipped, then an after-hook check fails",
      +"    Given a passing step"];

   Hook_Control_Trace : constant Lines :=
     [+"open skipped by a before hook",
      +"hook open_skip",
      +"enter skipped by a before hook",
      +"skipped a passing step",
      +"hook close_note",
      +"close skipped skipped by a before hook",
      +"open ignored by a before hook",
      +"hook open_ignore",
      +"drop ignored by a before hook",
      +"open failed by a before hook",
      +"hook open_fail",
      +"enter failed by a before hook",
      +"skipped a passing step",
      +"close failed failed by a before hook: open_fail failed",
      +"open failed check in a before hook",
      +"hook open_check",
      +"enter failed check in a before hook",
      +"skipped a passing step",
      +"close failed failed check in a before hook: open_check failed",
      +"open failed by an after hook",
      +"enter failed by an after hook",
      +"step pass",
      +"passed a passing step",
      +"hook close_fail",
      +"hook close_note",
      +"close failed failed by an after hook: close_fail failed",
      +"open skipped then an after hook fails",
      +"hook open_skip",
      +"enter skipped then an after hook fails",
      +"skipped a passing step",
      +"hook close_fail",
      +"hook close_note",
      +"close failed skipped then an after hook fails: close_fail failed",
      +"open skipped with an undefined step",
      +"hook open_skip",
      +"enter skipped with an undefined step",
      +"skipped a passing step",
      +"undefined nothing defines this",
      +"hook close_note",
      +"close failed skipped with an undefined step",
      +"open skipped by an after hook",
      +"enter skipped by an after hook",
      +"step pass",
      +"passed a passing step",
      +"hook close_skip",
      +"hook close_note",
      +"close skipped skipped by an after hook",
      +"open ignored by an after hook",
      +"enter ignored by an after hook",
      +"step pass",
      +"passed a passing step",
      +"hook close_ignore",
      +"hook close_note",
      +"drop ignored by an after hook",
      +"open after-hook check fails",
      +"enter after-hook check fails",
      +"step pass",
      +"passed a passing step",
      +"hook close_check",
      +"hook close_note",
      +"close failed after-hook check fails: close_check failed",
      +"open skipped, then an after-hook check fails",
      +"hook open_skip",
      +"enter skipped, then an after-hook check fails",
      +"skipped a passing step",
      +"hook close_check",
      +"hook close_note",
      +("close failed skipped, then an after-hook check fails: "
        & "close_check failed")];

   procedure Test_Hook_Controls (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Hook_Control_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Hook_Control_Trace);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios_Failed  => 7,
          Scenarios_Skipped => 2,
          Steps_Passed      => 3,
          Steps_Skipped     => 6,
          Steps_Undefined   => 1,
          others            => 0));
   end Test_Hook_Controls;

   ---------------------------------------------------------------------
   --  Scenario controls from a step body.
   ---------------------------------------------------------------------

   Step_Control_Doc : constant Lines :=
     [+"Feature: step controls",
      +"  Scenario: a step skips",
      +"    Given a step that skips",
      +"    Then a passing step",
      +"  Scenario: a step ignores",
      +"    Given a passing step",
      +"    When a step that ignores",
      +"    Then a passing step",
      +"  Scenario: a step fails the scenario",
      +"    Given a step that fails the scenario",
      +"    Then a passing step",
      +"  Scenario: a step fails itself",
      +"    Given a step that fails itself",
      +"    Then a passing step",
      +"  Scenario: the last step ignores",
      +"    Given a passing step",
      +"    Then a step that ignores"];

   Step_Control_Trace : constant Lines :=
     [+"open a step skips",
      +"enter a step skips",
      +"step call_skip",
      +"passed a step that skips",
      +"skipped a passing step",
      +"hook close_note",
      +"close skipped a step skips",
      +"open a step ignores",
      +"enter a step ignores",
      +"step pass",
      +"passed a passing step",
      +"step call_ignore",
      +"passed a step that ignores",
      +"drop a step ignores",
      +"open a step fails the scenario",
      +"enter a step fails the scenario",
      +"step call_fail",
      +"failed a step that fails the scenario: failed scenario",
      +"skipped a passing step",
      +"close failed a step fails the scenario: failed scenario",
      +"open a step fails itself",
      +"enter a step fails itself",
      +"step call_fail_step",
      +"failed a step that fails itself: failed step",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed a step fails itself",
      +"open the last step ignores",
      +"enter the last step ignores",
      +"step pass",
      +"passed a passing step",
      +"step call_ignore",
      +"passed a step that ignores",
      +"drop the last step ignores"];

   procedure Test_Step_Controls (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Step_Control_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Step_Control_Trace);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios_Failed  => 2,
          Scenarios_Skipped => 1,
          Steps_Passed      => 1,
          Steps_Failed      => 2,
          Steps_Skipped     => 3,
          others            => 0));
   end Test_Step_Controls;

   ---------------------------------------------------------------------
   --  Step hooks fail the step; a failed before-step hook also keeps
   --  the body and the after-step hooks from running.
   ---------------------------------------------------------------------

   Step_Hook_Doc : constant Lines :=
     [+"Feature: step hooks",
      +"  Scenario: guarded",
      +"    Given a passing step",
      +"    When a guarded passing step",
      +"    Then a passing step",
      +"  Scenario: watched",
      +"    Given a watched passing step",
      +"    Then a passing step"];

   Step_Hook_Trace : constant Lines :=
     [+"open guarded",
      +"enter guarded",
      +"hook step_in_guard",
      +"step pass",
      +"hook step_out_watch",
      +"passed a passing step",
      +"hook step_in_guard",
      +"failed a guarded passing step: guard failed",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed guarded",
      +"open watched",
      +"enter watched",
      +"hook step_in_guard",
      +"step pass",
      +"hook step_out_watch",
      +"failed a watched passing step: watch failed",
      +"skipped a passing step",
      +"hook close_note",
      +"close failed watched"];

   procedure Test_Step_Hooks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Stepped_Run.Runner;
   begin
      Stepped.Run_One
        (Step_Hook_Doc, (others => <>), Stepped_Run.All_Lines, Log, R);
      Assert_Trace (Log, Step_Hook_Trace);
      Assert_Counts
        (Stepped_Run.Counts_Of (R),
         (Scenarios_Failed => 2,
          Steps_Passed     => 1,
          Steps_Failed     => 2,
          Steps_Skipped    => 2,
          others           => 0));
   end Test_Step_Hooks;

   ---------------------------------------------------------------------
   --  Scenario controls from a before-step hook.  A skip lets the step
   --  run and skips the rest, after-hooks included in the run; a fail
   --  stops the step's body and keeps the after-hooks from running.
   ---------------------------------------------------------------------

   Step_Hook_Control_Doc : constant Lines :=
     [+"Feature: step hook controls",
      +"  Scenario: a step hook skips",
      +"    Given a skipping passing step",
      +"    Then a passing step",
      +"  Scenario: a step hook fails the scenario",
      +"    Given a doomed passing step",
      +"    Then a passing step"];

   Step_Hook_Control_Trace : constant Lines :=
     [+"open a step hook skips",
      +"enter a step hook skips",
      +"hook step_in_control",
      +"step pass",
      +"passed a skipping passing step",
      +"skipped a passing step",
      +"hook close_note",
      +"close skipped a step hook skips",
      +"open a step hook fails the scenario",
      +"enter a step hook fails the scenario",
      +"hook step_in_control",
      +"failed a doomed passing step: step_in_control failed",
      +"skipped a passing step",
      +"close failed a step hook fails the scenario: step_in_control failed"];

   procedure Test_Step_Hook_Controls
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Step_Control_Run.Runner;
   begin
      Step_Controlled.Run_One
        (Step_Hook_Control_Doc,
         (others => <>),
         Step_Control_Run.All_Lines,
         Log,
         R);
      Assert_Trace (Log, Step_Hook_Control_Trace);
      Assert_Counts
        (Step_Control_Run.Counts_Of (R),
         (Scenarios_Failed  => 1,
          Scenarios_Skipped => 1,
          Steps_Passed      => 1,
          Steps_Failed      => 1,
          Steps_Skipped     => 2,
          others            => 0));
   end Test_Step_Hook_Controls;

   ---------------------------------------------------------------------
   --  A failed Before_All skips every scenario unless the run continues
   --  on failure; each failed all-hook phase counts one hook error.
   ---------------------------------------------------------------------

   Doomed_Doc : constant Lines :=
     [+"Feature: doomed",
      +"  Scenario: first",
      +"    Given a passing step",
      +"  Scenario: second",
      +"    Given a passing step"];

   Doomed_Skips : constant Lines :=
     [+"before_all start_fail",
      +"before_all start_note",
      +"open first",
      +"hook open_note",
      +"enter first",
      +"skipped a passing step",
      +"hook close_note",
      +"close skipped first",
      +"open second",
      +"hook open_note",
      +"enter second",
      +"skipped a passing step",
      +"hook close_note",
      +"close skipped second",
      +"after_all end_fail"];

   Doomed_Continues : constant Lines :=
     [+"before_all start_fail",
      +"before_all start_note",
      +"open first",
      +"hook open_note",
      +"enter first",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed first",
      +"open second",
      +"hook open_note",
      +"enter second",
      +"step pass",
      +"passed a passing step",
      +"hook close_note",
      +"close passed second",
      +"after_all end_fail"];

   procedure Test_Before_All (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Doomed_Run.Runner;
   begin
      Doomed.Run_One
        (Doomed_Doc, (others => <>), Doomed_Run.All_Lines, Log, R);
      Assert_Trace (Log, Doomed_Skips);
      Assert_Counts
        (Doomed_Run.Counts_Of (R),
         (Scenarios_Skipped => 2,
          Steps_Skipped     => 2,
          Hook_Errors       => 2,
          others            => 0));
      Assert
        (Fabula.Results.Run_Failed (Doomed_Run.Counts_Of (R)),
         "a failed all-hook fails the run");
      Doomed.Run_One
        (Doomed_Doc,
         (Continue_On_Failure => True, others => <>),
         Doomed_Run.All_Lines,
         Log,
         R);
      Assert_Trace (Log, Doomed_Continues);
      Assert_Counts
        (Doomed_Run.Counts_Of (R),
         (Scenarios_Passed => 2,
          Steps_Passed     => 2,
          Hook_Errors      => 2,
          others           => 0));
   end Test_Before_All;

   ---------------------------------------------------------------------
   --  An expansion over the line limit fails its step with a typed
   --  cause; the step never runs.
   ---------------------------------------------------------------------

   Big : constant String := 1_100 * 'z';

   Overflow_Doc : constant Lines :=
     [+"Feature: overflow",
      +"  Scenario Outline: big",
      +"    Given a passing step",
      +"    And I place 1 x <big><big>",
      +"    Then a passing step",
      +"      """"""",
      +"      <big><big>",
      +"      """"""",
      +"    Examples:",
      +"      | big |",
      +("      | " & Big & " |")];

   Overflow_Trace : constant Lines :=
     [+"open big",
      +"enter big",
      +"step pass",
      +"passed a passing step",
      +("failed I place 1 x <big><big> (too long): "
        & Bare_Run.Too_Long_Message),
      +("failed a passing step (too long): " & Bare_Run.Too_Long_Message),
      +"close failed big"];

   procedure Test_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Bare_Run.Runner;
   begin
      Bare.Run_One
        (Overflow_Doc,
         (Continue_On_Failure => True, others => <>),
         Bare_Run.All_Lines,
         Log,
         R);
      Assert_Trace (Log, Overflow_Trace);
      Assert_Counts
        (Bare_Run.Counts_Of (R),
         (Scenarios_Failed => 1,
          Steps_Passed     => 1,
          Steps_Failed     => 2,
          others           => 0));
   end Test_Overflow;

   --  An outline name too long once substituted keeps its text as
   --  written, for the report and for the -n patterns alike.
   Long_Name_Doc : constant Lines :=
     [+"Feature: long name",
      +"  Scenario Outline: named <big><big>",
      +"    Given a passing step",
      +"    Examples:",
      +"      | big |",
      +("      | " & Big & " |")];

   Long_Name_Trace : constant Lines :=
     [+"open named <big><big>",
      +"enter named <big><big>",
      +"step pass",
      +"passed a passing step",
      +"close passed named <big><big>"];

   procedure Test_Long_Name (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log  : Trace;
      R    : Bare_Run.Runner;
      Opts : Bare_Run.Options;
   begin
      Bare.Run_One (Long_Name_Doc, Opts, Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Long_Name_Trace);
      Bare_Run.Set_Names (Opts, "named <big>*");
      Bare.Run_One (Long_Name_Doc, Opts, Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Long_Name_Trace);
   end Test_Long_Name;

   ---------------------------------------------------------------------
   --  A step request's arguments: captures, doc string and table, each
   --  substituted from the outline's row.
   ---------------------------------------------------------------------

   Args_Doc : constant Lines :=
     [+"Feature: args",
      +"  Scenario Outline: args <v>",
      +"    Given a step reading its doc string",
      +"      """"""",
      +"      value <v>",
      +"      """"""",
      +"    And a step reading its table",
      +"      | key | <v> |",
      +"    Examples:",
      +"      | v |",
      +"      | 7 |"];

   Args_Trace : constant Lines :=
     [+"open args 7",
      +"enter args 7",
      +"step read_doc value 7",
      +"passed a step reading its doc string",
      +"step read_table 7",
      +"passed a step reading its table",
      +"close passed args 7"];

   procedure Test_Args (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Bare_Run.Runner;
   begin
      Bare.Run_One (Args_Doc, (others => <>), Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Args_Trace);
   end Test_Args;

   --  A table that refuses to compile makes the tables invalid, which
   --  Start_Run's precondition rejects.
   procedure Test_Tables_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Bare_Run.Tables_Valid, "the sample tables are valid");
      Assert (not Refused_Run.Tables_Valid, "a refused row is not");
   end Test_Tables_Valid;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Happy_Path'Access, "the lifecycle, every hook kind in order");
      Register_Routine
        (T, Test_Protocol'Access, "the driver surface, request by request");
      Register_Routine
        (T,
         Test_After_Frame'Access,
         "after-hooks see no step; After_All none");
      Register_Routine
        (T, Test_Failed_Step'Access, "a failed step, with and without -c");
      Register_Routine
        (T, Test_Failed_Background'Access, "a failed background step");
      Register_Routine
        (T, Test_Undefined'Access, "undefined steps fail, raw outline text");
      Register_Routine
        (T, Test_Hook_Controls'Access, "skip, ignore and fail from hooks");
      Register_Routine
        (T, Test_Step_Controls'Access, "skip, ignore and fail from a step");
      Register_Routine
        (T, Test_Step_Hooks'Access, "step hooks fail their step");
      Register_Routine
        (T,
         Test_Step_Hook_Controls'Access,
         "skip and fail from a before-step hook");
      Register_Routine
        (T,
         Test_Before_All'Access,
         "a failed Before_All, with and without -c");
      Register_Routine
        (T, Test_Overflow'Access, "an expansion too long fails its step");
      Register_Routine
        (T, Test_Long_Name'Access, "a name too long keeps its raw text");
      Register_Routine
        (T, Test_Args'Access, "a request's arguments, substituted");
      Register_Routine
        (T, Test_Tables_Valid'Access, "invalid tables are refused up front");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Run (the scenario lifecycle)"));

end Fabula_Run_Tests;
