--  One parsed feature file as flat pools and index handles.  Every
--  keyword, name, description, tag, step text, cell and doc-string
--  line is a slice of one text arena; nodes hold index ranges into the
--  pools, never nested arrays.  Builders only append, each to the most
--  recent node of its parent kind; a full pool refuses with Ok = False.
--  Every slice and range is sliceable by construction of its index
--  subtypes, so a reader needs no invariant to stay in bounds.
with Fabula.Limits;
with Fabula.Pool_Ranges;
with Fabula.Scan;

package Fabula.Ast
  with Pure, SPARK_Mode
is

   subtype Arena_Index is Positive range 1 .. Limits.Text_Arena_Bytes;
   subtype Arena_Count is Natural range 0 .. Limits.Text_Arena_Bytes;

   --  The length of a slice that holds no character.
   No_Characters : constant Arena_Count := 0;

   --  A span of the text arena; Last < First is the empty slice.
   type Slice is record
      First : Arena_Index := Arena_Index'First;
      Last  : Arena_Count := No_Characters;
   end record;

   Empty_Slice : constant Slice := (First => 1, Last => 0);

   function Is_Empty (S : Slice) return Boolean
   is (S.Last < S.First);

   function Length (S : Slice) return Natural
   is (if Is_Empty (S) then No_Characters else S.Last - S.First + 1);

   --  One handle type per pool, so no node can index the wrong pool.
   --  Each pool's Pool_Ranges instance holds its index arithmetic: its
   --  None is "no member", and a range is First .. Last, empty when
   --  Last < First.
   type Rule_Handle is range 0 .. Limits.Max_Rules;
   package Rule_Pool is new Pool_Ranges (Rule_Handle);
   subtype Rule_Index is Rule_Pool.Index;
   No_Rule : constant Rule_Handle := Rule_Pool.None;

   type Scenario_Handle is range 0 .. Limits.Max_Scenarios;
   package Scenario_Pool is new Pool_Ranges (Scenario_Handle);
   subtype Scenario_Index is Scenario_Pool.Index;
   subtype Scenario_Range is Scenario_Pool.Pool_Range;
   No_Scenario : constant Scenario_Handle := Scenario_Pool.None;

   type Step_Handle is range 0 .. Limits.Max_Steps;
   package Step_Pool is new Pool_Ranges (Step_Handle);
   subtype Step_Index is Step_Pool.Index;
   subtype Step_Range is Step_Pool.Pool_Range;
   No_Step : constant Step_Handle := Step_Pool.None;

   type Tag_Handle is range 0 .. Limits.Max_Tags;
   package Tag_Pool is new Pool_Ranges (Tag_Handle);
   subtype Tag_Index is Tag_Pool.Index;
   subtype Tag_Range is Tag_Pool.Pool_Range;

   --  A step carries at most one table and one doc string, so both
   --  pools are sized by the step pool.
   type Table_Handle is range 0 .. Limits.Max_Steps;
   package Table_Pool is new Pool_Ranges (Table_Handle);
   subtype Table_Index is Table_Pool.Index;
   No_Table : constant Table_Handle := Table_Pool.None;

   type Doc_Handle is range 0 .. Limits.Max_Steps;
   package Doc_Pool is new Pool_Ranges (Doc_Handle);
   subtype Doc_Index is Doc_Pool.Index;
   No_Doc : constant Doc_Handle := Doc_Pool.None;

   type Row_Handle is range 0 .. Limits.Max_Table_Rows;
   package Row_Pool is new Pool_Ranges (Row_Handle);
   subtype Row_Index is Row_Pool.Index;
   subtype Row_Range is Row_Pool.Pool_Range;

   type Cell_Handle is range 0 .. Limits.Max_Table_Cells;
   package Cell_Pool is new Pool_Ranges (Cell_Handle);
   subtype Cell_Index is Cell_Pool.Index;
   subtype Cell_Range is Cell_Pool.Pool_Range;

   type Doc_Line_Handle is range 0 .. Limits.Max_Doc_Lines;
   package Doc_Line_Pool is new Pool_Ranges (Doc_Line_Handle);
   subtype Doc_Line_Index is Doc_Line_Pool.Index;
   subtype Doc_Line_Range is Doc_Line_Pool.Pool_Range;

   type Examples_Handle is range 0 .. Limits.Max_Examples_Blocks;
   package Examples_Pool is new Pool_Ranges (Examples_Handle);
   subtype Examples_Index is Examples_Pool.Index;
   subtype Examples_Range is Examples_Pool.Pool_Range;
   No_Examples : constant Examples_Handle := Examples_Pool.None;

   type Examples_Row_Handle is range 0 .. Limits.Max_Examples_Rows;
   package Examples_Row_Pool is new Pool_Ranges (Examples_Row_Handle);
   subtype Examples_Row_Index is Examples_Row_Pool.Index;
   subtype Examples_Row_Range is Examples_Row_Pool.Pool_Range;
   No_Examples_Row : constant Examples_Row_Handle := Examples_Row_Pool.None;

   --  What every block header records: the keyword as written (colon
   --  dropped, so "Scenario Template" stays distinguishable), the
   --  title, the header's line, and its description lines joined by LF.
   type Header is record
      Keyword     : Slice;
      Name        : Slice;
      Line        : Line_Number := No_Line;
      Description : Slice;
   end record;

   type Feature_Node is record
      Present        : Boolean := False;
      Head           : Header;
      Tags           : Tag_Range;
      Has_Background : Boolean := False;
   end record;

   type Background_Node is record
      Head  : Header;
      Steps : Step_Range;
   end record;

   --  Scenarios after a Rule header belong to it until the next Rule.
   type Rule_Node is record
      Head      : Header;
      Scenarios : Scenario_Range;
   end record;

   type Scenario_Kind is (Plain, Outline);

   type Scenario_Node is record
      Kind     : Scenario_Kind := Plain;
      Head     : Header;
      Tags     : Tag_Range;
      Steps    : Step_Range;
      Examples : Examples_Range;
      Rule     : Rule_Handle := No_Rule;
   end record;

   type Step_Node is record
      Keyword : Scan.Step_Keyword := Scan.K_Star;
      Text    : Slice;
      Line    : Line_Number := No_Line;
      Doc     : Doc_Handle := No_Doc;
      Table   : Table_Handle := No_Table;
   end record;

   type Table_Node is record
      Rows : Row_Range;
   end record;

   --  A table row of either pool: its cells and its source line.
   type Row_Node is record
      Cells : Cell_Range;
      Line  : Line_Number := No_Line;
   end record;

   --  Content lines are stored trimmed on both sides; the content type
   --  keeps any leading whitespace after the opening fence.
   type Doc_String_Node is record
      Fence        : Scan.Fence_Kind := Scan.Quotes;
      Content_Type : Slice;
      Line         : Line_Number := No_Line;
      Lines        : Doc_Line_Range;
   end record;

   --  The first row of an Examples table is its header; the rest are
   --  data rows, one concrete scenario each.
   type Examples_Node is record
      Head       : Header;
      Tags       : Tag_Range;
      Header_Row : Examples_Row_Handle := No_Examples_Row;
      Rows       : Examples_Row_Range;
   end record;

   --  The node a description line extends.
   type Block_Kind is
     (Feature_Block,
      Background_Block,
      Rule_Block,
      Scenario_Block,
      Examples_Block);

   type Document is private;

   ---------------------------------------------------------------------
   --  Readers.  A node reader takes a handle no greater than its
   --  pool's count: Clear resets only the counts, so a slot past the
   --  count may still hold a node from an earlier document.
   ---------------------------------------------------------------------

   function Text (Doc : Document; S : Slice) return String
   with
     Post =>
       Text'Result'First = Positive'First
       and then Text'Result'Length = Length (S);
   --  The slice's characters, re-based to start at Positive'First.

   function Text_Used (Doc : Document) return Arena_Count;
   function Is_Empty (Doc : Document) return Boolean;

   function Feature (Doc : Document) return Feature_Node;
   function Background (Doc : Document) return Background_Node;

   function Rule_Count (Doc : Document) return Rule_Handle;
   function Rule (Doc : Document; R : Rule_Index) return Rule_Node
   with Pre => R <= Rule_Count (Doc);

   function Scenario_Count (Doc : Document) return Scenario_Handle;
   function Scenario (Doc : Document; S : Scenario_Index) return Scenario_Node
   with Pre => S <= Scenario_Count (Doc);

   function Step_Count (Doc : Document) return Step_Handle;
   function Step (Doc : Document; S : Step_Index) return Step_Node
   with Pre => S <= Step_Count (Doc);

   function Tag_Count (Doc : Document) return Tag_Handle;
   function Tag (Doc : Document; T : Tag_Index) return Slice
   with Pre => T <= Tag_Count (Doc);

   function Table_Count (Doc : Document) return Table_Handle;
   function Table (Doc : Document; T : Table_Index) return Table_Node
   with Pre => T <= Table_Count (Doc);

   function Table_Row_Count (Doc : Document) return Row_Handle;
   function Table_Row (Doc : Document; R : Row_Index) return Row_Node
   with Pre => R <= Table_Row_Count (Doc);

   function Cell_Count (Doc : Document) return Cell_Handle;
   function Cell (Doc : Document; C : Cell_Index) return Slice
   with Pre => C <= Cell_Count (Doc);

   function Doc_String_Count (Doc : Document) return Doc_Handle;
   function Doc_String (Doc : Document; D : Doc_Index) return Doc_String_Node
   with Pre => D <= Doc_String_Count (Doc);

   function Doc_Line_Count (Doc : Document) return Doc_Line_Handle;
   function Doc_Line (Doc : Document; L : Doc_Line_Index) return Slice
   with Pre => L <= Doc_Line_Count (Doc);

   function Examples_Count (Doc : Document) return Examples_Handle;
   function Examples (Doc : Document; E : Examples_Index) return Examples_Node
   with Pre => E <= Examples_Count (Doc);

   function Examples_Row_Count (Doc : Document) return Examples_Row_Handle;
   function Examples_Row
     (Doc : Document; R : Examples_Row_Index) return Row_Node
   with Pre => R <= Examples_Row_Count (Doc);

   ---------------------------------------------------------------------
   --  Builders.  Each appends; Ok = False means the pool (or the arena)
   --  is full and the document is unchanged.
   ---------------------------------------------------------------------

   procedure Clear (Doc : in out Document)
   with Post => Is_Empty (Doc);

   procedure Append_Text
     (Doc    : in out Document;
      Source : String;
      Result : out Slice;
      Ok     : out Boolean)
   with
     Post =>
       Text_Used (Doc)
       = Text_Used (Doc)'Old + (if Ok then Source'Length else No_Characters)
       and then (if Ok then Length (Result) = Source'Length);

   procedure Set_Feature
     (Doc : in out Document; Head : Header; Tags : Tag_Range)
   with Post => Feature (Doc).Present;

   procedure Set_Background (Doc : in out Document; Head : Header)
   with Post => Feature (Doc).Has_Background;

   procedure Add_Rule (Doc : in out Document; Head : Header; Ok : out Boolean)
   with
     Post =>
       Rule_Count (Doc) = Rule_Pool.Count_After (Rule_Count (Doc)'Old, Ok);

   --  The new scenario joins the most recent rule, if any.
   procedure Add_Scenario
     (Doc  : in out Document;
      Kind : Scenario_Kind;
      Head : Header;
      Tags : Tag_Range;
      Ok   : out Boolean)
   with
     Post =>
       Scenario_Count (Doc)
       = Scenario_Pool.Count_After (Scenario_Count (Doc)'Old, Ok);

   --  The new block joins the most recent scenario.
   procedure Add_Examples
     (Doc : in out Document; Head : Header; Tags : Tag_Range; Ok : out Boolean)
   with
     Post =>
       Examples_Count (Doc)
       = Examples_Pool.Count_After (Examples_Count (Doc)'Old, Ok);

   --  Appends one description line to Target's most recent node,
   --  joined to the lines before it by LF into one arena slice.  So a
   --  caller appends nothing else to the arena between two lines of
   --  one description; the parser guarantees it, because a description
   --  ends at the first line that stores anything other than prose.
   procedure Describe
     (Doc    : in out Document;
      Target : Block_Kind;
      Source : String;
      Ok     : out Boolean)
   with Pre => Source'Length <= Limits.Max_Line_Length;

   --  Appends a tag and widens Pending, the run of tags not yet
   --  attached to a node, to cover it.
   procedure Add_Tag
     (Doc     : in out Document;
      Text    : Slice;
      Pending : in out Tag_Range;
      Ok      : out Boolean)
   with
     Post => Tag_Count (Doc) = Tag_Pool.Count_After (Tag_Count (Doc)'Old, Ok);

   --  The new step joins the most recent scenario, or the background
   --  while no scenario exists yet.
   procedure Add_Step
     (Doc     : in out Document;
      Keyword : Scan.Step_Keyword;
      Text    : Slice;
      Line    : Line_Number;
      Ok      : out Boolean)
   with
     Post =>
       Step_Count (Doc) = Step_Pool.Count_After (Step_Count (Doc)'Old, Ok);

   --  Gives the most recent step an empty table.
   procedure Add_Table (Doc : in out Document; Ok : out Boolean)
   with
     Post =>
       Table_Count (Doc) = Table_Pool.Count_After (Table_Count (Doc)'Old, Ok);

   procedure Add_Table_Row
     (Doc : in out Document; Line : Line_Number; Ok : out Boolean)
   with
     Post =>
       Table_Row_Count (Doc)
       = Row_Pool.Count_After (Table_Row_Count (Doc)'Old, Ok);

   procedure Add_Table_Cell
     (Doc : in out Document; Text : Slice; Ok : out Boolean)
   with
     Post =>
       Cell_Count (Doc) = Cell_Pool.Count_After (Cell_Count (Doc)'Old, Ok);

   --  The block's first row becomes its header, every later row data.
   procedure Add_Examples_Row
     (Doc : in out Document; Line : Line_Number; Ok : out Boolean)
   with
     Post =>
       Examples_Row_Count (Doc)
       = Examples_Row_Pool.Count_After (Examples_Row_Count (Doc)'Old, Ok);

   procedure Add_Examples_Cell
     (Doc : in out Document; Text : Slice; Ok : out Boolean)
   with
     Post =>
       Cell_Count (Doc) = Cell_Pool.Count_After (Cell_Count (Doc)'Old, Ok);

   --  Gives the most recent step a doc string with no lines yet.
   procedure Add_Doc_String
     (Doc          : in out Document;
      Fence        : Scan.Fence_Kind;
      Content_Type : Slice;
      Line         : Line_Number;
      Ok           : out Boolean)
   with
     Post =>
       Doc_String_Count (Doc)
       = Doc_Pool.Count_After (Doc_String_Count (Doc)'Old, Ok);

   procedure Add_Doc_Line
     (Doc : in out Document; Text : Slice; Ok : out Boolean)
   with
     Post =>
       Doc_Line_Count (Doc)
       = Doc_Line_Pool.Count_After (Doc_Line_Count (Doc)'Old, Ok);

private

   type Rule_Slots is array (Rule_Index) of Rule_Node;
   type Scenario_Slots is array (Scenario_Index) of Scenario_Node;
   type Step_Slots is array (Step_Index) of Step_Node;
   type Tag_Slots is array (Tag_Index) of Slice;
   type Table_Slots is array (Table_Index) of Table_Node;
   type Row_Slots is array (Row_Index) of Row_Node;
   type Cell_Slots is array (Cell_Index) of Slice;
   type Doc_Slots is array (Doc_Index) of Doc_String_Node;
   type Doc_Line_Slots is array (Doc_Line_Index) of Slice;
   type Examples_Slots is array (Examples_Index) of Examples_Node;
   type Examples_Row_Slots is array (Examples_Row_Index) of Row_Node;

   --  Each pool's count starts at its None, the count of an empty pool.
   type Document is record
      Arena             : String (Arena_Index) := [others => ' '];
      Used              : Arena_Count := No_Characters;
      The_Feature       : Feature_Node;
      The_Background    : Background_Node;
      Rules             : Rule_Slots;
      Rules_Used        : Rule_Handle := Rule_Pool.None;
      Scenarios         : Scenario_Slots;
      Scenarios_Used    : Scenario_Handle := Scenario_Pool.None;
      Steps             : Step_Slots;
      Steps_Used        : Step_Handle := Step_Pool.None;
      Tags              : Tag_Slots;
      Tags_Used         : Tag_Handle := Tag_Pool.None;
      Tables            : Table_Slots;
      Tables_Used       : Table_Handle := Table_Pool.None;
      Rows              : Row_Slots;
      Rows_Used         : Row_Handle := Row_Pool.None;
      Cells             : Cell_Slots;
      Cells_Used        : Cell_Handle := Cell_Pool.None;
      Docs              : Doc_Slots;
      Docs_Used         : Doc_Handle := Doc_Pool.None;
      Doc_Lines         : Doc_Line_Slots;
      Doc_Lines_Used    : Doc_Line_Handle := Doc_Line_Pool.None;
      Blocks            : Examples_Slots;
      Blocks_Used       : Examples_Handle := Examples_Pool.None;
      Example_Rows      : Examples_Row_Slots;
      Example_Rows_Used : Examples_Row_Handle := Examples_Row_Pool.None;
   end record;

   function Text_Used (Doc : Document) return Arena_Count
   is (Doc.Used);

   function Is_Empty (Doc : Document) return Boolean
   is (Doc.Used = 0
       and then not Doc.The_Feature.Present
       and then not Doc.The_Feature.Has_Background
       and then Doc.Rules_Used = 0
       and then Doc.Scenarios_Used = 0
       and then Doc.Steps_Used = 0
       and then Doc.Tags_Used = 0
       and then Doc.Tables_Used = 0
       and then Doc.Rows_Used = 0
       and then Doc.Cells_Used = 0
       and then Doc.Docs_Used = 0
       and then Doc.Doc_Lines_Used = 0
       and then Doc.Blocks_Used = 0
       and then Doc.Example_Rows_Used = 0);

   function Feature (Doc : Document) return Feature_Node
   is (Doc.The_Feature);

   function Background (Doc : Document) return Background_Node
   is (Doc.The_Background);

   function Rule_Count (Doc : Document) return Rule_Handle
   is (Doc.Rules_Used);

   function Rule (Doc : Document; R : Rule_Index) return Rule_Node
   is (Doc.Rules (R));

   function Scenario_Count (Doc : Document) return Scenario_Handle
   is (Doc.Scenarios_Used);

   function Scenario (Doc : Document; S : Scenario_Index) return Scenario_Node
   is (Doc.Scenarios (S));

   function Step_Count (Doc : Document) return Step_Handle
   is (Doc.Steps_Used);

   function Step (Doc : Document; S : Step_Index) return Step_Node
   is (Doc.Steps (S));

   function Tag_Count (Doc : Document) return Tag_Handle
   is (Doc.Tags_Used);

   function Tag (Doc : Document; T : Tag_Index) return Slice
   is (Doc.Tags (T));

   function Table_Count (Doc : Document) return Table_Handle
   is (Doc.Tables_Used);

   function Table (Doc : Document; T : Table_Index) return Table_Node
   is (Doc.Tables (T));

   function Table_Row_Count (Doc : Document) return Row_Handle
   is (Doc.Rows_Used);

   function Table_Row (Doc : Document; R : Row_Index) return Row_Node
   is (Doc.Rows (R));

   function Cell_Count (Doc : Document) return Cell_Handle
   is (Doc.Cells_Used);

   function Cell (Doc : Document; C : Cell_Index) return Slice
   is (Doc.Cells (C));

   function Doc_String_Count (Doc : Document) return Doc_Handle
   is (Doc.Docs_Used);

   function Doc_String (Doc : Document; D : Doc_Index) return Doc_String_Node
   is (Doc.Docs (D));

   function Doc_Line_Count (Doc : Document) return Doc_Line_Handle
   is (Doc.Doc_Lines_Used);

   function Doc_Line (Doc : Document; L : Doc_Line_Index) return Slice
   is (Doc.Doc_Lines (L));

   function Examples_Count (Doc : Document) return Examples_Handle
   is (Doc.Blocks_Used);

   function Examples (Doc : Document; E : Examples_Index) return Examples_Node
   is (Doc.Blocks (E));

   function Examples_Row_Count (Doc : Document) return Examples_Row_Handle
   is (Doc.Example_Rows_Used);

   function Examples_Row
     (Doc : Document; R : Examples_Row_Index) return Row_Node
   is (Doc.Example_Rows (R));

end Fabula.Ast;
