with AUnit.Assertions;  use AUnit.Assertions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Fabula.Expressions;
with Fabula.Limits;
with Fabula.Registry;
with Fabula.Tags;

package body Fabula_Registry_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Expressions.Param_Kind;

   type Box_Step is (Place, Count_Items, Anything, Label);
   type Box_Hook is (Reset, Audit, Announce);

   type Box_Context is record
      Items : Natural := 0;
   end record;

   package Box is new
     Fabula.Registry
       (Step_Kind => Box_Step,
        Hook_Kind => Box_Hook,
        Context   => Box_Context);
   use Box;

   --  Tables are library-level constants, never on a test routine's
   --  stack: a row carries a whole compiled pattern.
   Box_Steps : constant Step_Table :=
     [Step ("I place {int} x {string} in it") >= Place,
      Step ("The box contains {int} item(s)") >= Count_Items,
      Step ("{}") >= Anything];

   --  The catch-all first: it wins every text, so the later row never.
   Catch_All_First : constant Step_Table :=
     [Step ("{}") >= Anything,
      Step ("The box contains {int} item(s)") >= Count_Items];

   No_Catch_All : constant Step_Table :=
     [Step ("An empty box") >= Place, Step ("The box is labeled") >= Label];

   --  Row 2 names an unknown parameter key, row 3 leaves a group open.
   Refused_Rows : constant Step_Table :=
     [Step ("An empty box") >= Place,
      Step ("I have {foo}") >= Label,
      Step ("(unbalanced") >= Label];

   --  Row 2 never met ">=", so it names no kind.
   Unbound_Rows : constant Step_Table :=
     [Step ("An empty box") >= Place, Step ("a row with no kind")];

   Empty_Steps : constant Step_Table := [];

   Box_Hooks : constant Hook_Table :=
     [Before ("@fresh") >= Reset,
      After >= Audit,
      Before_All >= Announce,
      After_All >= Announce,
      Before_Step >= Audit,
      After_Step >= Reset,
      Before ("   ") >= Reset];

   Refused_Hooks : constant Hook_Table :=
     [After >= Audit, Before ("@a and") >= Reset];

   Unbound_Hooks : constant Hook_Table := [After_All >= Audit, Before_All];

   --  One character over each bound, and otherwise well formed: a
   --  pattern of plain letters, and a single tag.
   Long_Pattern  : constant String :=
     (Fabula.Limits.Max_Pattern_Length + 1) * 'p';
   Long_Tag_Expr : constant String :=
     "@" & Fabula.Limits.Max_Tag_Expr_Length * 't';

   Overlong_Steps : constant Step_Table :=
     [Step ("An empty box") >= Place, Step (Long_Pattern) >= Label];

   Overlong_Hooks : constant Hook_Table :=
     [After >= Audit, Before (Long_Tag_Expr) >= Reset];

   --  Capture I of R, cut from the text it was matched against.
   function Captured
     (Text : String; R : Match_Result; I : Positive) return String
   is (Text (R.Captures.Items (I).First .. R.Captures.Items (I).Last));

   function Fresh_Only (Name : String) return Boolean
   is (Name = "@fresh");

   function Eval_Fresh is new Fabula.Tags.Eval (Has_Tag => Fresh_Only);

   procedure Test_Find_Captures (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Text : constant String := "I place 3 x ""pen"" in it";
      R    : constant Match_Result := Find (Box_Steps, Text);
   begin
      Assert (R.Found and then R.Index = 1, "the first row matches");
      Assert (Kind_Of (Box_Steps, R.Index) = Place, "row 1 is Place");
      Assert
        (R.Captures.Count = 2, "two captures, got" & R.Captures.Count'Image);
      Assert (Captured (Text, R, 1) = "3", "capture 1 is the count");
      Assert
        (R.Captures.Items (1).Kind = Fabula.Expressions.P_Int,
         "capture 1 is an {int}");
      Assert (Captured (Text, R, 2) = "pen", "capture 2 drops the quotes");
      Assert
        (R.Captures.Items (2).Kind = Fabula.Expressions.P_String,
         "capture 2 is a {string}");
   end Test_Find_Captures;

   --  Two rows match; the earlier one wins, as in the reference
   --  interpreter's registration order.
   procedure Test_First_Match_Wins
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Text  : constant String := "The box contains 2 items";
      Later : constant Match_Result := Find (Box_Steps, Text);
      First : constant Match_Result := Find (Catch_All_First, Text);
   begin
      Assert
        (Later.Found and then Later.Index = 2,
         "the specific row precedes the catch-all, got" & Later.Index'Image);
      Assert (Kind_Of (Box_Steps, Later.Index) = Count_Items, "Count_Items");
      Assert (Captured (Text, Later, 1) = "2", "its capture is forwarded");
      Assert
        (First.Found and then First.Index = 1,
         "a catch-all first wins, got" & First.Index'Image);
      Assert
        (Kind_Of (Catch_All_First, First.Index) = Anything,
         "the catch-all's kind");
      Assert (Captured (Text, First, 1) = Text, "the catch-all takes it all");
   end Test_First_Match_Wins;

   procedure Test_No_Match (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Match_Result := Find (No_Catch_All, "An empty crate");
   begin
      Assert (not R.Found, "no row matches");
      Assert (R.Index = 0, "no index, got" & R.Index'Image);
      Assert (R.Captures.Count = 0, "no captures");
   end Test_No_Match;

   procedure Test_Valid_Steps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Steps_Valid (Box_Steps), "a well-formed table is valid");
      Assert (First_Bad (Box_Steps) = 0, "and has no bad row");
      Assert (Steps_Valid (Empty_Steps), "an empty table is valid");
      Assert (First_Bad (Empty_Steps) = 0, "and has no bad row");
      Assert
        (Pattern_Text (Box_Steps, 2) = "The box contains {int} item(s)",
         "a row keeps its pattern as written");
   end Test_Valid_Steps;

   procedure Test_Refused_Pattern (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (not Steps_Valid (Refused_Rows), "a refused pattern invalidates");
      Assert
        (First_Bad (Refused_Rows) = 2,
         "row 2 is the first bad, got" & First_Bad (Refused_Rows)'Image);
      Assert (Step_Status (Refused_Rows, 1) = Row_Ok, "row 1 compiled");
      Assert (Step_Status (Refused_Rows, 2) = Refused, "unknown key refused");
      Assert (Step_Status (Refused_Rows, 3) = Refused, "open group refused");
      Assert
        (Pattern_Text (Refused_Rows, 2) = "I have {foo}",
         "the refused row keeps its text for the startup report");
   end Test_Refused_Pattern;

   procedure Test_Unbound_Row (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not Steps_Valid (Unbound_Rows), "a row with no kind invalidates");
      Assert (First_Bad (Unbound_Rows) = 2, "row 2 is the first bad");
      Assert (Step_Status (Unbound_Rows, 2) = Unbound, "row 2 is unbound");
   end Test_Unbound_Row;

   procedure Test_Hook_Phases (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Hooks_Valid (Box_Hooks), "a well-formed hook table is valid");
      Assert (First_Bad_Hook (Box_Hooks) = 0, "and has no bad row");
      Assert (Phase_Of (Box_Hooks, 1) = Scenario_Start, "Before");
      Assert (Phase_Of (Box_Hooks, 2) = Scenario_End, "After");
      Assert (Phase_Of (Box_Hooks, 3) = Run_Start, "Before_All");
      Assert (Phase_Of (Box_Hooks, 4) = Run_End, "After_All");
      Assert (Phase_Of (Box_Hooks, 5) = Step_Start, "Before_Step");
      Assert (Phase_Of (Box_Hooks, 6) = Step_End, "After_Step");
      Assert (Kind_Of (Box_Hooks, 1) = Reset, "row 1 runs Reset");
      Assert (Kind_Of (Box_Hooks, 2) = Audit, "row 2 runs Audit");
      Assert (Kind_Of (Box_Hooks, 3) = Announce, "row 3 runs Announce");
   end Test_Hook_Phases;

   procedure Test_Hook_Tags (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Has_Tag_Expr (Box_Hooks, 1), "Before (""@fresh"") is tagged");
      Assert
        (Fabula.Tags.Valid (Tag_Expr (Box_Hooks, 1)),
         "its expression compiled");
      Assert
        (Eval_Fresh (Tag_Expr (Box_Hooks, 1)),
         "the compiled expression selects @fresh");
      Assert
        (Tag_Expr_Text (Box_Hooks, 1) = "@fresh",
         "a hook keeps its expression as written");
      Assert
        (not Has_Tag_Expr (Box_Hooks, 2), "an empty expression: untagged");
      Assert
        (not Has_Tag_Expr (Box_Hooks, 7), "an all-blank expression: untagged");
      Assert (Hook_Status (Box_Hooks, 7) = Row_Ok, "and valid");
   end Test_Hook_Tags;

   procedure Test_Bad_Hooks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not Hooks_Valid (Refused_Hooks), "a refused expression invalidates");
      Assert
        (First_Bad_Hook (Refused_Hooks) = 2,
         "row 2 is the first bad, got" & First_Bad_Hook (Refused_Hooks)'Image);
      Assert (Hook_Status (Refused_Hooks, 2) = Refused, "a dangling and");
      Assert
        (Tag_Expr_Text (Refused_Hooks, 2) = "@a and",
         "the refused row keeps its text for the startup report");
      Assert
        (not Hooks_Valid (Unbound_Hooks), "a hook with no kind invalidates");
      Assert (First_Bad_Hook (Unbound_Hooks) = 2, "row 2 is the first bad");
      Assert (Hook_Status (Unbound_Hooks, 2) = Unbound, "row 2 is unbound");
   end Test_Bad_Hooks;

   --  Text over a bound is a refused row, not a contract failure: the
   --  tables above elaborated, and each keeps its first characters.
   procedure Test_Overlong (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Pattern_Max : constant := Fabula.Limits.Max_Pattern_Length;
      Expr_Max    : constant := Fabula.Limits.Max_Tag_Expr_Length;
   begin
      Assert
        (not Steps_Valid (Overlong_Steps), "an overlong pattern invalidates");
      Assert (First_Bad (Overlong_Steps) = 2, "row 2 is the first bad");
      Assert (Step_Status (Overlong_Steps, 2) = Refused, "and is refused");
      Assert
        (Pattern_Text (Overlong_Steps, 2) = Long_Pattern (1 .. Pattern_Max),
         "its text is kept up to the pattern bound");
      Assert (not Hooks_Valid (Overlong_Hooks), "an overlong tag expression");
      Assert (First_Bad_Hook (Overlong_Hooks) = 2, "row 2 is the first bad");
      Assert (Hook_Status (Overlong_Hooks, 2) = Refused, "and is refused");
      Assert (Has_Tag_Expr (Overlong_Hooks, 2), "it is a tagged hook");
      Assert
        (Tag_Expr_Text (Overlong_Hooks, 2) = Long_Tag_Expr (1 .. Expr_Max),
         "its text is kept up to the expression bound");
   end Test_Overlong;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Find_Captures'Access, "Find forwards a match's captures");
      Register_Routine
        (T, Test_First_Match_Wins'Access, "the first matching row wins");
      Register_Routine (T, Test_No_Match'Access, "no row matches");
      Register_Routine
        (T, Test_Valid_Steps'Access, "valid and empty step tables");
      Register_Routine
        (T, Test_Refused_Pattern'Access, "a refused pattern names its row");
      Register_Routine
        (T, Test_Unbound_Row'Access, "a row with no kind names its row");
      Register_Routine
        (T, Test_Hook_Phases'Access, "each hook constructor's phase");
      Register_Routine
        (T, Test_Hook_Tags'Access, "tagged, untagged and blank hooks");
      Register_Routine
        (T, Test_Bad_Hooks'Access, "a refused or unbound hook names its row");
      Register_Routine
        (T, Test_Overlong'Access, "overlong text is a refused row");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Registry (step and hook tables)"));

end Fabula_Registry_Tests;
