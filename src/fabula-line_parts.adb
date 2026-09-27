package body Fabula.Line_Parts
  with SPARK_Mode
is

   --  The first index in From .. To + 1 whose character is not
   --  White_Space; To + 1 when every one is.
   function First_Kept
     (Line : String; From : Positive; To : Natural) return Positive
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post => First_Kept'Result in From .. To + 1
   is
      First : Positive := From;
   begin
      while First <= To and then Line (First) in White_Space loop
         pragma Loop_Invariant (First in From .. To);
         pragma Loop_Variant (Increases => First);
         First := First + 1;
      end loop;
      return First;
   end First_Kept;

   --  The last index in First .. To whose character is not White_Space;
   --  First - 1 when every one is.
   function Last_Kept
     (Line : String; First : Positive; To : Natural) return Natural
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then First <= To + 1,
     Post => Last_Kept'Result in First - 1 .. To
   is
      Last : Natural := To;
   begin
      while Last >= First and then Line (Last) in White_Space loop
         pragma Loop_Invariant (Last in First .. To);
         pragma Loop_Variant (Decreases => Last);
         Last := Last - 1;
      end loop;
      return Last;
   end Last_Kept;

   function Trimmed (Line : String; From : Positive; To : Natural) return Span
   is
      First : constant Positive := First_Kept (Line, From, To);
   begin
      return (First => First, Last => Last_Kept (Line, First, To));
   end Trimmed;

   function Fence_Run
     (Line : String; From : Positive; To : Natural) return Natural
   is
      function Opens_Fence (I : Positive) return Boolean
      is (Is_Line (Line) and then Fence_At (Line, I));

      function First_Fence is new Searches.Find_First (Opens_Fence);
   begin
      return First_Fence (From, To - (Scan.Fence_Length - 1));
   end Fence_Run;

   --  The first index in From .. To + 1 whose character is not
   --  Space_Or_Tab; To + 1 when every one is.
   function Skip_Spaces
     (Line : String; From : Positive; To : Natural) return Positive
   with
     Pre  => Is_Line (Line) and then To <= Line'Last,
     Post =>
       Skip_Spaces'Result >= From
       and then (if From <= To then Skip_Spaces'Result <= To + 1)
   is
      First : Positive := From;
   begin
      while First <= To and then Line (First) in Space_Or_Tab loop
         pragma Loop_Invariant (First in From .. To);
         pragma Loop_Variant (Increases => First);
         First := First + 1;
      end loop;
      return First;
   end Skip_Spaces;

   --  The last index of the tag that starts at First: the run of tag
   --  characters after its mark, no further than To.
   function Tag_End
     (Line : String; First : Positive; To : Natural) return Positive
   with
     Pre  => Is_Line (Line) and then First <= To and then To <= Line'Last,
     Post => Tag_End'Result in First .. To
   is
      Last : Positive := First;
   begin
      while Last < To and then Line (Last + 1) in Tag_Char loop
         pragma Loop_Invariant (Last in First .. To - 1);
         pragma Loop_Variant (Increases => Last);
         Last := Last + 1;
      end loop;
      return Last;
   end Tag_End;

   function Next_Tag (Line : String; From : Positive; To : Natural) return Span
   is
      First : constant Positive := Skip_Spaces (Line, From, To);
   begin
      if First > To or else Line (First) /= Scan.Tag_Mark then
         return Empty_Span;
      end if;
      return (First => First, Last => Tag_End (Line, First, To));
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
      return (Text => Trimmed (Line, From, To), Stop => No_Position);
   end Next_Cell;

   function Measure_Row
     (Line : String; First : Positive; Last : Natural) return Row_Shape
   is
      Pos   : Positive := First + 1;
      Count : Line_Length := No_Cells;
      Next  : Cell;
   begin
      while Pos <= Last loop
         pragma Loop_Invariant (Pos in First + 1 .. Last);
         pragma Loop_Invariant (Count <= Pos - First - 1);
         pragma Loop_Variant (Increases => Pos);
         Next := Next_Cell (Line, Pos, Last);
         if Next.Stop = No_Position then
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
         if Line (I) = Scan.Header_Colon then
            return (First => From, Last => I - 1);
         end if;
      end loop;
      return (First => From, Last => Natural'Max (To, From - 1));
   end Keyword_Of;

end Fabula.Line_Parts;
