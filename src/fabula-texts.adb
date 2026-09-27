package body Fabula.Texts
  with SPARK_Mode
is

   --  Appends Piece, which fits.
   procedure Append_Whole (T : in out Bounded_Text; Piece : String)
   with
     Pre  => Piece'Length <= T.Capacity - T.Len,
     Post =>
       T.Len = T.Len'Old + Piece'Length
       and then Value (T) = Value (T'Old) & Piece
   is
   begin
      if Piece'Length > 0 then
         T.Data (T.Len + 1 .. T.Len + Piece'Length) := Piece;
         T.Len := T.Len + Piece'Length;
      end if;
   end Append_Whole;

   procedure Append_Truncated (T : in out Bounded_Text; Piece : String) is
      Kept : constant Natural :=
        Natural'Min (Piece'Length, T.Capacity - T.Len);
   begin
      Append_Whole (T, Prefix (Piece, Kept));
   end Append_Truncated;

   function Truncated
     (Source : String; Capacity : Positive) return Bounded_Text is
   begin
      return Result : Bounded_Text := Empty (Capacity) do
         Append_Truncated (Result, Source);
      end return;
   end Truncated;

   procedure Append
     (T : in out Bounded_Text; Piece : String; Ok : in out Boolean) is
   begin
      Ok := Ok and then Piece'Length <= T.Capacity - T.Len;
      if Ok then
         Append_Whole (T, Piece);
      end if;
   end Append;

end Fabula.Texts;
