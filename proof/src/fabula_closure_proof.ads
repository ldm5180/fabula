--  The proof closure.  Every core unit must be reachable from here;
--  tools/proof_closure_lint.py fails on any unit gnatprove did not
--  analyze.  A generic (Fabula.Tags.Eval) is analyzed only through a
--  concrete instance, so one is instantiated here.
with Fabula.Ast;
with Fabula.Expressions;
with Fabula.Limits;
with Fabula.Parse;
with Fabula.Scan;
with Fabula.Tags;

package Fabula_Closure_Proof
  with SPARK_Mode
is
   Arena_Holds_A_Line : constant Boolean :=
     Fabula.Limits.Text_Arena_Bytes >= Fabula.Limits.Max_Line_Length;

   Feature_Line_Classifies : constant Boolean :=
     Fabula.Scan.Classify ("Feature: x").Class in Fabula.Scan.Feature_Header;

   Every_Argument_Has_A_Capture : constant Boolean :=
     Fabula.Expressions.Capture_Items'Length = Fabula.Limits.Max_Args_Per_Step;

   --  Fixes the instance's tag set to {"@a"}; only gnatprove's analysis
   --  of the instance matters here, not the value it computes.
   function Closure_Has_Tag (Name : String) return Boolean
   is (Name = "@a");

   function Closure_Eval is new Fabula.Tags.Eval (Has_Tag => Closure_Has_Tag);

   --  Mirrors the real calling convention: check Valid before calling
   --  Eval.  Compile ("@a") is always valid, so the Then branch is the
   --  one actually taken; the Else branch exists only to give Error a
   --  call site here too.
   Closure_Tag_Expr : constant Fabula.Tags.Compiled :=
     Fabula.Tags.Compile ("@a");

   Tag_Expr_Round_Trips : constant Boolean :=
     (if Fabula.Tags.Valid (Closure_Tag_Expr)
      then Closure_Eval (Closure_Tag_Expr)
      else Fabula.Tags.Error (Closure_Tag_Expr) > 0);

   Empty_Slice_Is_Empty : constant Boolean :=
     Fabula.Ast.Length (Fabula.Ast.Empty_Slice) = 0;

   --  One parse of a two-line feature, as the shell will run it: proves
   --  Start, Feed and Finish callable under their contracts, and
   --  reaches the parser machine's sml instance (inside the private
   --  Fabula.Grammar) at the shipped capacities.
   procedure Closure_Parse
     (P : out Fabula.Parse.Parser; Doc : in out Fabula.Ast.Document);
end Fabula_Closure_Proof;
