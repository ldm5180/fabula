with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Limits;

package body Fabula_Limits_Tests is

   use AUnit.Test_Cases.Registration;

   --  Trivial by design: every constant in Fabula.Limits is a shipped
   --  capacity, so this proves the harness runs a real assertion rather
   --  than exercising the values themselves.
   procedure Test_Limits_Are_Positive
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Fabula.Limits.Max_Line_Length > 0,
         "Max_Line_Length must be positive");
      Assert
        (Fabula.Limits.Text_Arena_Bytes > 0,
         "Text_Arena_Bytes must be positive");
      Assert (Fabula.Limits.Max_Steps > 0, "Max_Steps must be positive");
      Assert
        (Fabula.Limits.Max_Scenarios > 0, "Max_Scenarios must be positive");
      Assert (Fabula.Limits.Max_Rules > 0, "Max_Rules must be positive");
      Assert
        (Fabula.Limits.Max_Table_Rows > 0, "Max_Table_Rows must be positive");
      Assert
        (Fabula.Limits.Max_Table_Cells > 0,
         "Max_Table_Cells must be positive");
      Assert (Fabula.Limits.Max_Tags > 0, "Max_Tags must be positive");
      Assert
        (Fabula.Limits.Max_Examples_Rows > 0,
         "Max_Examples_Rows must be positive");
      Assert
        (Fabula.Limits.Max_Doc_Lines > 0, "Max_Doc_Lines must be positive");
      Assert
        (Fabula.Limits.Max_Examples_Blocks > 0,
         "Max_Examples_Blocks must be positive");
      Assert
        (Fabula.Limits.Max_Features_Per_Run > 0,
         "Max_Features_Per_Run must be positive");
      Assert
        (Fabula.Limits.Max_Step_Defs > 0, "Max_Step_Defs must be positive");
      Assert (Fabula.Limits.Max_Hooks > 0, "Max_Hooks must be positive");
      Assert
        (Fabula.Limits.Max_Pattern_Length > 0,
         "Max_Pattern_Length must be positive");
      Assert
        (Fabula.Limits.Max_Args_Per_Step > 0,
         "Max_Args_Per_Step must be positive");
      Assert
        (Fabula.Limits.Text_Arena_Bytes >= Fabula.Limits.Max_Line_Length,
         "the arena must hold at least one full line");
   end Test_Limits_Are_Positive;

   --  The tag-expression compiler's two capacities.
   procedure Test_Tag_Expr_Limits (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Fabula.Limits.Max_Tag_Expr_Length > 0,
         "Max_Tag_Expr_Length must be positive");
      Assert
        (Fabula.Limits.Max_Tag_Expr_Tokens > 0,
         "Max_Tag_Expr_Tokens must be positive");
   end Test_Tag_Expr_Limits;

   --  The pattern matcher's two capacities, and the relation between
   --  them: the matcher keeps at most one choice per pattern token.
   procedure Test_Matcher_Limits (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Fabula.Limits.Max_Pattern_Tokens > 0,
         "Max_Pattern_Tokens must be positive");
      Assert
        (Fabula.Limits.Max_Match_Choices > 0,
         "Max_Match_Choices must be positive");
      Assert
        (Fabula.Limits.Max_Match_Choices > Fabula.Limits.Max_Pattern_Tokens,
         "the choice stack must hold one choice per pattern token");
   end Test_Matcher_Limits;

   --  The check, results and frame capacities added in P5.
   procedure Test_Check_Frame_Limits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Fabula.Limits.Max_Message_Length > 0,
         "Max_Message_Length must be positive");
      Assert
        (Fabula.Limits.Max_Name_Length > 0,
         "Max_Name_Length must be positive");
      Assert
        (Fabula.Limits.Max_Path_Length > 0,
         "Max_Path_Length must be positive");
      Assert
        (Fabula.Limits.Max_Step_Text_Length > 0,
         "Max_Step_Text_Length must be positive");
      Assert
        (Fabula.Limits.Max_Step_Text_Length = Fabula.Limits.Max_Line_Length,
         "a step's text is bounded the same as a scanned line");
   end Test_Check_Frame_Limits;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T,
         Test_Limits_Are_Positive'Access,
         "every shipped capacity is positive");
      Register_Routine
        (T,
         Test_Matcher_Limits'Access,
         "the matcher's capacities are consistent");
      Register_Routine
        (T, Test_Tag_Expr_Limits'Access, "the tag-expression capacities");
      Register_Routine
        (T, Test_Check_Frame_Limits'Access, "the check/frame capacities");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Limits (shipped capacities)"));

end Fabula_Limits_Tests;
