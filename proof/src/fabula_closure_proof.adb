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

end Fabula_Closure_Proof;
