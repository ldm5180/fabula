--  The proof closure.  Every core unit must be reachable from here;
--  tools/proof_closure_lint.py fails on any unit gnatprove did not
--  analyze.  A generic (Fabula.Tags.Eval) is analyzed only through a
--  concrete instance, so one is instantiated here.
with Fabula.Ast;
with Fabula.Check;
with Fabula.Expressions;
with Fabula.Frames;
with Fabula.Limits;
with Fabula.Parse;
with Fabula.Results;
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

   --  A second Integer instance of Compare, alongside the shipped
   --  Fabula.Check.Ints: belt and suspenders for the generic's proof
   --  coverage, since a bare child-unit instantiation needs its own
   --  `pragma SPARK_Mode;` (an aspect there is rejected) before
   --  gnatprove analyzes it rather than skipping it as Off.
   package Closure_Compare is new
     Fabula.Check.Compare
       (Item  => Integer,
        Image => Fabula.Check.Integer_Image);

   --  Reaches Closure_Compare's six comparisons and the plain checks
   --  and scenario controls declared directly on Fabula.Check.
   procedure Closure_Check (R : in out Fabula.Check.Outcome);

   --  One scenario's worth of counters, reaching the exit rule.
   procedure Closure_Results (C : in out Fabula.Results.Counts);

   --  A Frame's bounded fields, filled and read back.
   procedure Closure_Frame (F : in out Fabula.Frames.Frame);

end Fabula_Closure_Proof;
