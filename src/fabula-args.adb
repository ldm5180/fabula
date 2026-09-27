with Fabula.Expand;

package body Fabula.Args
  with SPARK_Mode
is

   Two_Quotes : constant String := [1 .. 2 => '"'];

   --  A doc string's lines, numbered from First_Doc_Line, joined by one
   --  LF each.
   First_Doc_Line   : constant := 1;
   Separator_Length : constant := 1;

   --  The length of a joined doc string, and the characters written of
   --  one, before its first line.
   Nothing_Joined : constant := 0;

   function Make
     (Text     : String;
      Captures : Expressions.Capture_List;
      Attached : Attachments := No_Attachments) return List
   is ((Text     => Texts.Truncated (Text, Limits.Max_Line_Length),
        Captures => Captures,
        Attached => Attached));

   ---------------------------------------------------------------------
   --  Captures.
   ---------------------------------------------------------------------

   --  Capture N's text, or "" when its bounds do not lie in the text.
   function Captured (A : List; N : Arg_Index) return String
   with
     Pre  => N <= Count (A),
     Post => Captured'Result'Length <= Limits.Max_Line_Length
   is
      Cap : constant Expressions.Capture := A.Captures.Items (N);
   begin
      if Cap.Last > Texts.Length (A.Text) or else Cap.First > Cap.Last + 1 then
         return "";
      end if;
      return Texts.Value (A.Text) (Cap.First .. Cap.Last);
   end Captured;

   function Unquoted (A : List; N : Arg_Index) return String
   with
     Pre  => N <= Count (A),
     Post => Unquoted'Result'Length <= Limits.Max_Line_Length
   is
      Raw : constant String := Captured (A, N);
   begin
      if A.Captures.Items (N).Kind
         in Expressions.P_Word | Expressions.P_Anonymous
        and then Raw = Two_Quotes
      then
         return "";
      end if;
      return Raw;
   end Unquoted;

   function Int (A : List; N : Arg_Index) return Numbers.Integer_Reads.Read
   is (Numbers.Parse_Integer (Captured (A, N)));

   function Long (A : List; N : Arg_Index) return Numbers.Long_Reads.Read
   is (Numbers.Parse_Long (Captured (A, N)));

   function Real (A : List; N : Arg_Index) return Numbers.Real_Reads.Read
   is (Numbers.Parse_Real (Captured (A, N)));

   function Text (A : List; N : Arg_Index) return String
   is (Unquoted (A, N));

   function Word (A : List; N : Arg_Index) return String
   is (Unquoted (A, N));

   ---------------------------------------------------------------------
   --  The doc string and the table.
   ---------------------------------------------------------------------

   --  S's text, substituted when A is a step of an outline; "" when the
   --  expansion refused.
   function Resolved (A : List; S : Ast.Slice) return String
   is (Expand.Value_Or
         (Expand.Resolved
            (A.Attached.Doc.all,
             S,
             A.Attached.Header_Row,
             A.Attached.Data_Row),
          ""))
   with
     Pre  => A.Attached.Doc /= null,
     Post =>
       Resolved'Result'First = First_Column
       and then Resolved'Result'Length <= Limits.Max_Line_Length;

   function Doc_Type (A : List) return String
   is (Ast.Text (A.Attached.Doc.all, Doc_Node (A).Content_Type));

   function Doc_Line (A : List; N : Positive) return String
   is (Resolved
         (A,
          Ast.Doc_Line
            (A.Attached.Doc.all,
             Ast.Doc_Line_Pool.Nth (Doc_Node (A).Lines, N))));

   --  The longest doc string: every line at the line limit, plus an LF
   --  between each two.
   Max_Joined : constant :=
     Limits.Max_Doc_Lines * (Limits.Max_Line_Length + Separator_Length);

   --  Writes A's doc lines into Into, joined by LF, as far as Into holds;
   --  Doc_String sizes Into to hold them all.
   procedure Fill (A : List; Into : in out String)
   with
     Pre =>
       Has_Doc (A)
       and then Into'First = Positive'First
       and then Into'Length <= Max_Joined
   is
      Pos : Natural := Nothing_Joined;
   begin
      for N in First_Doc_Line .. Doc_Line_Count (A) loop
         pragma Loop_Invariant (Pos <= Into'Length);
         if N > First_Doc_Line then
            exit when Pos = Into'Length;
            Pos := Pos + Separator_Length;
            Into (Pos) := ASCII.LF;
         end if;
         declare
            Line : constant String := Doc_Line (A, N);
            Take : constant Natural :=
              Natural'Min (Line'Length, Into'Length - Pos);
         begin
            Into (Pos + 1 .. Pos + Take) := Line (1 .. Take);
            Pos := Pos + Take;
         end;
      end loop;
   end Fill;

   --  The length of A's doc lines joined by LF.
   function Joined_Length (A : List) return Natural
   with Pre => Has_Doc (A), Post => Joined_Length'Result <= Max_Joined
   is
      Total : Natural := Nothing_Joined;
   begin
      for N in First_Doc_Line .. Doc_Line_Count (A) loop
         pragma
           Loop_Invariant (Total <= (N - 1) * (Limits.Max_Line_Length + 1));
         if N > First_Doc_Line then
            Total := Total + Separator_Length;
         end if;
         Total := Total + Doc_Line (A, N)'Length;
      end loop;
      return Total;
   end Joined_Length;

   function Doc_String (A : List) return String is
      Total : constant Natural := Joined_Length (A);
   begin
      return Result : String (1 .. Total) := [others => ' '] do
         Fill (A, Result);
      end return;
   end Doc_String;

   function Cell (A : List; Row, Col : Positive) return String is
      Cells : constant Ast.Cell_Range := Row_At (A, Row).Cells;
   begin
      if Col > Ast.Cell_Pool.Width (Cells)
        or else Ast.Cell_Pool.Nth (Cells, Col)
                > Ast.Cell_Count (A.Attached.Doc.all)
      then
         return "";
      end if;
      return
        Resolved
          (A, Ast.Cell (A.Attached.Doc.all, Ast.Cell_Pool.Nth (Cells, Col)));
   end Cell;

   function Cell_Int
     (A : List; Row, Col : Positive) return Numbers.Integer_Reads.Read
   is (Numbers.Parse_Integer (Cell (A, Row, Col)));

   function Column_Of (A : List; Key : String) return Natural is
      function Is_Key (Col : Positive) return Boolean
      is (Has_Table (A)
          and then Col <= Col_Count (A)
          and then Cell (A, Key_Row, Col) = Key);

      function First_Key is new Searches.Find_First (Is_Key);
   begin
      return First_Key (Positive'First, Col_Count (A));
   end Column_Of;

   function Hash_Value (A : List; Row : Positive; Key : String) return String
   is (Cell (A, Key_Row + Row, Column_Of (A, Key)));

   function Pair_Row (A : List; Key : String) return Natural is
      function Is_Key (Row : Positive) return Boolean
      is (Has_Table (A)
          and then Row <= Row_Count (A)
          and then Key_Column <= Col_Count (A)
          and then Cell (A, Row, Key_Column) = Key);

      function First_Key is new Searches.Find_First (Is_Key);
   begin
      return First_Key (Positive'First, Row_Count (A));
   end Pair_Row;

   function Pair_Value (A : List; Key : String) return String
   is (Cell (A, Pair_Row (A, Key), Value_Column));

end Fabula.Args;
