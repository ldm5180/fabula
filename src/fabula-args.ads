--  Typed access to one matched step's arguments: its captures, its doc
--  string and its data table.  Captures are slices of the List's own
--  copy of the matched text.  The doc string and the table are read
--  from the Document through a reference, and substituted from the
--  Examples row when the step belongs to an outline.  Every reader is
--  1-based, left to right.
with Fabula.Ast;
with Fabula.Expressions;
with Fabula.Limits;
with Fabula.Numbers;

package Fabula.Args
  with SPARK_Mode
is

   --  The shell makes this reference to its Document outside the proof:
   --  SPARK takes 'Access into an access-to-constant type only of a
   --  constant, and the shell's Document is a variable it refills for
   --  each feature file.  A List must not be read after that refill.
   type Document_Access is access constant Ast.Document;

   type List is private;

   function Count (A : List) return Natural
   with Post => Count'Result <= Limits.Max_Args_Per_Step;

   function Has_Doc (A : List) return Boolean;
   function Has_Table (A : List) return Boolean;

   ---------------------------------------------------------------------
   --  Assembly, by the runner.
   ---------------------------------------------------------------------

   --  Text is the step text, as expanded, that Captures slice.
   function Make
     (Text : String; Captures : Expressions.Capture_List) return List
   with
     Pre  => Text'First = 1 and then Text'Length <= Limits.Max_Line_Length,
     Post =>
       Count (Make'Result) = Captures.Count
       and then not Has_Doc (Make'Result)
       and then not Has_Table (Make'Result);

   --  Gives A the step's doc string and table; handle 0 is "none".
   procedure Attach
     (A          : in out List;
      Doc        : Document_Access;
      Doc_String : Ast.Doc_Handle;
      Table      : Ast.Table_Handle)
   with Post => Count (A) = Count (A)'Old;

   --  Makes A one concrete step of an outline: its doc lines and cells
   --  then read substituted from this Examples row.
   procedure Set_Example
     (A : in out List; Header_Row, Data_Row : Ast.Examples_Row_Index)
   with Post => Count (A) = Count (A)'Old;

   ---------------------------------------------------------------------
   --  Captures.  The numeric readers return a Fabula.Numbers result,
   --  which says why when the capture's text is not a number of the
   --  type.  Text and Word read a {word} or {} capture of exactly two
   --  double quotes -- what an empty Examples value substitutes to --
   --  as "".
   ---------------------------------------------------------------------

   function Int (A : List; N : Positive) return Numbers.Integer_Reads.Read
   with Pre => N <= Count (A);

   function Long (A : List; N : Positive) return Numbers.Long_Reads.Read
   with Pre => N <= Count (A);

   function Real (A : List; N : Positive) return Numbers.Real_Reads.Read
   with Pre => N <= Count (A);

   function Text (A : List; N : Positive) return String
   with
     Pre  => N <= Count (A),
     Post => Text'Result'Length <= Limits.Max_Line_Length;

   function Word (A : List; N : Positive) return String
   with
     Pre  => N <= Count (A),
     Post => Word'Result'Length <= Limits.Max_Line_Length;

   ---------------------------------------------------------------------
   --  The doc string.  A line whose expansion would not fit in
   --  Max_Line_Length reads as ""; the runner checks Expand.Step_Fits
   --  before it runs a concrete step.
   ---------------------------------------------------------------------

   function Doc_String (A : List) return String
   with Pre => Has_Doc (A);
   --  The lines joined by LF, with no final LF.

   function Doc_Type (A : List) return String
   with Pre => Has_Doc (A);

   function Doc_Line_Count (A : List) return Natural
   with Pre => Has_Doc (A);

   function Doc_Line (A : List; N : Positive) return String
   with
     Pre  => Has_Doc (A) and then N <= Doc_Line_Count (A),
     Post =>
       Doc_Line'Result'First = 1
       and then Doc_Line'Result'Length <= Limits.Max_Line_Length;

   ---------------------------------------------------------------------
   --  The data table: raw rows, hashes (the first row holds the keys),
   --  and rows_hash (a two-column table of key, value rows).  A cell
   --  whose expansion would not fit reads as "".
   ---------------------------------------------------------------------

   function Row_Count (A : List) return Natural
   with Pre => Has_Table (A);

   function Col_Count (A : List) return Natural
   with Pre => Has_Table (A);

   function Cell (A : List; Row, Col : Positive) return String
   with
     Pre  =>
       Has_Table (A)
       and then Row <= Row_Count (A)
       and then Col <= Col_Count (A),
     Post =>
       Cell'Result'First = 1
       and then Cell'Result'Length <= Limits.Max_Line_Length;

   function Cell_Int
     (A : List; Row, Col : Positive) return Numbers.Integer_Reads.Read
   with
     Pre =>
       Has_Table (A)
       and then Row <= Row_Count (A)
       and then Col <= Col_Count (A);

   function Has_Column (A : List; Key : String) return Boolean
   with Pre => Has_Table (A);

   --  Row 1 is the first data row, the row after the keys.  The first
   --  column whose key is Key wins.
   function Hash_Value (A : List; Row : Positive; Key : String) return String
   with
     Pre =>
       Has_Table (A) and then Row < Row_Count (A) and then Has_Column (A, Key);

   function Has_Pair (A : List; Key : String) return Boolean
   with Pre => Has_Table (A) and then Col_Count (A) = 2;

   --  Column 1 holds the keys, column 2 the values; the first row
   --  whose key is Key wins.
   function Pair_Value (A : List; Key : String) return String
   with
     Pre =>
       Has_Table (A) and then Col_Count (A) = 2 and then Has_Pair (A, Key);

private

   use type Ast.Cell_Handle;
   use type Ast.Doc_Line_Handle;
   use type Ast.Row_Handle;

   subtype Text_Length is Natural range 0 .. Limits.Max_Line_Length;

   --  Text (1 .. Len) is the matched text.  Header_Row and Data_Row
   --  are 0 for a step of a plain scenario.
   type List is record
      Text       : String (1 .. Limits.Max_Line_Length) := [others => ' '];
      Len        : Text_Length := 0;
      Captures   : Expressions.Capture_List;
      Doc        : Document_Access;
      Doc_String : Ast.Doc_Handle := 0;
      Table      : Ast.Table_Handle := 0;
      Header_Row : Ast.Examples_Row_Handle := 0;
      Data_Row   : Ast.Examples_Row_Handle := 0;
   end record;

   function Count (A : List) return Natural
   is (A.Captures.Count);

   function Has_Doc (A : List) return Boolean
   is (A.Doc /= null
       and then A.Doc_String in 1 .. Ast.Doc_String_Count (A.Doc.all));

   function Has_Table (A : List) return Boolean
   is (A.Doc /= null and then A.Table in 1 .. Ast.Table_Count (A.Doc.all));

   --  How many members a stored range holds when it lies inside a pool
   --  of Used members; 0 when it is empty or runs past the pool.
   function Span
     (R : Ast.Doc_Line_Range; Used : Ast.Doc_Line_Handle) return Natural
   is (if R.Last < R.First or else R.Last > Used
       then 0
       else Natural (R.Last - R.First) + 1);

   function Span (R : Ast.Row_Range; Used : Ast.Row_Handle) return Natural
   is (if R.Last < R.First or else R.Last > Used
       then 0
       else Natural (R.Last - R.First) + 1);

   function Span (R : Ast.Cell_Range; Used : Ast.Cell_Handle) return Natural
   is (if R.Last < R.First or else R.Last > Used
       then 0
       else Natural (R.Last - R.First) + 1);

   function Doc_Node (A : List) return Ast.Doc_String_Node
   is (Ast.Doc_String (A.Doc.all, A.Doc_String))
   with Pre => Has_Doc (A);

   function Doc_Line_Count (A : List) return Natural
   is (Span (Doc_Node (A).Lines, Ast.Doc_Line_Count (A.Doc.all)));

   function Table_Rows (A : List) return Ast.Row_Range
   is (Ast.Table (A.Doc.all, A.Table).Rows)
   with Pre => Has_Table (A);

   function Row_Count (A : List) return Natural
   is (Span (Table_Rows (A), Ast.Table_Row_Count (A.Doc.all)));

   --  Table row R, counted from 1.
   function Row_At (A : List; R : Positive) return Ast.Row_Node
   is (Ast.Table_Row
         (A.Doc.all, Ast.Row_Index (Natural (Table_Rows (A).First) + R - 1)))
   with Pre => Has_Table (A) and then R <= Row_Count (A);

   --  The first row's width; the parser refuses a ragged table.
   function Col_Count (A : List) return Natural
   is (if Row_Count (A) = 0
       then 0
       else Span (Row_At (A, 1).Cells, Ast.Cell_Count (A.Doc.all)));

   --  The first column whose key (row 1) is Key, or 0.
   function Column_Of (A : List; Key : String) return Natural
   with Pre => Has_Table (A), Post => Column_Of'Result <= Col_Count (A);

   function Has_Column (A : List; Key : String) return Boolean
   is (Column_Of (A, Key) /= 0);

   --  The first row whose column 1 is Key, or 0.
   function Pair_Row (A : List; Key : String) return Natural
   with
     Pre  => Has_Table (A) and then Col_Count (A) = 2,
     Post => Pair_Row'Result <= Row_Count (A);

   function Has_Pair (A : List; Key : String) return Boolean
   is (Pair_Row (A, Key) /= 0);

end Fabula.Args;
