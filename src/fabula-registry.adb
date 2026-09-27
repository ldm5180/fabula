package body Fabula.Registry
  with SPARK_Mode
is

   --  A row keeps the first characters of the source its user wrote, as
   --  many as its Source holds.  An overlong pattern is never compiled,
   --  so the row keeps a default pattern, which is not Valid, and reads
   --  Refused.
   function Step (Pattern : String) return Step_Row is
      Result : Step_Row :=
        (Source => Texts.Truncated (Pattern, Limits.Max_Pattern_Length),
         others => <>);
   begin
      if Pattern'Length <= Limits.Max_Pattern_Length then
         Result.Pattern := Expressions.Compile (Pattern);
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
      Result : Hook_Row :=
        (Phase    => Phase,
         Has_Expr => not Tags.Blank (Tag_Expr),
         Source   => Texts.Truncated (Tag_Expr, Limits.Max_Tag_Expr_Length),
         others   => <>);
   begin
      if Result.Has_Expr and then Tag_Expr'Length <= Limits.Max_Tag_Expr_Length
      then
         Result.Expr := Tags.Compile (Texts.Value (Result.Source));
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
      function Is_Bad (I : Positive) return Boolean
      is (I in T'Range and then Step_Status (T, I) /= Row_Ok);

      function First_Bad_Row is new Searches.Find_First (Is_Bad);
   begin
      if T'Length = 0 then
         return No_Row;
      end if;
      return First_Bad_Row (T'First, T'Last);
   end First_Bad;

   function First_Bad_Hook (T : Hook_Table) return Natural is
      function Is_Bad (I : Positive) return Boolean
      is (I in T'Range and then Hook_Status (T, I) /= Row_Ok);

      function First_Bad_Row is new Searches.Find_First (Is_Bad);
   begin
      if T'Length = 0 then
         return No_Row;
      end if;
      return First_Bad_Row (T'First, T'Last);
   end First_Bad_Hook;

   function Pattern_Text (T : Step_Table; Index : Positive) return String
   is (Texts.Value (T (Index).Source));

   function Tag_Expr_Text (T : Hook_Table; Index : Positive) return String
   is (Texts.Value (T (Index).Source));

   --  Each row's match returns its captures, so this search stays a
   --  loop: Find_First would match the winning row a second time.
   function Find (T : Step_Table; Text : String) return Match_Result is
   begin
      for I in T'Range loop
         declare
            Row : constant Expressions.Step_Match :=
              Expressions.Match (T (I).Pattern, Text);
         begin
            if Row.Found then
               return (Found => True, Index => I, Captures => Row.Captures);
            end if;
         end;
      end loop;
      return (Found => False, Index => No_Row, Captures => <>);
   end Find;

end Fabula.Registry;
