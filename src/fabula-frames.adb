package body Fabula.Frames
  with SPARK_Mode
is

   procedure Set (T : out Name_Text; Value : String) is
   begin
      T.Data := [others => ' '];
      T.Len := 0;
      for J in Value'Range loop
         exit when T.Len = Limits.Max_Name_Length;
         T.Len := T.Len + 1;
         T.Data (T.Len) := Value (J);
      end loop;
   end Set;

   function Value (T : Name_Text) return String
   is (T.Data (1 .. T.Len));

   procedure Set (T : out Path_Text; Value : String) is
   begin
      T.Data := [others => ' '];
      T.Len := 0;
      for J in Value'Range loop
         exit when T.Len = Limits.Max_Path_Length;
         T.Len := T.Len + 1;
         T.Data (T.Len) := Value (J);
      end loop;
   end Set;

   function Value (T : Path_Text) return String
   is (T.Data (1 .. T.Len));

   procedure Set (T : out Step_Text; Value : String) is
   begin
      T.Data := [others => ' '];
      T.Len := 0;
      for J in Value'Range loop
         exit when T.Len = Limits.Max_Step_Text_Length;
         T.Len := T.Len + 1;
         T.Data (T.Len) := Value (J);
      end loop;
   end Set;

   function Value (T : Step_Text) return String
   is (T.Data (1 .. T.Len));

end Fabula.Frames;
