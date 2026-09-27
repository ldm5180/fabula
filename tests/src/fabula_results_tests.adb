with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Results; use Fabula.Results;

package body Fabula_Results_Tests is

   use AUnit.Test_Cases.Registration;

   procedure Test_Counter_Accumulation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Scenario (C, Passed);
      Add_Scenario (C, Passed);
      Add_Scenario (C, Failed);
      Add_Scenario (C, Skipped);
      Add_Scenario (C, Undefined);
      Add_Step (C, Passed);
      Add_Step (C, Undefined);
      Add_Parse_Error (C);
      Add_Hook_Error (C);

      Assert (C.Scenarios (Passed) = 2, "two passed scenarios");
      Assert (C.Scenarios (Failed) = 1, "one failed scenario");
      Assert (C.Scenarios (Skipped) = 1, "one skipped scenario");
      Assert (C.Scenarios (Undefined) = 1, "one undefined scenario");
      Assert (C.Steps (Passed) = 1, "one passed step");
      Assert (C.Steps (Undefined) = 1, "one undefined step");
      Assert (C.Parse_Errors = 1, "one parse error");
      Assert (C.Hook_Errors = 1, "one hook error");
   end Test_Counter_Accumulation;

   procedure Test_All_Green (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Scenario (C, Passed);
      Add_Step (C, Passed);
      Assert (not Run_Failed (C), "an all-green run does not fail");
   end Test_All_Green;

   procedure Test_Failed_Scenario_Fails_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Scenario (C, Failed);
      Assert (Run_Failed (C), "a failed scenario fails the run");
   end Test_Failed_Scenario_Fails_Run;

   procedure Test_Undefined_Step_Fails_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Step (C, Undefined);
      Assert (Run_Failed (C), "an undefined step fails the run");
   end Test_Undefined_Step_Fails_Run;

   procedure Test_Parse_Error_Fails_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Parse_Error (C);
      Assert (Run_Failed (C), "a parse error fails the run");
   end Test_Parse_Error_Fails_Run;

   procedure Test_Hook_Error_Fails_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Hook_Error (C);
      Assert
        (Run_Failed (C), "a Before_All/After_All hook error fails the run");
   end Test_Hook_Error_Fails_Run;

   procedure Test_Skipped_Never_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Scenario (C, Skipped);
      Add_Step (C, Skipped);
      Assert
        (not Run_Failed (C), "skipped scenarios and steps never fail a run");
   end Test_Skipped_Never_Fails;

   --  An Undefined SCENARIO status alone -- no undefined STEP -- must
   --  not fail the run: the runner never actually records one this
   --  way (it records Failed instead), but Counts itself does not
   --  enforce that, so Run_Failed's own trigger set is what is under
   --  test here.
   procedure Test_Undefined_Scenario_Alone_Does_Not_Fail
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Counts;
   begin
      Add_Scenario (C, Undefined);
      Assert
        (not Run_Failed (C),
         "an Undefined scenario status alone does not fail the run");
   end Test_Undefined_Scenario_Alone_Does_Not_Fail;

   procedure Test_Saturation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      C : Counts :=
        (Scenarios    => [Passed => Natural'Last, others => 0],
         Steps        => [Failed => Natural'Last, others => 0],
         Parse_Errors => Natural'Last,
         Hook_Errors  => 0);
   begin
      Add_Scenario (C, Passed);
      Add_Step (C, Failed);
      Add_Parse_Error (C);
      Assert
        (C.Scenarios (Passed) = Natural'Last,
         "a scenario counter at Natural'Last saturates, does not wrap");
      Assert
        (C.Steps (Failed) = Natural'Last,
         "a step counter at Natural'Last saturates, does not wrap");
      Assert
        (C.Parse_Errors = Natural'Last,
         "Parse_Errors at Natural'Last saturates, does not wrap");
   end Test_Saturation;

   --  Every status's counter, scenario and step alike, stops at
   --  Natural'Last, and adding to one status leaves the others alone.
   procedure Test_Status_Saturation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Near : constant Natural := Natural'Last - 1;
   begin
      for S in Status loop
         declare
            C    : Counts :=
              (Scenarios => [others => Near],
               Steps     => [others => Near],
               others    => 0);
            Want : Status_Counts := [others => Near];
         begin
            Add_Scenario (C, S);
            Add_Scenario (C, S);
            Add_Step (C, S);
            Add_Step (C, S);
            Want (S) := Natural'Last;
            Assert
              (C.Scenarios = Want,
               S'Image & ": the scenario counter stops at Natural'Last");
            Assert
              (C.Steps = Want,
               S'Image & ": the step counter stops at Natural'Last");
         end;
      end loop;
      Assert
        (Saturating_Add (Natural'Last, 1) = Natural'Last,
         "a sum past Natural'Last stops there");
      Assert (Saturating_Add (Near, 1) = Natural'Last, "a sum up to it fits");
      Assert (Saturating_Add (2, 3) = 5, "a small sum is exact");
   end Test_Status_Saturation;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Counter_Accumulation'Access, "counters accumulate");
      Register_Routine (T, Test_All_Green'Access, "an all-green run passes");
      Register_Routine
        (T, Test_Failed_Scenario_Fails_Run'Access, "a failed scenario fails");
      Register_Routine
        (T, Test_Undefined_Step_Fails_Run'Access, "an undefined step fails");
      Register_Routine
        (T, Test_Parse_Error_Fails_Run'Access, "a parse error fails");
      Register_Routine
        (T, Test_Hook_Error_Fails_Run'Access, "a hook error fails");
      Register_Routine
        (T, Test_Skipped_Never_Fails'Access, "skipped never fails alone");
      Register_Routine
        (T,
         Test_Undefined_Scenario_Alone_Does_Not_Fail'Access,
         "an Undefined scenario alone does not fail");
      Register_Routine
        (T, Test_Saturation'Access, "counters saturate at Natural'Last");
      Register_Routine
        (T,
         Test_Status_Saturation'Access,
         "every status's counter saturates on its own");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Results (counts and the exit rule)"));

end Fabula_Results_Tests;
