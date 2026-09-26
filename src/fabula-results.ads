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

   type Counts is record
      Scenarios_Passed    : Natural := 0;
      Scenarios_Failed    : Natural := 0;
      Scenarios_Skipped   : Natural := 0;
      Scenarios_Undefined : Natural := 0;
      Steps_Passed        : Natural := 0;
      Steps_Failed        : Natural := 0;
      Steps_Skipped       : Natural := 0;
      Steps_Undefined     : Natural := 0;
      Parse_Errors        : Natural := 0;
      Hook_Errors         : Natural := 0;   --  Before_All/After_All failures
   end record;

   procedure Add_Scenario (C : in out Counts; S : Status)
   with
     Post =>
       (case S is
          when Passed    =>
            (if C'Old.Scenarios_Passed < Natural'Last
             then C.Scenarios_Passed = C'Old.Scenarios_Passed + 1
             else C.Scenarios_Passed = Natural'Last),
          when Failed    =>
            (if C'Old.Scenarios_Failed < Natural'Last
             then C.Scenarios_Failed = C'Old.Scenarios_Failed + 1
             else C.Scenarios_Failed = Natural'Last),
          when Skipped   =>
            (if C'Old.Scenarios_Skipped < Natural'Last
             then C.Scenarios_Skipped = C'Old.Scenarios_Skipped + 1
             else C.Scenarios_Skipped = Natural'Last),
          when Undefined =>
            (if C'Old.Scenarios_Undefined < Natural'Last
             then C.Scenarios_Undefined = C'Old.Scenarios_Undefined + 1
             else C.Scenarios_Undefined = Natural'Last));

   procedure Add_Step (C : in out Counts; S : Status)
   with
     Post =>
       (case S is
          when Passed    =>
            (if C'Old.Steps_Passed < Natural'Last
             then C.Steps_Passed = C'Old.Steps_Passed + 1
             else C.Steps_Passed = Natural'Last),
          when Failed    =>
            (if C'Old.Steps_Failed < Natural'Last
             then C.Steps_Failed = C'Old.Steps_Failed + 1
             else C.Steps_Failed = Natural'Last),
          when Skipped   =>
            (if C'Old.Steps_Skipped < Natural'Last
             then C.Steps_Skipped = C'Old.Steps_Skipped + 1
             else C.Steps_Skipped = Natural'Last),
          when Undefined =>
            (if C'Old.Steps_Undefined < Natural'Last
             then C.Steps_Undefined = C'Old.Steps_Undefined + 1
             else C.Steps_Undefined = Natural'Last));

   procedure Add_Parse_Error (C : in out Counts)
   with
     Post =>
       (if C'Old.Parse_Errors < Natural'Last
        then C.Parse_Errors = C'Old.Parse_Errors + 1
        else C.Parse_Errors = Natural'Last);

   procedure Add_Hook_Error (C : in out Counts)
   with
     Post =>
       (if C'Old.Hook_Errors < Natural'Last
        then C.Hook_Errors = C'Old.Hook_Errors + 1
        else C.Hook_Errors = Natural'Last);

   function Run_Failed (C : Counts) return Boolean;
   --  True when any scenario failed, any step was undefined, any
   --  file failed to parse, or an all-hook failed.

end Fabula.Results;
