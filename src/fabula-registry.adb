package body Fabula.Registry
  with SPARK_Mode
is

   --  The six characters the tag-expression lexer skips as blanks.
   function Is_Whitespace (Ch : Character) return Boolean
   is (Ch in ' ' | ASCII.HT | ASCII.CR | ASCII.LF | ASCII.VT | ASCII.FF);

   function Is_Blank (Expr : String) return Boolean
   is (for all Ch of Expr => Is_Whitespace (Ch));

   --  An overlong pattern is never compiled, so Compiled_Ok stays False
   --  and the row reads Refused.
   function Step (Pattern : String) return Step_Row is
      Kept   : constant Pattern_Length :=
        Natural'Min (Pattern'Length, Limits.Max_Pattern_Length);
      Result : Step_Row;
   begin
      if Kept > 0 then
         Result.Source (1 .. Kept) :=
           Pattern (Pattern'First .. Pattern'First + (Kept - 1));
      end if;
      Result.Source_Len := Kept;
      if Pattern'Length <= Limits.Max_Pattern_Length then
         Expressions.Compile (Pattern, Result.Pattern, Result.Compiled_Ok);
      end if;
      return Result;
   end Step;

   function ">=" (L : Step_Row; R : Step_Kind) return Step_Row
   is ((L with delta Kind => R, Bound => True));

   function Untagged (Phase : Hook_Phase) return Hook_Row
   is ((Phase => Phase, others => <>));

   --  A Before or After hook.  A blank expression leaves it untagged,
   --  so Tags.Compile, which refuses a blank expression, never sees it.
   --  An overlong one is never compiled: Expr keeps its default, which
   --  is not Valid, so the row reads Refused.
   function Tagged_Hook (Phase : Hook_Phase; Tag_Expr : String) return Hook_Row
   is
      Kept   : constant Tag_Expr_Length :=
        Natural'Min (Tag_Expr'Length, Limits.Max_Tag_Expr_Length);
      Result : Hook_Row := Untagged (Phase);
   begin
      if Kept > 0 then
         Result.Source (1 .. Kept) :=
           Tag_Expr (Tag_Expr'First .. Tag_Expr'First + (Kept - 1));
      end if;
      Result.Source_Len := Kept;
      if Is_Blank (Tag_Expr) then
         return Result;
      end if;
      Result.Has_Expr := True;
      if Tag_Expr'Length <= Limits.Max_Tag_Expr_Length then
         Result.Expr := Tags.Compile (Result.Source (1 .. Kept));
      end if;
      return Result;
   end Tagged_Hook;

   function Before_All return Hook_Row
   is (Untagged (Run_Start));

   function After_All return Hook_Row
   is (Untagged (Run_End));

   function Before (Tag_Expr : String := "") return Hook_Row
   is (Tagged_Hook (Scenario_Start, Tag_Expr));

   function After (Tag_Expr : String := "") return Hook_Row
   is (Tagged_Hook (Scenario_End, Tag_Expr));

   function Before_Step return Hook_Row
   is (Untagged (Step_Start));

   function After_Step return Hook_Row
   is (Untagged (Step_End));

   function ">=" (L : Hook_Row; R : Hook_Kind) return Hook_Row
   is ((L with delta Kind => R, Bound => True));

   function First_Bad (T : Step_Table) return Natural is
   begin
      for I in T'Range loop
         pragma
           Loop_Invariant
             (for all J in T'First .. I - 1 => Step_Status (T, J) = Row_Ok);
         if Step_Status (T, I) /= Row_Ok then
            return I;
         end if;
      end loop;
      return 0;
   end First_Bad;

   function First_Bad_Hook (T : Hook_Table) return Natural is
   begin
      for I in T'Range loop
         pragma
           Loop_Invariant
             (for all J in T'First .. I - 1 => Hook_Status (T, J) = Row_Ok);
         if Hook_Status (T, I) /= Row_Ok then
            return I;
         end if;
      end loop;
      return 0;
   end First_Bad_Hook;

   function Pattern_Text (T : Step_Table; Index : Positive) return String
   is (T (Index).Source (1 .. T (Index).Source_Len));

   function Tag_Expr_Text (T : Hook_Table; Index : Positive) return String
   is (T (Index).Source (1 .. T (Index).Source_Len));

   function Find (T : Step_Table; Text : String) return Match_Result is
      Captures : Expressions.Capture_List;
      Matched  : Boolean;
   begin
      for I in T'Range loop
         Expressions.Match (T (I).Pattern, Text, Captures, Matched);
         if Matched then
            return (Found => True, Index => I, Captures => Captures);
         end if;
      end loop;
      return (Found => False, Index => 0, Captures => <>);
   end Find;

end Fabula.Registry;
