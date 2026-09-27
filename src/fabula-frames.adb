package body Fabula.Frames
  with SPARK_Mode
is

   function To_Name (Value : String) return Name_Text
   is (Texts.Truncated (Value, Limits.Max_Name_Length));

   function To_Path (Value : String) return Path_Text
   is (Texts.Truncated (Value, Limits.Max_Path_Length));

   function To_Step (Value : String) return Step_Text
   is (Texts.Truncated (Value, Limits.Max_Step_Text_Length));

end Fabula.Frames;
