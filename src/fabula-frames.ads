--  What a step or hook may know about its position: the reference
--  interpreter's current_feature / current_scenario / current_step.
--  Bounded copies, filled by the runner once per scenario and once
--  per step -- deliberately independent of the parse arena so hooks
--  and tests need no AST types.
with Fabula.Limits;
with Fabula.Texts;

package Fabula.Frames
  with SPARK_Mode
is

   subtype Name_Text is Texts.Bounded_Text (Limits.Max_Name_Length);
   subtype Path_Text is Texts.Bounded_Text (Limits.Max_Path_Length);
   subtype Step_Text is Texts.Bounded_Text (Limits.Max_Step_Text_Length);

   type Frame is record
      File          : Path_Text;
      Feature       : Name_Text;
      Feature_Line  : Line_Number := No_Line;
      Scenario      : Name_Text;
      Scenario_Line : Line_Number := No_Line;
      Step          : Step_Text;
      Step_Line     : Line_Number := No_Line;
      --  Step components stay empty outside step execution.
   end record;

   --  Each keeps Value's first characters, as many as its text holds.
   function To_Name (Value : String) return Name_Text;
   function To_Path (Value : String) return Path_Text;
   function To_Step (Value : String) return Step_Text;

   function Value (T : Texts.Bounded_Text) return String renames Texts.Value;

end Fabula.Frames;
