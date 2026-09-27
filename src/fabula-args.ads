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

private with Fabula.Searches;
private with Fabula.Texts;

package Fabula.Args
  with SPARK_Mode
is

   --  The shell makes this reference to its Document outside the proof:
   --  SPARK takes 'Access into an access-to-constant type only of a
   --  constant, and the shell's Document is a variable it refills for
   --  each feature file.  A List must not be read after that refill.
   type Document_Access is access constant Ast.Document;

   type List is private;

   --  How many captures a step can hold, and a capture's number.
   subtype Arg_Count is Expressions.Capture_Count;
   subtype Arg_Index is Positive range 1 .. Limits.Max_Args_Per_Step;

   --  The table layouts the readers below know by position: hashes keep
   --  their keys in the first row, and rows_hash is a table of
   --  Pair_Columns columns, the keys in Key_Column and the values in
   --  Value_Column.
   Key_Row      : constant := 1;
   Key_Column   : constant := 1;
   Value_Column : constant := 2;
   Pair_Columns : constant := 2;

   function Count (A : List) return Arg_Count;

   function Has_Doc (A : List) return Boolean;
   function Has_Table (A : List) return Boolean;

   ---------------------------------------------------------------------
   --  Assembly, by the runner.
   ---------------------------------------------------------------------

   --  What a step carries besides its text: its doc string and table in
   --  Doc (No_Doc and No_Table for none), and, for a step of an
   --  outline, the Examples rows its doc lines and cells then read
   --  substituted from (No_Examples_Row for a plain step).
   type Attachments is record
      Doc        : Document_Access;
      Doc_String : Ast.Doc_Handle := Ast.No_Doc;
      Table      : Ast.Table_Handle := Ast.No_Table;
      Header_Row : Ast.Examples_Row_Handle := Ast.No_Examples_Row;
      Data_Row   : Ast.Examples_Row_Handle := Ast.No_Examples_Row;
   end record;

   No_Attachments : constant Attachments := (others => <>);

   --  Text is the step text, as expanded, that Captures slice.
   function Make
     (Text     : String;
      Captures : Expressions.Capture_List;
      Attached : Attachments := No_Attachments) return List
   with
     Pre  =>
       Text'First = First_Column
       and then Text'Length <= Limits.Max_Line_Length,
     Post =>
       Count (Make'Result) = Captures.Count
       and then (if Attached.Doc = null
                 then
                   not Has_Doc (Make'Result)
                   and then not Has_Table (Make'Result));

   ---------------------------------------------------------------------
   --  Captures.  The numeric readers return a Fabula.Numbers result,
   --  which says why when the capture's text is not a number of the
   --  type.  Text and Word read a {word} or {} capture of exactly two
   --  double quotes -- what an empty Examples value substitutes to --
   --  as "".
   ---------------------------------------------------------------------

   function Int (A : List; N : Arg_Index) return Numbers.Integer_Reads.Read
   with Pre => N <= Count (A);

   function Long (A : List; N : Arg_Index) return Numbers.Long_Reads.Read
   with Pre => N <= Count (A);

   function Real (A : List; N : Arg_Index) return Numbers.Real_Reads.Read
   with Pre => N <= Count (A);

   function Text (A : List; N : Arg_Index) return String
   with
     Pre  => N <= Count (A),
     Post => Text'Result'Length <= Limits.Max_Line_Length;

   function Word (A : List; N : Arg_Index) return String
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
       Doc_Line'Result'First = First_Column
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
       Cell'Result'First = First_Column
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
   with Pre => Has_Table (A) and then Col_Count (A) = Pair_Columns;

   --  The first row whose key is Key wins.
   function Pair_Value (A : List; Key : String) return String
   with
     Pre =>
       Has_Table (A)
       and then Col_Count (A) = Pair_Columns
       and then Has_Pair (A, Key);

private

   use type Ast.Cell_Handle;

   --  Text is the matched text, which the captures slice.
   type List is record
      Text     : Texts.Line_Text;
      Captures : Expressions.Capture_List;
      Attached : Attachments;
   end record;

   function Count (A : List) return Arg_Count
   is (A.Captures.Count);

   function Has_Doc (A : List) return Boolean
   is (A.Attached.Doc /= null
       and then Ast.Doc_Pool.Is_Live
                  (A.Attached.Doc_String,
                   Ast.Doc_String_Count (A.Attached.Doc.all)));

   function Has_Table (A : List) return Boolean
   is (A.Attached.Doc /= null
       and then Ast.Table_Pool.Is_Live
                  (A.Attached.Table, Ast.Table_Count (A.Attached.Doc.all)));

   function Doc_Node (A : List) return Ast.Doc_String_Node
   is (Ast.Doc_String (A.Attached.Doc.all, A.Attached.Doc_String))
   with Pre => Has_Doc (A);

   function Doc_Line_Count (A : List) return Natural
   is (Ast.Doc_Line_Pool.Span
         (Doc_Node (A).Lines, Ast.Doc_Line_Count (A.Attached.Doc.all)));

   function Table_Rows (A : List) return Ast.Row_Range
   is (Ast.Table (A.Attached.Doc.all, A.Attached.Table).Rows)
   with Pre => Has_Table (A);

   function Row_Count (A : List) return Natural
   is (Ast.Row_Pool.Span
         (Table_Rows (A), Ast.Table_Row_Count (A.Attached.Doc.all)));

   --  Table row R, counted from 1.
   function Row_At (A : List; R : Positive) return Ast.Row_Node
   is (Ast.Table_Row
         (A.Attached.Doc.all, Ast.Row_Pool.Nth (Table_Rows (A), R)))
   with Pre => Has_Table (A) and then R <= Row_Count (A);

   --  The first row's width; the parser refuses a ragged table.
   function Col_Count (A : List) return Natural
   is (if Row_Count (A) = Ast.Row_Pool.No_Members
       then Ast.Cell_Pool.No_Members
       else
         Ast.Cell_Pool.Span
           (Row_At (A, Key_Row).Cells, Ast.Cell_Count (A.Attached.Doc.all)));

   --  The first column whose key (row Key_Row) is Key, or
   --  Searches.Not_Found.
   function Column_Of (A : List; Key : String) return Natural
   with Pre => Has_Table (A), Post => Column_Of'Result <= Col_Count (A);

   function Has_Column (A : List; Key : String) return Boolean
   is (Column_Of (A, Key) /= Searches.Not_Found);

   --  The first row whose Key_Column is Key, or Searches.Not_Found.
   function Pair_Row (A : List; Key : String) return Natural
   with
     Pre  => Has_Table (A) and then Col_Count (A) = Pair_Columns,
     Post => Pair_Row'Result <= Row_Count (A);

   function Has_Pair (A : List; Key : String) return Boolean
   is (Pair_Row (A, Key) /= Searches.Not_Found);

end Fabula.Args;
