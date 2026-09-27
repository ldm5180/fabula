with Fabula.Searches;

package body Fabula.Expand
  with SPARK_Mode
is

   use type Ast.Cell_Handle;
   use type Ast.Doc_Handle;
   use type Ast.Doc_Line_Handle;
   use type Ast.Row_Handle;
   use type Ast.Table_Handle;

   Refused : constant Text_Result := (others => <>);

   Stale_Example : constant Example_Ref := (Status => Stale);

   Empty_Value : constant String := [1 .. 2 => '"'];

   Placeholder_Open  : constant Character := '<';
   Placeholder_Close : constant Character := '>';

   --  A placeholder's length counts its two brackets.
   Brackets_Length : constant := 2;

   --  Closing's answer when no placeholder opens, and Column_Of's when
   --  no header names the key.
   No_Close  : constant Natural := Searches.Not_Found;
   No_Column : constant Natural := Searches.Not_Found;

   --  Appends Piece, or refuses R when Piece would not fit.
   procedure Append (R : in out Text_Result; Piece : String)
   with
     Post => (if not R.Ok'Old then not R.Ok) and then R.Unknown = R.Unknown'Old
   is
   begin
      Texts.Append (R.Text, Piece, R.Ok);
   end Append;

   function Copied (Raw : String) return Text_Result is
      Result : Text_Result := (Ok => True, others => <>);
   begin
      Append (Result, Raw);
      return Result;
   end Copied;

   --  A cell range lies inside the cell pool, or is empty.
   function Cells_Inside
     (Doc : Ast.Document; R : Ast.Cell_Range) return Boolean
   is (Ast.Cell_Pool.Inside (R, Ast.Cell_Count (Doc)));

   --  The '>' closing a placeholder that opens at Text (From), or
   --  No_Close when Text (From) is not '<' or no '>' comes before a line
   --  break.
   function Closing (Text : String; From : Positive) return Natural
   with
     Pre  =>
       Text'First = Positive'First
       and then Text'Length <= Limits.Text_Arena_Bytes
       and then From in Text'Range,
     Post =>
       Closing'Result = No_Close
       or else Closing'Result in From + 1 .. Text'Last
   is
      function Ends_Placeholder (J : Positive) return Boolean
      is (J in Text'Range
          and then Text (J) in Placeholder_Close | ASCII.LF | ASCII.CR);

      function First_End is new Searches.Find_First (Ends_Placeholder);

      Stop : constant Natural :=
        (if Text (From) = Placeholder_Open
         then First_End (From + 1, Text'Last)
         else No_Close);
   begin
      return
        (if Stop /= No_Close and then Text (Stop) = Placeholder_Close
         then Stop
         else No_Close);
   end Closing;

   --  The 1-based column whose header cell spells Key, or No_Column.
   --  The first such column wins.
   function Column_Of
     (Doc : Ast.Document; Header : Ast.Row_Node; Key : String) return Natural
   with
     Pre  => Cells_Inside (Doc, Header.Cells),
     Post => Column_Of'Result <= Ast.Cell_Pool.Width (Header.Cells)
   is
      function Spells_Key (Column : Positive) return Boolean
      is (Column <= Ast.Cell_Pool.Width (Header.Cells)
          and then Cells_Inside (Doc, Header.Cells)
          and then Ast.Text
                     (Doc,
                      Ast.Cell (Doc, Ast.Cell_Pool.Nth (Header.Cells, Column)))
                   = Key);

      function First_Spelling is new Searches.Find_First (Spells_Key);
   begin
      return
        First_Spelling (Positive'First, Ast.Cell_Pool.Width (Header.Cells));
   end Column_Of;

   --  Appends the value for one placeholder, brackets included in
   --  Whole, or Whole itself when no header names its key.
   procedure Put_Value
     (Doc    : Ast.Document;
      R      : in out Text_Result;
      Whole  : String;
      Header : Ast.Row_Node;
      Data   : Ast.Row_Node)
   with
     Pre =>
       Whole'Length >= Brackets_Length
       and then Cells_Inside (Doc, Header.Cells)
       and then Cells_Inside (Doc, Data.Cells)
   is
      Col : constant Natural :=
        Column_Of (Doc, Header, Whole (Whole'First + 1 .. Whole'Last - 1));
   begin
      if Col = No_Column then
         Append (R, Whole);
         if R.Unknown < Text_Length'Last then
            R.Unknown := R.Unknown + 1;
         end if;
      elsif Col > Ast.Cell_Pool.Width (Data.Cells) then
         R.Ok := False;
      else
         declare
            Cell : constant Ast.Slice :=
              Ast.Cell (Doc, Ast.Cell_Pool.Nth (Data.Cells, Col));
         begin
            Append
              (R,
               (if Ast.Is_Empty (Cell)
                then Empty_Value
                else Ast.Text (Doc, Cell)));
         end;
      end if;
   end Put_Value;

   --  Copies Text into R left to right, each placeholder replaced.
   procedure Scan_Text
     (Doc    : Ast.Document;
      R      : in out Text_Result;
      Text   : String;
      Header : Ast.Row_Node;
      Data   : Ast.Row_Node)
   with
     Pre =>
       Text'First = Positive'First
       and then Text'Length <= Limits.Text_Arena_Bytes
       and then Cells_Inside (Doc, Header.Cells)
       and then Cells_Inside (Doc, Data.Cells)
   is
      I : Positive := Text'First;
   begin
      while I <= Text'Last and then R.Ok loop
         pragma Loop_Variant (Increases => I);
         declare
            Close : constant Natural := Closing (Text, I);
         begin
            if Close = No_Close then
               Append (R, Text (I .. I));
               I := I + 1;
            else
               Put_Value (Doc, R, Text (I .. Close), Header, Data);
               I := Close + 1;
            end if;
         end;
      end loop;
   end Scan_Text;

   function Substituted
     (Doc        : Ast.Document;
      Text       : String;
      Header_Row : Ast.Examples_Row_Index;
      Data_Row   : Ast.Examples_Row_Index) return Text_Result
   is
      Result : Text_Result := (Ok => True, others => <>);
   begin
      if Header_Row > Ast.Examples_Row_Count (Doc)
        or else Data_Row > Ast.Examples_Row_Count (Doc)
      then
         return Refused;
      end if;
      declare
         Header : constant Ast.Row_Node := Ast.Examples_Row (Doc, Header_Row);
         Data   : constant Ast.Row_Node := Ast.Examples_Row (Doc, Data_Row);
      begin
         if not Cells_Inside (Doc, Header.Cells)
           or else not Cells_Inside (Doc, Data.Cells)
         then
            return Refused;
         end if;
         Scan_Text (Doc, Result, Text, Header, Data);
      end;
      return (if Result.Ok then Result else Refused);
   end Substituted;

   function Resolved
     (Doc        : Ast.Document;
      S          : Ast.Slice;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Text_Result
   is
      Raw : constant String := Ast.Text (Doc, S);
   begin
      if Header_Row /= Ast.No_Examples_Row
        and then Data_Row /= Ast.No_Examples_Row
      then
         return Substituted (Doc, Raw, Header_Row, Data_Row);
      end if;
      return Copied (Raw);
   end Resolved;

   function Doc_Fits
     (Doc        : Ast.Document;
      Handle     : Ast.Doc_Index;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Boolean is
   begin
      if Handle > Ast.Doc_String_Count (Doc) then
         return False;
      end if;
      declare
         Lines : constant Ast.Doc_Line_Range :=
           Ast.Doc_String (Doc, Handle).Lines;
      begin
         for L in Lines.First .. Lines.Last loop
            if L > Ast.Doc_Line_Count (Doc)
              or else not Resolved
                            (Doc, Ast.Doc_Line (Doc, L), Header_Row, Data_Row)
                            .Ok
            then
               return False;
            end if;
         end loop;
      end;
      return True;
   end Doc_Fits;

   function Row_Fits
     (Doc        : Ast.Document;
      Row        : Ast.Row_Node;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Boolean is
   begin
      for C in Row.Cells.First .. Row.Cells.Last loop
         if C > Ast.Cell_Count (Doc)
           or else not Resolved (Doc, Ast.Cell (Doc, C), Header_Row, Data_Row)
                         .Ok
         then
            return False;
         end if;
      end loop;
      return True;
   end Row_Fits;

   function Table_Fits
     (Doc        : Ast.Document;
      Handle     : Ast.Table_Index;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Boolean is
   begin
      if Handle > Ast.Table_Count (Doc) then
         return False;
      end if;
      declare
         Rows : constant Ast.Row_Range := Ast.Table (Doc, Handle).Rows;
      begin
         for R in Rows.First .. Rows.Last loop
            if R > Ast.Table_Row_Count (Doc)
              or else not Row_Fits
                            (Doc, Ast.Table_Row (Doc, R), Header_Row, Data_Row)
            then
               return False;
            end if;
         end loop;
      end;
      return True;
   end Table_Fits;

   function Step_Fits
     (Doc        : Ast.Document;
      Node       : Ast.Step_Node;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Boolean is
   begin
      if not Resolved (Doc, Node.Text, Header_Row, Data_Row).Ok then
         return False;
      elsif Node.Doc /= Ast.No_Doc
        and then not Doc_Fits (Doc, Node.Doc, Header_Row, Data_Row)
      then
         return False;
      elsif Node.Table /= Ast.No_Table
        and then not Table_Fits (Doc, Node.Table, Header_Row, Data_Row)
      then
         return False;
      end if;
      return True;
   end Step_Fits;

   --  The first block in From .. Last with a data row.  A block past
   --  the pool, or rows past theirs, stops the walk as stale.
   function Scan_Blocks
     (Doc  : Ast.Document;
      From : Ast.Examples_Index;
      Last : Ast.Examples_Handle) return Example_Ref
   with
     Post =>
       Scan_Blocks'Result.Status /= Row_Due
       or else Usable (Doc, Scan_Blocks'Result)
   is
   begin
      for E in From .. Last loop
         if E > Ast.Examples_Count (Doc) then
            return Stale_Example;
         end if;
         declare
            B : constant Ast.Examples_Node := Ast.Examples (Doc, E);
         begin
            if B.Header_Row > Ast.Examples_Row_Count (Doc)
              or else not Ast.Examples_Row_Pool.Inside
                            (B.Rows, Ast.Examples_Row_Count (Doc))
            then
               return Stale_Example;
            elsif B.Header_Row /= Ast.No_Examples_Row
              and then not Ast.Examples_Row_Pool.Is_Empty (B.Rows)
            then
               return
                 (Status     => Row_Due,
                  Block      => E,
                  Header_Row => B.Header_Row,
                  Data_Row   => B.Rows.First);
            end if;
         end;
      end loop;
      return No_Example;
   end Scan_Blocks;

   function First_Example
     (Doc : Ast.Document; S : Ast.Scenario_Index) return Example_Ref
   is
      Blocks : constant Ast.Examples_Range := Ast.Scenario (Doc, S).Examples;
   begin
      if Ast.Examples_Pool.Is_Empty (Blocks) then
         return No_Example;
      end if;
      return Scan_Blocks (Doc, Blocks.First, Blocks.Last);
   end First_Example;

   --  The row after After in After's own block: Ended after that
   --  block's last row, Stale when the block's stored rows run past
   --  their pool.
   function Next_Row_In_Block
     (Doc : Ast.Document; After : Example_Ref) return Example_Ref
   is (declare
         B : constant Ast.Examples_Node := Ast.Examples (Doc, After.Block);
       begin
         (if After.Data_Row >= B.Rows.Last
          then No_Example
          elsif B.Rows.Last > Ast.Examples_Row_Count (Doc)
            or else not Ast.Examples_Row_Pool.Is_Live
                          (B.Header_Row, Ast.Examples_Row_Count (Doc))
          then Stale_Example
          else
            (Status     => Row_Due,
             Block      => After.Block,
             Header_Row => B.Header_Row,
             Data_Row   => After.Data_Row + 1)))
   with
     Pre  =>
       After.Status = Row_Due and then After.Block <= Ast.Examples_Count (Doc),
     Post =>
       Next_Row_In_Block'Result.Status /= Row_Due
       or else Usable (Doc, Next_Row_In_Block'Result);

   function Next_Example
     (Doc : Ast.Document; S : Ast.Scenario_Index; After : Example_Ref)
      return Example_Ref
   is
      Blocks : constant Ast.Examples_Range := Ast.Scenario (Doc, S).Examples;
   begin
      if After.Status /= Row_Due or else After.Block > Ast.Examples_Count (Doc)
      then
         return (if After.Status = Row_Due then Stale_Example else After);
      end if;
      declare
         In_Block : constant Example_Ref := Next_Row_In_Block (Doc, After);
      begin
         return
           (if In_Block.Status /= Ended
            then In_Block
            elsif After.Block >= Blocks.Last
            then No_Example
            else Scan_Blocks (Doc, After.Block + 1, Blocks.Last));
      end;
   end Next_Example;

   function Concrete_Name
     (Doc        : Ast.Document;
      S          : Ast.Scenario_Index;
      Header_Row : Ast.Examples_Row_Index;
      Data_Row   : Ast.Examples_Row_Index) return Text_Result
   is (Substituted
         (Doc,
          Ast.Text (Doc, Ast.Scenario (Doc, S).Head.Name),
          Header_Row,
          Data_Row));

   function Concrete_Line
     (Doc : Ast.Document; Data_Row : Ast.Examples_Row_Index) return Line_Number
   is (if Data_Row <= Ast.Examples_Row_Count (Doc)
       then Ast.Examples_Row (Doc, Data_Row).Line
       else No_Line);

   function Contains
     (Doc : Ast.Document; Set : Tag_Set; Name : String) return Boolean is
   begin
      for I in 1 .. Set.Count loop
         if Set.Items (I) <= Ast.Tag_Count (Doc)
           and then Ast.Text (Doc, Ast.Tag (Doc, Set.Items (I))) = Name
         then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Items_Inside (Doc : Ast.Document; Set : Tag_Set) return Boolean
   is (for all I in 1 .. Set.Count => Set.Items (I) <= Ast.Tag_Count (Doc));

   --  Adds each tag of R that Set does not already hold, in order.
   procedure Add_Range
     (Doc : Ast.Document; Set : in out Tag_Set; R : Ast.Tag_Range)
   with Pre => Items_Inside (Doc, Set), Post => Items_Inside (Doc, Set)
   is
   begin
      for T in R.First .. R.Last loop
         pragma Loop_Invariant (Items_Inside (Doc, Set));
         if T > Ast.Tag_Count (Doc) then
            Set.Ok := False;
            return;
         elsif not Contains (Doc, Set, Ast.Text (Doc, Ast.Tag (Doc, T))) then
            if Set.Count = Tag_Count'Last then
               Set.Ok := False;
               return;
            end if;
            Set.Count := Set.Count + 1;
            Set.Items (Set.Count) := T;
         end if;
      end loop;
   end Add_Range;

   function Effective_Tags
     (Doc : Ast.Document; S : Ast.Scenario_Index; E : Ast.Examples_Handle)
      return Tag_Set
   is
      Result : Tag_Set;
   begin
      Add_Range (Doc, Result, Ast.Scenario (Doc, S).Tags);
      Add_Range (Doc, Result, Ast.Feature (Doc).Tags);
      if E > Ast.Examples_Count (Doc) then
         Result.Ok := False;
      elsif E /= Ast.No_Examples then
         Add_Range (Doc, Result, Ast.Examples (Doc, E).Tags);
      end if;
      return Result;
   end Effective_Tags;

end Fabula.Expand;
