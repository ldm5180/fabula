with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast;
with Fabula.Step_Walk; use Fabula.Step_Walk;

package body Fabula_Step_Walk_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Ast.Step_Handle;

   subtype Step_Handle is Fabula.Ast.Step_Handle;

   No_Steps : Fabula.Ast.Step_Range renames Fabula.Ast.Step_Pool.Empty;

   function Steps (First, Last : Step_Handle) return Fabula.Ast.Step_Range
   is ((First => First, Last => Last));

   --  Moves W on once, then checks where it stands.
   procedure Expect_Next
     (W     : in out Walk;
      State : Segment;
      Step  : Step_Handle;
      Found : Boolean;
      What  : String)
   is
      Got_State : Segment;
      Got_Step  : Step_Handle;
   begin
      Next (W);
      Got_State := State_Of (W);
      Got_Step := Step_Of (W);
      Assert
        (Got_State = State,
         What
         & ": state "
         & State'Image
         & " expected, got "
         & Got_State'Image);
      Assert
        (Got_Step = Step,
         What & ": step " & Step'Image & " expected, got " & Got_Step'Image);
      Assert
        (Fabula.Step_Walk.Found (W) = Found,
         What & ": found " & Found'Image & " expected");
   end Expect_Next;

   --  Steps 1 and 2 are the background's, 3 and 4 the scenario's own.
   procedure Test_Both (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      W : Walk := Started (Steps (1, 2), Steps (3, 4), 4);
   begin
      Assert (State_Of (W) = Not_Started, "a started walk has not moved");
      Assert (not Found (W), "a started walk has found no step");
      Expect_Next (W, Background, 1, True, "not started, background first");
      Expect_Next (W, Background, 2, True, "background step left");
      Expect_Next (W, Own, 3, True, "background done, own steps next");
      Expect_Next (W, Own, 4, True, "own step left");
      Expect_Next (W, Own, 4, False, "own steps done: the cursor stays");
      Expect_Next (W, Own, 4, False, "and stays on every later move");
   end Test_Both;

   procedure Test_Background_Only (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W : Walk := Started (Steps (1, 2), No_Steps, 2);
   begin
      Expect_Next (W, Background, 1, True, "not started, background first");
      Expect_Next (W, Background, 2, True, "background step left");
      Expect_Next
        (W, Background, 2, False, "no own step: the cursor stays in place");
   end Test_Background_Only;

   procedure Test_Own_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      W : Walk := Started (No_Steps, Steps (1, 2), 2);
   begin
      Expect_Next (W, Own, 1, True, "not started, no background: own first");
      Expect_Next (W, Own, 2, True, "own step left");
      Expect_Next (W, Own, 2, False, "own steps done: the cursor stays");
   end Test_Own_Only;

   procedure Test_No_Steps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      W : Walk := Empty;
   begin
      Expect_Next
        (W, Not_Started, Fabula.Ast.No_Step, False, "no step at all");
      Expect_Next
        (W, Not_Started, Fabula.Ast.No_Step, False, "and none on a retry");
   end Test_No_Steps;

   --  A step past the document's count is never found, even where a
   --  range names it.
   procedure Test_Outside_Document
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W : Walk := Started (No_Steps, Steps (3, 4), 3);
   begin
      Expect_Next (W, Own, 3, True, "the document's last step");
      Expect_Next (W, Own, 4, False, "a step past the document's count");
   end Test_Outside_Document;

   --  A walk started for the next scenario forgets the last one.
   procedure Test_Restart (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      W : Walk := Started (Steps (1, 1), Steps (2, 2), 3);
   begin
      Expect_Next (W, Background, 1, True, "the first scenario's background");
      Expect_Next (W, Own, 2, True, "the first scenario's own step");
      W := Started (Steps (1, 1), Steps (3, 3), 3);
      Assert (State_Of (W) = Not_Started, "the next scenario starts afresh");
      Assert (not Found (W), "and has found no step yet");
      Expect_Next (W, Background, 1, True, "the background again");
      Expect_Next (W, Own, 3, True, "then the next scenario's own step");
   end Test_Restart;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Both'Access, "background steps, then the scenario's own");
      Register_Routine
        (T, Test_Background_Only'Access, "background steps only");
      Register_Routine (T, Test_Own_Only'Access, "the scenario's own only");
      Register_Routine (T, Test_No_Steps'Access, "no step: none is found");
      Register_Routine
        (T, Test_Outside_Document'Access, "only a step in the document");
      Register_Routine
        (T, Test_Restart'Access, "a new scenario starts a new walk");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Step_Walk (the step cursor's table)"));

end Fabula_Step_Walk_Tests;
