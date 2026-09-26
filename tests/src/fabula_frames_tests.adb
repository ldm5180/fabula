with AUnit.Assertions;  use AUnit.Assertions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Fabula.Frames; use Fabula.Frames;
with Fabula.Limits;

package body Fabula_Frames_Tests is

   use AUnit.Test_Cases.Registration;

   procedure Test_Name_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      N : Name_Text;
   begin
      Set (N, "a checkout scenario");
      Assert
        (Value (N) = "a checkout scenario",
         "Name_Text round-trips, got """ & Value (N) & """");
   end Test_Name_Round_Trip;

   procedure Test_Name_Truncation (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      N    : Name_Text;
      Long : constant String := (Fabula.Limits.Max_Name_Length + 10) * 'x';
   begin
      Set (N, Long);
      Assert
        (Value (N)'Length = Fabula.Limits.Max_Name_Length,
         "a name over the cap truncates to the cap");
      Assert
        (Value (N)
         = Long (Long'First .. Long'First + Fabula.Limits.Max_Name_Length - 1),
         "the truncated name keeps its FIRST Max_Name_Length characters");
   end Test_Name_Truncation;

   procedure Test_Path_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P : Path_Text;
   begin
      Set (P, "features/checkout.feature");
      Assert
        (Value (P) = "features/checkout.feature",
         "Path_Text round-trips, got """ & Value (P) & """");
   end Test_Path_Round_Trip;

   procedure Test_Path_Truncation (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P    : Path_Text;
      Long : constant String := (Fabula.Limits.Max_Path_Length + 10) * 'y';
   begin
      Set (P, Long);
      Assert
        (Value (P)'Length = Fabula.Limits.Max_Path_Length,
         "a path over the cap truncates to the cap");
   end Test_Path_Truncation;

   procedure Test_Step_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Step_Text;
   begin
      Set (S, "I place 3 apples in the box");
      Assert
        (Value (S) = "I place 3 apples in the box",
         "Step_Text round-trips, got """ & Value (S) & """");
   end Test_Step_Round_Trip;

   procedure Test_Step_Truncation (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S    : Step_Text;
      Long : constant String :=
        (Fabula.Limits.Max_Step_Text_Length + 10) * 'z';
   begin
      Set (S, Long);
      Assert
        (Value (S)'Length = Fabula.Limits.Max_Step_Text_Length,
         "a step text over the cap truncates to the cap");
   end Test_Step_Truncation;

   procedure Test_Frame_Defaults (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      F : Frame;
   begin
      Assert (Value (F.File) = "", "File is empty by default");
      Assert (Value (F.Feature) = "", "Feature is empty by default");
      Assert (F.Feature_Line = 0, "Feature_Line is 0 by default");
      Assert (Value (F.Scenario) = "", "Scenario is empty by default");
      Assert (F.Scenario_Line = 0, "Scenario_Line is 0 by default");
      Assert
        (Value (F.Step) = "", "Step text stays empty outside step execution");
      Assert (F.Step_Line = 0, "Step_Line is 0 by default");
   end Test_Frame_Defaults;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Name_Round_Trip'Access, "Name_Text Set/Value round-trip");
      Register_Routine
        (T, Test_Name_Truncation'Access, "Name_Text truncates at the cap");
      Register_Routine
        (T, Test_Path_Round_Trip'Access, "Path_Text Set/Value round-trip");
      Register_Routine
        (T, Test_Path_Truncation'Access, "Path_Text truncates at the cap");
      Register_Routine
        (T, Test_Step_Round_Trip'Access, "Step_Text Set/Value round-trip");
      Register_Routine
        (T, Test_Step_Truncation'Access, "Step_Text truncates at the cap");
      Register_Routine
        (T, Test_Frame_Defaults'Access, "a Frame's step fields default empty");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Frames (feature, scenario, step position)"));

end Fabula_Frames_Tests;
