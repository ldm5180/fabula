with Fabula.Expand;

package body Fabula.Args
  with SPARK_Mode
is

   Two_Quotes : constant String := [1 .. 2 => '"'];

   function Make
     (Text : String; Captures : Expressions.Capture_List) return List
   is
      Result : List;
   begin
      Result.Text (1 .. Text'Length) := Text;
      Result.Len := Text'Length;
      Result.Captures := Captures;
      return Result;
   end Make;

   procedure Attach
     (A          : in out List;
      Doc        : Document_Access;
      Doc_String : Ast.Doc_Handle;
      Table      : Ast.Table_Handle) is
   begin
      A.Doc := Doc;
      A.Doc_String := Doc_String;
      A.Table := Table;
   end Attach;

   procedure Set_Example
     (A : in out List; Header_Row, Data_Row : Ast.Examples_Row_Index) is
   begin
      A.Header_Row := Header_Row;
      A.Data_Row := Data_Row;
   end Set_Example;

   ---------------------------------------------------------------------
   --  Captures.
   ---------------------------------------------------------------------

   --  Capture N's text, or "" when its bounds do not lie in the text.
   function Captured (A : List; N : Positive) return String
   with
     Pre  => N <= Count (A),
     Post => Captured'Result'Length <= Limits.Max_Line_Length
   is
      Cap : constant Expressions.Capture := A.Captures.Items (N);
   begin
      if Cap.Last > A.Len or else Cap.First > Cap.Last + 1 then
         return "";
      end if;
      return A.Text (Cap.First .. Cap.Last);
   end Captured;

   function Unquoted (A : List; N : Positive) return String
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

   function Int (A : List; N : Positive) return Numbers.Integer_Reads.Read
   is (Numbers.Parse_Integer (Captured (A, N)));

   function Long (A : List; N : Positive) return Numbers.Long_Reads.Read
   is (Numbers.Parse_Long (Captured (A, N)));

   function Real (A : List; N : Positive) return Numbers.Real_Reads.Read
   is (Numbers.Parse_Real (Captured (A, N)));

   function Text (A : List; N : Positive) return String
   is (Unquoted (A, N));

   function Word (A : List; N : Positive) return String
   is (Unquoted (A, N));

   ---------------------------------------------------------------------
   --  The doc string and the table.
   ---------------------------------------------------------------------

   --  S's text, substituted when A is a step of an outline; "" when the
   --  expansion refused.
   function Resolved (A : List; S : Ast.Slice) return String
   with
     Pre  => A.Doc /= null,
     Post =>
       Resolved'Result'First = 1
       and then Resolved'Result'Length <= Limits.Max_Line_Length
   is
      R : constant Expand.Text_Result :=
        Expand.Resolved (A.Doc.all, S, A.Header_Row, A.Data_Row);
   begin
      if not R.Ok then
         return "";
      end if;
      return Expand.Value (R);
   end Resolved;

   function Doc_Type (A : List) return String
   is (Ast.Text (A.Doc.all, Doc_Node (A).Content_Type));

   function Doc_Line (A : List; N : Positive) return String
   is (Resolved
         (A,
          Ast.Doc_Line
            (A.Doc.all,
             Ast.Doc_Line_Index
               (Natural (Doc_Node (A).Lines.First) + N - 1))));

   --  The longest doc string: every line at the line limit, plus an LF
   --  between each two.
   Max_Joined : constant :=
     Limits.Max_Doc_Lines * (Limits.Max_Line_Length + 1);

   --  Writes A's doc lines into Into, joined by LF, as far as Into holds;
   --  Doc_String sizes Into to hold them all.
   procedure Fill (A : List; Into : in out String)
   with
     Pre =>
       Has_Doc (A) and then Into'First = 1 and then Into'Length <= Max_Joined
   is
      Pos : Natural := 0;
   begin
      for N in 1 .. Doc_Line_Count (A) loop
         pragma Loop_Invariant (Pos <= Into'Length);
         if N > 1 then
            exit when Pos = Into'Length;
            Pos := Pos + 1;
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
      Total : Natural := 0;
   begin
      for N in 1 .. Doc_Line_Count (A) loop
         pragma
           Loop_Invariant (Total <= (N - 1) * (Limits.Max_Line_Length + 1));
         Total := Total + Doc_Line (A, N)'Length + (if N > 1 then 1 else 0);
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
      Pos   : constant Natural := Natural (Cells.First) + Col - 1;
   begin
      if Pos > Natural (Cells.Last)
        or else Pos > Natural (Ast.Cell_Count (A.Doc.all))
      then
         return "";
      end if;
      return Resolved (A, Ast.Cell (A.Doc.all, Ast.Cell_Index (Pos)));
   end Cell;

   function Cell_Int
     (A : List; Row, Col : Positive) return Numbers.Integer_Reads.Read
   is (Numbers.Parse_Integer (Cell (A, Row, Col)));

   function Column_Of (A : List; Key : String) return Natural is
   begin
      for C in 1 .. Col_Count (A) loop
         if Cell (A, 1, C) = Key then
            return C;
         end if;
      end loop;
      return 0;
   end Column_Of;

   function Hash_Value (A : List; Row : Positive; Key : String) return String
   is (Cell (A, Row + 1, Column_Of (A, Key)));

   function Pair_Row (A : List; Key : String) return Natural is
   begin
      for R in 1 .. Row_Count (A) loop
         if Cell (A, R, 1) = Key then
            return R;
         end if;
      end loop;
      return 0;
   end Pair_Row;

   function Pair_Value (A : List; Key : String) return String
   is (Cell (A, Pair_Row (A, Key), 2));

end Fabula.Args;
