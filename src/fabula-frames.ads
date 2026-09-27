--  What a step or hook may know about its position: the reference
--  interpreter's current_feature / current_scenario / current_step.
--  Bounded copies, filled by the runner once per scenario and once
--  per step -- deliberately independent of the parse arena so hooks
--  and tests need no AST types.
with Fabula.Limits;

package Fabula.Frames
  with SPARK_Mode
is

   type Name_Text is record
      Data : String (1 .. Limits.Max_Name_Length) := [others => ' '];
      Len  : Natural range 0 .. Limits.Max_Name_Length := 0;
   end record;

   type Path_Text is record
      Data : String (1 .. Limits.Max_Path_Length) := [others => ' '];
      Len  : Natural range 0 .. Limits.Max_Path_Length := 0;
   end record;

   type Step_Text is record
      Data : String (1 .. Limits.Max_Step_Text_Length) := [others => ' '];
      Len  : Natural range 0 .. Limits.Max_Step_Text_Length := 0;
   end record;

   type Frame is record
      File          : Path_Text;
      Feature       : Name_Text;
      Feature_Line  : Natural := No_Line;
      Scenario      : Name_Text;
      Scenario_Line : Natural := No_Line;
      Step          : Step_Text;
      Step_Line     : Natural := No_Line;
      --  Step components stay empty outside step execution.
   end record;

   procedure Set (T : out Name_Text; Value : String);  --  truncates
   function Value (T : Name_Text) return String;

   procedure Set (T : out Path_Text; Value : String);  --  truncates
   function Value (T : Path_Text) return String;

   procedure Set (T : out Step_Text; Value : String);  --  truncates
   function Value (T : Step_Text) return String;

end Fabula.Frames;
