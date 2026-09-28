with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Check;
with Fabula.Results;

with Fabula_Fixtures;    use Fabula_Fixtures;
with Fabula_Run_Fixture; use Fabula_Run_Fixture;
with Fabula_Run_Script;  use Fabula_Run_Script;

package body Fabula_Run_Table_Tests is

   use AUnit.Test_Cases.Registration;
   use all type Fabula.Results.Status;

   Passing : constant Fabula.Check.Outcome := (others => <>);

   ---------------------------------------------------------------------
   --  A step that must skip and a step with no definition, in all four
   --  combinations: an undefined step reports undefined whether or not
   --  it must skip; a defined one that must skip reports skipped.
   ---------------------------------------------------------------------

   Skip_Or_Undefined_Doc : constant Lines :=
     [+"Feature: skip or undefined",
      +"  @skip",
      +"  Scenario: skipping",
      +"    Given a passing step",
      +"    When nothing defines this",
      +"  Scenario: running",
      +"    Given a passing step",
      +"    When nothing defines this"];

   Skip_Or_Undefined_Trace : constant Lines :=
     [+"open skipping",
      +"hook open_skip",
      +"enter skipping",
      +"skipped a passing step",
      +"undefined nothing defines this",
      +"hook close_note",
      +"close failed skipping",
      +"open running",
      +"enter running",
      +"step pass",
      +"passed a passing step",
      +"undefined nothing defines this",
      +"hook close_note",
      +"close failed running"];

   procedure Test_Skip_Or_Undefined
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Skip_Or_Undefined_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Skip_Or_Undefined_Trace);
      Assert_Counts
        (Control_Run.Counts_Of (R),
         (Scenarios => [Failed => 2, others => 0],
          Steps     =>
            [Passed => 1, Skipped => 1, Undefined => 2, others => 0],
          others    => 0));
   end Test_Skip_Or_Undefined;

   ---------------------------------------------------------------------
   --  A dropped scenario's notice says whether it was entered: never
   --  when its before-hooks drop it, always when a step or an
   --  after-hook does.
   ---------------------------------------------------------------------

   Drop_Doc : constant Lines :=
     [+"Feature: drops",
      +"  @ignore",
      +"  Scenario: before",
      +"    Given a passing step",
      +"  Scenario: stepping",
      +"    Given a step that ignores",
      +"    Then a passing step",
      +"  @ignore_after",
      +"  Scenario: after",
      +"    Given a passing step"];

   Drop_Trace : constant Lines :=
     [+"open before",
      +"hook open_ignore",
      +"drop before",
      +"open stepping",
      +"enter stepping",
      +"step call_ignore",
      +"passed a step that ignores",
      +"drop after entry stepping",
      +"open after",
      +"enter after",
      +"step pass",
      +"passed a passing step",
      +"hook close_ignore",
      +"hook close_note",
      +"drop after entry after"];

   procedure Test_Drop_Entry (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Control_Run.Runner;
   begin
      Control.Run_One
        (Drop_Doc, (others => <>), Control_Run.All_Lines, Log, R);
      Assert_Trace (Log, Drop_Trace);
      Assert_Counts (Control_Run.Counts_Of (R), (others => <>));
   end Test_Drop_Entry;

   ---------------------------------------------------------------------
   --  The step cursor: the background's steps, then the scenario's
   --  own, whichever of the two a scenario has.  Each step traces its
   --  scenario's line and its own, and the next scenario starts again
   --  from the background.
   ---------------------------------------------------------------------

   Both_Doc : constant Lines :=
     [+"Feature: both",
      +"  Background:",
      +"    Given I place 1 x shared",
      +"    And I place 2 x shared",
      +"  Scenario: first",
      +"    Given I place 3 x mine",
      +"    Then I place 4 x mine",
      +"  Scenario: second",
      +"    Given I place 5 x mine"];

   Both_Trace : constant Lines :=
     [+"open first",
      +"enter first",
      +"step place 1 shared @5:3",
      +"passed I place 1 x shared",
      +"step place 2 shared @5:4",
      +"passed I place 2 x shared",
      +"step place 3 mine @5:6",
      +"passed I place 3 x mine",
      +"step place 4 mine @5:7",
      +"passed I place 4 x mine",
      +"close passed first",
      +"open second",
      +"enter second",
      +"step place 1 shared @8:3",
      +"passed I place 1 x shared",
      +"step place 2 shared @8:4",
      +"passed I place 2 x shared",
      +"step place 5 mine @8:9",
      +"passed I place 5 x mine",
      +"close passed second"];

   Shared_Only_Doc : constant Lines :=
     [+"Feature: shared only",
      +"  Background:",
      +"    Given I place 1 x shared",
      +"    And I place 2 x shared",
      +"  Scenario: none of its own"];

   Shared_Only_Trace : constant Lines :=
     [+"open none of its own",
      +"enter none of its own",
      +"step place 1 shared @5:3",
      +"passed I place 1 x shared",
      +"step place 2 shared @5:4",
      +"passed I place 2 x shared",
      +"close passed none of its own"];

   Own_Only_Doc : constant Lines :=
     [+"Feature: own only",
      +"  Scenario: mine",
      +"    Given I place 1 x mine",
      +"    Then I place 2 x mine"];

   Own_Only_Trace : constant Lines :=
     [+"open mine",
      +"enter mine",
      +"step place 1 mine @2:3",
      +"passed I place 1 x mine",
      +"step place 2 mine @2:4",
      +"passed I place 2 x mine",
      +"close passed mine"];

   Neither_Doc : constant Lines :=
     [+"Feature: neither", +"  Scenario: no step at all"];

   Neither_Trace : constant Lines :=
     [+"open no step at all",
      +"enter no step at all",
      +"close passed no step at all"];

   procedure Test_Step_Cursor (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Log : Trace;
      R   : Bare_Run.Runner;
   begin
      Bare.Run_One (Both_Doc, (others => <>), Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Both_Trace);
      Assert_Counts
        (Bare_Run.Counts_Of (R),
         (Scenarios => [Passed => 2, others => 0],
          Steps     => [Passed => 7, others => 0],
          others    => 0));
      Bare.Run_One
        (Shared_Only_Doc, (others => <>), Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Shared_Only_Trace);
      Assert_Counts
        (Bare_Run.Counts_Of (R),
         (Scenarios => [Passed => 1, others => 0],
          Steps     => [Passed => 2, others => 0],
          others    => 0));
      Bare.Run_One (Own_Only_Doc, (others => <>), Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Own_Only_Trace);
      Assert_Counts
        (Bare_Run.Counts_Of (R),
         (Scenarios => [Passed => 1, others => 0],
          Steps     => [Passed => 2, others => 0],
          others    => 0));
      Bare.Run_One (Neither_Doc, (others => <>), Bare_Run.All_Lines, Log, R);
      Assert_Trace (Log, Neither_Trace);
      Assert_Counts
        (Bare_Run.Counts_Of (R),
         (Scenarios => [Passed => 1, others => 0],
          Steps     => [others => 0],
          others    => 0));
   end Test_Step_Cursor;

   ---------------------------------------------------------------------
   --  What the runner waits for, at each kind of pause.
   ---------------------------------------------------------------------

   Happy_Doc : constant Lines :=
     [+"Feature: happy",
      +"  Background:",
      +"    Given a background step",
      +"  Scenario: one",
      +"    Given a passing step",
      +"    Then a passing step"];

   --  More moves than the happy document takes, so a stuck runner
   --  fails the assertion after the loop rather than hanging.
   Max_Moves : constant := 100;

   procedure Expect
     (R : Lifecycle_Run.Runner; Want : Lifecycle_Run.Wait_Kind; What : String)
   is
      use type Lifecycle_Run.Wait_Kind;
      Got : constant Lifecycle_Run.Wait_Kind := Lifecycle_Run.Waiting_For (R);
   begin
      Assert
        (Got = Want, What & ": expected " & Want'Image & ", got " & Got'Image);
   end Expect;

   procedure Test_Waiting_For (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Lifecycle_Run;
      R : Runner;
   begin
      Load (Happy_Doc);
      Start_Run (R, (others => <>));
      Expect (R, All_Hook_Wait, "a Before_All hook");
      Post_Hook_Result (R, Passing);
      Expect (R, Idle, "between features");
      Start_Feature (R, Doc_Ref, "happy.feature", All_Lines);
      Expect (R, Notice_Wait, "a scenario opens");
      Resume (R);
      Expect (R, Hook_Wait, "a Before hook");
      Post_Hook_Result (R, Passing);
      Expect (R, Notice_Wait, "the scenario is entered");
      Resume (R);
      Expect (R, Hook_Wait, "a Before_Step hook");
      Post_Hook_Result (R, Passing);
      Expect (R, Step_Wait, "a step body");
      for Move in 1 .. Max_Moves loop
         exit when Between_Features (R);
         if Has_Notice (R) then
            Resume (R);
         elsif Next_Request (R) = C_Step then
            Post_Step_Result (R, Passing);
         else
            Post_Hook_Result (R, Passing);
         end if;
      end loop;
      Expect (R, Idle, "the feature is done");
      Finish_Run (R);
      Expect (R, All_Hook_Wait, "an After_All hook");
      Post_Hook_Result (R, Passing);
      Expect (R, Idle, "the run is finished");
   end Test_Waiting_For;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T,
         Test_Skip_Or_Undefined'Access,
         "must-skip and undefined, all four combinations");
      Register_Routine
        (T, Test_Drop_Entry'Access, "a drop's notice says if it was entered");
      Register_Routine
        (T, Test_Step_Cursor'Access, "background steps, then the scenario's");
      Register_Routine
        (T, Test_Waiting_For'Access, "what the runner waits for, per pause");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Run (branches the table decides)"));

end Fabula_Run_Table_Tests;
