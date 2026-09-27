package body Fabula.Results
  with SPARK_Mode
is

   procedure Add_Scenario (C : in out Counts; S : Status) is
   begin
      C.Scenarios (S) := Incremented (C.Scenarios (S));
   end Add_Scenario;

   procedure Add_Step (C : in out Counts; S : Status) is
   begin
      C.Steps (S) := Incremented (C.Steps (S));
   end Add_Step;

   procedure Add_Parse_Error (C : in out Counts) is
   begin
      C.Parse_Errors := Incremented (C.Parse_Errors);
   end Add_Parse_Error;

   procedure Add_Hook_Error (C : in out Counts) is
   begin
      C.Hook_Errors := Incremented (C.Hook_Errors);
   end Add_Hook_Error;

   function Sum (Left, Right : Status_Counts) return Status_Counts
   is ([for S in Status => Saturating_Add (Left (S), Right (S))]);

   function Run_Failed (C : Counts) return Boolean
   is (Counted (C.Scenarios (Failed))
       or else Counted (C.Steps (Undefined))
       or else Counted (C.Parse_Errors)
       or else Counted (C.Hook_Errors));

end Fabula.Results;
