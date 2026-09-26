package body Fabula_Closure_Proof
  with SPARK_Mode
is

   procedure Closure_Parse
     (P : out Fabula.Parse.Parser; Doc : in out Fabula.Ast.Document) is
   begin
      Fabula.Parse.Start (P, Doc);
      Fabula.Parse.Feed (P, Doc, "Feature: x", 1);
      Fabula.Parse.Feed (P, Doc, "  Scenario: y", 2);
      Fabula.Parse.Finish (P, Doc);
   end Closure_Parse;

   procedure Closure_Check (R : in out Fabula.Check.Outcome) is
   begin
      Closure_Compare.Equal (R, 1, 1);
      Closure_Compare.Not_Equal (R, 1, 2);
      Closure_Compare.Greater (R, 2, 1);
      Closure_Compare.Greater_Or_Equal (R, 1, 1);
      Closure_Compare.Less (R, 1, 2);
      Closure_Compare.Less_Or_Equal (R, 1, 1);
      Fabula.Check.Is_True (R, True);
      Fabula.Check.Text_Equal (R, "a", "b");
      Fabula.Check.Skip (R);
      Fabula.Check.Fail (R, "closure");
      Fabula.Check.Fail_Step (R);
   end Closure_Check;

   procedure Closure_Results (C : in out Fabula.Results.Counts) is
   begin
      Fabula.Results.Add_Scenario (C, Fabula.Results.Passed);
      Fabula.Results.Add_Step (C, Fabula.Results.Undefined);
      Fabula.Results.Add_Parse_Error (C);
      Fabula.Results.Add_Hook_Error (C);
      declare
         Failed : constant Boolean := Fabula.Results.Run_Failed (C);
         pragma Unreferenced (Failed);
      begin
         null;
      end;
   end Closure_Results;

   procedure Closure_Frame (F : in out Fabula.Frames.Frame) is
   begin
      Fabula.Frames.Set (F.Feature, "a feature");
      Fabula.Frames.Set (F.Scenario, "a scenario");
      Fabula.Frames.Set (F.Step, "a step");
      Fabula.Frames.Set (F.File, "a.feature");
      declare
         Step_Len : constant Natural := Fabula.Frames.Value (F.Step)'Length;
         pragma Unreferenced (Step_Len);
      begin
         null;
      end;
   end Closure_Frame;

end Fabula_Closure_Proof;
