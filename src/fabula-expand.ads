--  Outline expansion over a parsed Document.  One Examples data row
--  turns an outline into a concrete scenario: its name, step text, doc
--  lines and table cells take the row's values for their <name>
--  placeholders.  Node ranges are stored values that no proof carries,
--  so every walk checks each index against its pool's count; a failed
--  check refuses, and never reads past the pool.
with Fabula.Ast;
with Fabula.Limits;

package Fabula.Expand
  with SPARK_Mode
is

   use type Ast.Examples_Handle;
   use type Ast.Examples_Row_Handle;
   use type Ast.Scenario_Handle;
   use type Ast.Tag_Handle;

   subtype Text_Length is Natural range 0 .. Limits.Max_Line_Length;

   --  One expanded text.  Ok is False when the text would not fit in
   --  Max_Line_Length, or when a row handle or a stored range ran past
   --  its pool.  Unknown counts the placeholders that no header names;
   --  each stays as written.
   type Text_Result is record
      Ok      : Boolean := False;
      Len     : Text_Length := 0;
      Val     : String (1 .. Limits.Max_Line_Length) := [others => ' '];
      Unknown : Text_Length := 0;
   end record;

   function Value (R : Text_Result) return String
   is (R.Val (1 .. R.Len));

   --  Each <name> whose name a header cell spells takes the data row's
   --  cell in that column, and an empty cell gives two double quotes.
   --  A placeholder runs from '<' to the first '>' before a line break.
   --  A substituted value is never scanned again.
   function Substituted
     (Doc        : Ast.Document;
      Text       : String;
      Header_Row : Ast.Examples_Row_Index;
      Data_Row   : Ast.Examples_Row_Index) return Text_Result
   with Pre => Text'First = 1 and then Text'Length <= Limits.Text_Arena_Bytes;

   --  S's text, substituted when both row handles are non-zero, else a
   --  plain copy.  A plain scenario's step passes 0 for both.
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

   --  Block 0 ends the walk; Stale says it ended at a stored range that
   --  ran past its pool rather than at the last row.
   type Example_Ref is record
      Block      : Ast.Examples_Handle := 0;
      Header_Row : Ast.Examples_Row_Handle := 0;
      Data_Row   : Ast.Examples_Row_Handle := 0;
      Stale      : Boolean := False;
   end record;

   function Usable (Doc : Ast.Document; Ref : Example_Ref) return Boolean
   is (Ref.Block in 1 .. Ast.Examples_Count (Doc)
       and then Ref.Header_Row in 1 .. Ast.Examples_Row_Count (Doc)
       and then Ref.Data_Row in 1 .. Ast.Examples_Row_Count (Doc));

   function First_Example
     (Doc : Ast.Document; S : Ast.Scenario_Index) return Example_Ref
   with
     Pre  => S <= Ast.Scenario_Count (Doc),
     Post =>
       First_Example'Result.Block = 0
       or else Usable (Doc, First_Example'Result);

   function Next_Example
     (Doc : Ast.Document; S : Ast.Scenario_Index; After : Example_Ref)
      return Example_Ref
   with
     Pre  => S <= Ast.Scenario_Count (Doc),
     Post =>
       Next_Example'Result.Block = 0 or else Usable (Doc, Next_Example'Result);

   --  The outline's name as the reference interpreter prints it for one
   --  concrete scenario: substituted from the data row.
   function Concrete_Name
     (Doc        : Ast.Document;
      S          : Ast.Scenario_Index;
      Header_Row : Ast.Examples_Row_Index;
      Data_Row   : Ast.Examples_Row_Index) return Text_Result
   with Pre => S <= Ast.Scenario_Count (Doc);

   --  A concrete scenario's line is its data row's; 0 for a stale row.
   function Concrete_Line
     (Doc : Ast.Document; Data_Row : Ast.Examples_Row_Index) return Natural;

   ---------------------------------------------------------------------
   --  Effective tags: the scenario's own, then the Feature's, then its
   --  Examples block's, each kept once in first-seen order.  Items name
   --  tags in the Document's pool, so each keeps its leading '@'.
   ---------------------------------------------------------------------

   subtype Tag_Count is Natural range 0 .. Limits.Max_Tags;
   type Tag_Items is array (1 .. Limits.Max_Tags) of Ast.Tag_Index;

   --  Ok is False when a stored tag range ran past its pool.
   type Tag_Set is record
      Ok    : Boolean := True;
      Count : Tag_Count := 0;
      Items : Tag_Items := [others => 1];
   end record;

   --  E is the concrete scenario's Examples block, or 0 for a plain
   --  scenario.
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
