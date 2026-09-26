package body Fabula.Results
  with SPARK_Mode
is

   procedure Add_Scenario (C : in out Counts; S : Status) is
   begin
      case S is
         when Passed    =>
            if C.Scenarios_Passed < Natural'Last then
               C.Scenarios_Passed := C.Scenarios_Passed + 1;
            end if;

         when Failed    =>
            if C.Scenarios_Failed < Natural'Last then
               C.Scenarios_Failed := C.Scenarios_Failed + 1;
            end if;

         when Skipped   =>
            if C.Scenarios_Skipped < Natural'Last then
               C.Scenarios_Skipped := C.Scenarios_Skipped + 1;
            end if;

         when Undefined =>
            if C.Scenarios_Undefined < Natural'Last then
               C.Scenarios_Undefined := C.Scenarios_Undefined + 1;
            end if;
      end case;
   end Add_Scenario;

   procedure Add_Step (C : in out Counts; S : Status) is
   begin
      case S is
         when Passed    =>
            if C.Steps_Passed < Natural'Last then
               C.Steps_Passed := C.Steps_Passed + 1;
            end if;

         when Failed    =>
            if C.Steps_Failed < Natural'Last then
               C.Steps_Failed := C.Steps_Failed + 1;
            end if;

         when Skipped   =>
            if C.Steps_Skipped < Natural'Last then
               C.Steps_Skipped := C.Steps_Skipped + 1;
            end if;

         when Undefined =>
            if C.Steps_Undefined < Natural'Last then
               C.Steps_Undefined := C.Steps_Undefined + 1;
            end if;
      end case;
   end Add_Step;

   procedure Add_Parse_Error (C : in out Counts) is
   begin
      if C.Parse_Errors < Natural'Last then
         C.Parse_Errors := C.Parse_Errors + 1;
      end if;
   end Add_Parse_Error;

   procedure Add_Hook_Error (C : in out Counts) is
   begin
      if C.Hook_Errors < Natural'Last then
         C.Hook_Errors := C.Hook_Errors + 1;
      end if;
   end Add_Hook_Error;

   function Run_Failed (C : Counts) return Boolean
   is (C.Scenarios_Failed > 0
       or else C.Steps_Undefined > 0
       or else C.Parse_Errors > 0
       or else C.Hook_Errors > 0);

end Fabula.Results;
