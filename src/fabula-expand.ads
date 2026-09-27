--  Outline expansion over a parsed Document.  One Examples data row
--  turns an outline into a concrete scenario: its name, step text, doc
--  lines and table cells take the row's values for their <name>
--  placeholders.  Node ranges are stored values that no proof carries,
--  so every walk checks each index against its pool's count; a failed
--  check refuses, and never reads past the pool.
with Fabula.Ast;
with Fabula.Limits;
with Fabula.Texts;

package Fabula.Expand
  with SPARK_Mode
is

   use type Ast.Examples_Handle;
   use type Ast.Examples_Row_Handle;
   use type Ast.Scenario_Handle;
   use type Ast.Tag_Handle;

   subtype Text_Length is Natural range 0 .. Limits.Max_Line_Length;

   --  The count of placeholders that no header names, before any.
   Nothing_Unknown : constant Text_Length := 0;

   --  One expanded text.  Ok is False when the text would not fit in
   --  Max_Line_Length, or when a row handle or a stored range ran past
   --  its pool; like every sticky Ok, it stays False once set.  Unknown
   --  counts the placeholders that no header names; each stays as
   --  written.
   type Text_Result is record
      Ok      : Boolean := False;
      Text    : Texts.Line_Text;
      Unknown : Text_Length := Nothing_Unknown;
   end record;

   function Value (R : Text_Result) return String
   is (Texts.Value (R.Text))
   with
     Post =>
       Value'Result'First = Positive'First
       and then Value'Result'Length <= Limits.Max_Line_Length;

   --  The expanded text, or Default when the expansion refused.
   function Value_Or (R : Text_Result; Default : String) return String
   is (if R.Ok then Value (R) else Default);

   --  Each <name> whose name a header cell spells takes the data row's
   --  cell in that column, and an empty cell gives two double quotes.
   --  A placeholder runs from '<' to the first '>' before a line break.
   --  A substituted value is never scanned again.
   function Substituted
     (Doc        : Ast.Document;
      Text       : String;
      Header_Row : Ast.Examples_Row_Index;
      Data_Row   : Ast.Examples_Row_Index) return Text_Result
   with
     Pre =>
       Text'First = Positive'First
       and then Text'Length <= Limits.Text_Arena_Bytes;

   --  S's text, substituted when both row handles name a row, else a
   --  plain copy.  A plain scenario's step passes No_Examples_Row for
   --  both.
   function Resolved
     (Doc        : Ast.Document;
      S          : Ast.Slice;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Text_Result;

   --  True when the step's text, every doc line and every table cell
   --  resolve Ok; the runner refuses a concrete step that does not fit.
   function Step_Fits
     (Doc        : Ast.Document;
      Node       : Ast.Step_Node;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Boolean;

   ---------------------------------------------------------------------
   --  Concrete scenarios.  An outline's data rows, in file order, block
   --  by block; a block with no data row yields none.
   ---------------------------------------------------------------------

   --  Where a walk over an outline's data rows stands: a row is due,
   --  the walk ended after the last row, or it ended stale, at a stored
   --  range that ran past its pool.
   type Walk_Status is (Row_Due, Ended, Stale);

   --  Only a due row has a block and rows, so an ended walk cannot name
   --  one.  The defaults only complete the type's default value; every
   --  due row is built with its own three.
   type Example_Ref (Status : Walk_Status := Ended) is record
      case Status is
         when Row_Due =>
            Block      : Ast.Examples_Index := Ast.Examples_Index'First;
            Header_Row : Ast.Examples_Row_Index :=
              Ast.Examples_Row_Index'First;
            Data_Row   : Ast.Examples_Row_Index :=
              Ast.Examples_Row_Index'First;

         when Ended | Stale =>
            null;
      end case;
   end record;

   --  A walk with no row due: a plain scenario's, or one that ended.
   No_Example : constant Example_Ref := (Status => Ended);

   --  The due row's block and rows, or none when no row is due.
   function Block_Of (Ref : Example_Ref) return Ast.Examples_Handle
   is (if Ref.Status = Row_Due then Ref.Block else Ast.No_Examples);

   function Header_Row_Of (Ref : Example_Ref) return Ast.Examples_Row_Handle
   is (if Ref.Status = Row_Due then Ref.Header_Row else Ast.No_Examples_Row);

   function Data_Row_Of (Ref : Example_Ref) return Ast.Examples_Row_Handle
   is (if Ref.Status = Row_Due then Ref.Data_Row else Ast.No_Examples_Row);

   function Usable (Doc : Ast.Document; Ref : Example_Ref) return Boolean
   is (Ref.Status = Row_Due
       and then Ref.Block <= Ast.Examples_Count (Doc)
       and then Ref.Header_Row <= Ast.Examples_Row_Count (Doc)
       and then Ref.Data_Row <= Ast.Examples_Row_Count (Doc));

   function First_Example
     (Doc : Ast.Document; S : Ast.Scenario_Index) return Example_Ref
   with
     Pre  => S <= Ast.Scenario_Count (Doc),
     Post =>
       First_Example'Result.Status /= Row_Due
       or else Usable (Doc, First_Example'Result);

   --  The row after After; an ended or stale walk stays as it is.
   function Next_Example
     (Doc : Ast.Document; S : Ast.Scenario_Index; After : Example_Ref)
      return Example_Ref
   with
     Pre  => S <= Ast.Scenario_Count (Doc),
     Post =>
       (if After.Status /= Row_Due then Next_Example'Result = After)
       and then (Next_Example'Result.Status /= Row_Due
                 or else Usable (Doc, Next_Example'Result));

   --  The outline's name as the reference interpreter prints it for one
   --  concrete scenario: substituted from the data row.
   function Concrete_Name
     (Doc        : Ast.Document;
      S          : Ast.Scenario_Index;
      Header_Row : Ast.Examples_Row_Index;
      Data_Row   : Ast.Examples_Row_Index) return Text_Result
   with Pre => S <= Ast.Scenario_Count (Doc);

   --  A concrete scenario's line is its data row's; No_Line for a stale
   --  row.
   function Concrete_Line
     (Doc : Ast.Document; Data_Row : Ast.Examples_Row_Index)
      return Line_Number;

   ---------------------------------------------------------------------
   --  Effective tags: the scenario's own, then the Feature's, then its
   --  Examples block's, each kept once in first-seen order.  Items name
   --  tags in the Document's pool, so each keeps its leading '@'.
   ---------------------------------------------------------------------

   subtype Tag_Count is Natural range 0 .. Limits.Max_Tags;
   type Tag_Items is array (1 .. Limits.Max_Tags) of Ast.Tag_Index;

   No_Tags : constant Tag_Count := 0;

   --  Ok is False when a stored tag range ran past its pool.
   type Tag_Set is record
      Ok    : Boolean := True;
      Count : Tag_Count := No_Tags;
      Items : Tag_Items := [others => Ast.Tag_Index'First];
   end record;

   --  E is the concrete scenario's Examples block, or No_Examples for a
   --  plain scenario.
   function Effective_Tags
     (Doc : Ast.Document; S : Ast.Scenario_Index; E : Ast.Examples_Handle)
      return Tag_Set
   with
     Pre  => S <= Ast.Scenario_Count (Doc),
     Post =>
       (for all I in 1 .. Effective_Tags'Result.Count =>
          Effective_Tags'Result.Items (I) <= Ast.Tag_Count (Doc));

   --  Name is a tag with its '@'.  The runner's Has_Tag for Tags.Eval
   --  reads the current scenario's set through this.
   function Contains
     (Doc : Ast.Document; Set : Tag_Set; Name : String) return Boolean;

end Fabula.Expand;
