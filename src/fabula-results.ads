--  Run-level accounting and the exit rule: the detailed report streams
--  out elsewhere; this holds only counters and the flags that decide
--  the exit code.

package Fabula.Results
  with SPARK_Mode
is

   type Status is (Passed, Failed, Skipped, Undefined);
   --  Ignored scenarios are REMOVED, not counted (the reference
   --  interpreter's own behavior).  The runner records a scenario with
   --  an undefined step as Failed, never Undefined: Undefined names a
   --  STEP's status only, matching the reference interpreter.

   --  Every counter's value before its first count.
   Nothing_Counted : constant Natural := 0;

   type Status_Counts is array (Status) of Natural;

   No_Counts : constant Status_Counts := [others => Nothing_Counted];

   type Counts is record
      Scenarios    : Status_Counts := No_Counts;
      Steps        : Status_Counts := No_Counts;
      Parse_Errors : Natural := Nothing_Counted;
      Hook_Errors  : Natural := Nothing_Counted;   --  Before_All/After_All
   end record;

   --  A + B, capped at Natural'Last: every counter and every total
   --  saturates instead of overflowing.
   function Saturating_Add (A, B : Natural) return Natural
   is (if A > Natural'Last - B then Natural'Last else A + B);

   --  Count plus one, capped at Natural'Last.
   function Incremented (Count : Natural) return Natural
   is (if Count < Natural'Last then Count + 1 else Count);

   --  At least one was counted.
   function Counted (Count : Natural) return Boolean
   is (Count > 0);

   procedure Add_Scenario (C : in out Counts; S : Status)
   with
     Post =>
       C.Scenarios (S) = Incremented (C'Old.Scenarios (S))
       and then (for all Other in Status =>
                   (if Other /= S
                    then C.Scenarios (Other) = C'Old.Scenarios (Other)))
       and then C.Steps = C'Old.Steps
       and then C.Parse_Errors = C'Old.Parse_Errors
       and then C.Hook_Errors = C'Old.Hook_Errors;

   procedure Add_Step (C : in out Counts; S : Status)
   with
     Post =>
       C.Steps (S) = Incremented (C'Old.Steps (S))
       and then (for all Other in Status =>
                   (if Other /= S then C.Steps (Other) = C'Old.Steps (Other)))
       and then C.Scenarios = C'Old.Scenarios
       and then C.Parse_Errors = C'Old.Parse_Errors
       and then C.Hook_Errors = C'Old.Hook_Errors;

   procedure Add_Parse_Error (C : in out Counts)
   with
     Post =>
       C.Parse_Errors = Incremented (C'Old.Parse_Errors)
       and then C.Scenarios = C'Old.Scenarios
       and then C.Steps = C'Old.Steps
       and then C.Hook_Errors = C'Old.Hook_Errors;

   procedure Add_Hook_Error (C : in out Counts)
   with
     Post =>
       C.Hook_Errors = Incremented (C'Old.Hook_Errors)
       and then C.Scenarios = C'Old.Scenarios
       and then C.Steps = C'Old.Steps
       and then C.Parse_Errors = C'Old.Parse_Errors;

   --  Every status's count added up, saturating: a saturating sum is
   --  the true sum capped at Natural'Last whatever the grouping.
   function Total (C : Status_Counts) return Natural
   is (Saturating_Add
         (Saturating_Add (C (Failed), C (Skipped)),
          Saturating_Add (C (Passed), C (Undefined))));

   --  Each status's two counts added, saturating.
   function Sum (Left, Right : Status_Counts) return Status_Counts
   with
     Post =>
       (for all S in Status =>
          Sum'Result (S) = Saturating_Add (Left (S), Right (S)));

   function Run_Failed (C : Counts) return Boolean;
   --  True when any scenario failed, any step was undefined, any
   --  file failed to parse, or an all-hook failed.

end Fabula.Results;
