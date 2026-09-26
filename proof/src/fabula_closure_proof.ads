--  The proof closure.  Every core unit must be reachable from here;
--  tools/proof_closure_lint.py fails on any unit gnatprove did not
--  analyze.
with Fabula.Limits;
with Fabula.Scan;

package Fabula_Closure_Proof
  with SPARK_Mode
is
   Arena_Holds_A_Line : constant Boolean :=
     Fabula.Limits.Text_Arena_Bytes >= Fabula.Limits.Max_Line_Length;

   Feature_Line_Classifies : constant Boolean :=
     Fabula.Scan.Classify ("Feature: x").Class in Fabula.Scan.Feature_Header;
end Fabula_Closure_Proof;
