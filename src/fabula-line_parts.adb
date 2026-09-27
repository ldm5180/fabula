package body Fabula.Line_Parts
  with SPARK_Mode
is

   function Trimmed (Line : String; From : Positive; To : Natural) return Span
   is
      First : Positive := From;
      Last  : Natural := To;
   begin
      while First <= Last and then Is_Blank (Line (First)) loop
         pragma Loop_Invariant (First in From .. Last);
         pragma Loop_Variant (Increases => First);
         First := First + 1;
      end loop;
      while Last >= First and then Is_Blank (Line (Last)) loop
         pragma Loop_Invariant (Last in First .. To);
         pragma Loop_Variant (Decreases => Last);
         Last := Last - 1;
      end loop;
      return (First => First, Last => Last);
   end Trimmed;

   function Fence_Run
     (Line : String; From : Positive; To : Natural) return Natural is
   begin
      for I in From .. To - (Scan.Fence_Length - 1) loop
         if Fence_At (Line, I) then
            return I;
         end if;
      end loop;
      return 0;
   end Fence_Run;

   function Next_Tag (Line : String; From : Positive; To : Natural) return Span
   is
      First : Positive := From;
      Last  : Natural;
   begin
      while First <= To and then Is_Space (Line (First)) loop
         pragma Loop_Invariant (First in From .. To);
         pragma Loop_Variant (Increases => First);
         First := First + 1;
      end loop;
      if First > To or else Line (First) /= Scan.Tag_Mark then
         return (First => 1, Last => 0);
      end if;
      Last := First;
      while Last < To and then Is_Tag_Char (Line (Last + 1)) loop
         pragma Loop_Invariant (Last in First .. To - 1);
         pragma Loop_Variant (Increases => Last);
         Last := Last + 1;
      end loop;
      return (First => First, Last => Last);
   end Next_Tag;

   function Next_Cell
     (Line : String; From : Positive; To : Natural) return Cell
   is
      Escaped : Boolean := False;
   begin
      for I in From .. To loop
         if Line (I) = Scan.Cell_Separator and then not Escaped then
            return (Text => Trimmed (Line, From, I - 1), Stop => I);
         end if;
         Escaped := Line (I) = Scan.Escape_Mark and then not Escaped;
      end loop;
      return (Text => Trimmed (Line, From, To), Stop => 0);
   end Next_Cell;

   function Measure_Row
     (Line : String; First : Positive; Last : Natural) return Row_Shape
   is
      Pos   : Positive := First + 1;
      Count : Natural := 0;
      Next  : Cell;
   begin
      while Pos <= Last loop
         pragma Loop_Invariant (Pos in First + 1 .. Last);
         pragma Loop_Invariant (Count <= Pos - First - 1);
         pragma Loop_Variant (Increases => Pos);
         Next := Next_Cell (Line, Pos, Last);
         if Next.Stop = 0 then
            return (Terminated => False, Cells => Count);
         end if;
         Count := Count + 1;
         Pos := Next.Stop + 1;
      end loop;
      return (Terminated => True, Cells => Count);
   end Measure_Row;

   function Keyword_Of
     (Line : String; From : Positive; To : Natural) return Span is
   begin
      for I in From .. To loop
         if Line (I) = ':' then
            return (First => From, Last => I - 1);
         end if;
      end loop;
      return (First => From, Last => Natural'Max (To, From - 1));
   end Keyword_Of;

end Fabula.Line_Parts;
