with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast; use Fabula.Ast;
with Fabula.Limits;
with Fabula.Scan;

package body Fabula_Ast_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Scan.Step_Keyword;
   use type Fabula.Scan.Fence_Kind;
   use type Fabula.Line_Number;
   use type Cell_Range;
   use type Doc_Line_Range;
   use type Examples_Range;
   use type Examples_Row_Range;
   use type Row_Range;
   use type Scenario_Range;
   use type Step_Range;
   use type Tag_Range;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;

   procedure Put (Source : String; Result : out Slice) is
      Ok : Boolean;
   begin
      Append_Text (Doc, Source, Result, Ok);
      Assert (Ok, "appending """ & Source & """ must fit the arena");
   end Put;

   procedure Make_Head
     (Keyword : String;
      Name    : String;
      Line    : Fabula.Source_Line;
      Head    : out Header) is
   begin
      Head := (Line => Line, others => <>);
      Put (Keyword, Head.Keyword);
      Put (Name, Head.Name);
   end Make_Head;

   procedure Check (Ok : Boolean; What : String) is
   begin
      Assert (Ok, What & " must fit its pool");
   end Check;

   function Named (Head : Header) return String
   is (Text (Doc, Head.Name));

   procedure Test_Text_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Word, Nothing, Abc : Slice;
   begin
      Clear (Doc);
      Put ("Feature", Word);
      Put ("", Nothing);
      Put ("abc", Abc);
      Assert (Text (Doc, Word) = "Feature", "first slice reads back");
      Assert (Text (Doc, Abc) = "abc", "third slice reads back");
      Assert (Text (Doc, Abc)'First = 1, "a slice re-bases to 1");
      Assert (Length (Nothing) = 0, "an empty source is an empty slice");
      Assert (Text_Used (Doc) = 10, "the arena holds exactly the text");
   end Test_Text_Round_Trip;

   procedure Test_Arena_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Chunk  : constant String (1 .. Fabula.Limits.Max_Line_Length) :=
        [others => 'x'];
      Chunks : constant := Fabula.Limits.Text_Arena_Bytes / Chunk'Length;
      S      : Slice;
      Ok     : Boolean;
   begin
      Clear (Doc);
      for I in 1 .. Chunks loop
         Append_Text (Doc, Chunk, S, Ok);
         Check (Ok, "chunk" & I'Image);
      end loop;
      Assert
        (Text_Used (Doc) = Fabula.Limits.Text_Arena_Bytes, "arena is full");
      Append_Text (Doc, "y", S, Ok);
      Assert (not Ok, "one byte past the arena must be refused");
      Assert
        (Text_Used (Doc) = Fabula.Limits.Text_Arena_Bytes,
         "a refusal leaves the arena unchanged");
      Append_Text (Doc, "", S, Ok);
      Assert (Ok, "an empty source always fits");
   end Test_Arena_Overflow;

   procedure Build_Blocks is
      Head    : Header;
      Pending : Tag_Range;
      Tag_S   : Slice;
      Ok      : Boolean;
   begin
      Clear (Doc);
      Put ("@t", Tag_S);
      Add_Tag (Doc, Tag_S, Pending, Ok);
      Check (Ok, "tag");
      Make_Head ("Feature", "f", 1, Head);
      Set_Feature (Doc, Head, Pending);
      Make_Head ("Background", "", 2, Head);
      Set_Background (Doc, Head);
      Put ("a", Tag_S);
      Add_Step (Doc, Fabula.Scan.K_Given, Tag_S, 3, Ok);
      Check (Ok, "background step");
      Make_Head ("Scenario", "s", 4, Head);
      Add_Scenario (Doc, Plain, Head, (others => <>), Ok);
      Check (Ok, "scenario");
      Put ("b", Tag_S);
      Add_Step (Doc, Fabula.Scan.K_When, Tag_S, 5, Ok);
      Check (Ok, "scenario step");
      Make_Head ("Rule", "r", 6, Head);
      Add_Rule (Doc, Head, Ok);
      Check (Ok, "rule");
      Make_Head ("Scenario Outline", "o", 7, Head);
      Add_Scenario (Doc, Outline, Head, (others => <>), Ok);
      Check (Ok, "outline");
      Put ("c", Tag_S);
      Add_Step (Doc, Fabula.Scan.K_Then, Tag_S, 8, Ok);
      Check (Ok, "outline step");
   end Build_Blocks;

   procedure Test_Blocks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Build_Blocks;
      Assert (Feature (Doc).Present, "the feature is present");
      Assert (Named (Feature (Doc).Head) = "f", "feature name");
      Assert (Feature (Doc).Tags = (1, 1), "the feature owns the tag");
      Assert (Text (Doc, Tag (Doc, 1)) = "@t", "tag text keeps its '@'");
      Assert (Feature (Doc).Has_Background, "the background is present");
      Assert (Background (Doc).Steps = (1, 1), "first step: background");
      Assert (Scenario (Doc, 1).Steps = (2, 2), "second step: scenario 1");
      Assert (Scenario (Doc, 1).Rule = 0, "scenario 1 has no rule");
      Assert (Scenario (Doc, 2).Kind = Outline, "scenario 2 is an outline");
      Assert (Scenario (Doc, 2).Rule = 1, "scenario 2 joins the rule");
      Assert (Rule (Doc, 1).Scenarios = (2, 2), "the rule owns scenario 2");
      Assert (Step (Doc, 3).Keyword = Fabula.Scan.K_Then, "keyword");
      Assert (Text (Doc, Step (Doc, 3).Text) = "c", "step text");
      Assert (Step (Doc, 3).Line = 8, "step line");
      Assert
        (Text (Doc, Scenario (Doc, 2).Head.Keyword) = "Scenario Outline",
         "the keyword is stored as written");
   end Test_Blocks;

   procedure Build_Table is
      Head : Header;
      S    : Slice;
      Ok   : Boolean;
   begin
      Clear (Doc);
      Make_Head ("Scenario", "s", 1, Head);
      Add_Scenario (Doc, Plain, Head, (others => <>), Ok);
      Put ("a step", S);
      Add_Step (Doc, Fabula.Scan.K_Given, S, 2, Ok);
      Add_Table (Doc, Ok);
      Check (Ok, "table");
      for Row in 1 .. 2 loop
         Add_Table_Row (Doc, Fabula.Line_Number (2 + Row), Ok);
         Check (Ok, "table row");
         for Col in 1 .. 2 loop
            Put
              ([1 => Character'Val (Character'Pos ('a') + Row * 2 + Col - 3)],
               S);
            Add_Table_Cell (Doc, S, Ok);
            Check (Ok, "table cell");
         end loop;
      end loop;
   end Build_Table;

   procedure Test_Table (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Build_Table;
      Assert (Step (Doc, 1).Table = 1, "the step owns the table");
      Assert (Table (Doc, 1).Rows = (1, 2), "the table owns both rows");
      Assert (Table_Row (Doc, 2).Cells = (3, 4), "row 2 owns cells 3-4");
      Assert (Table_Row (Doc, 2).Line = 4, "row 2's line");
      Assert (Text (Doc, Cell (Doc, 3)) = "c", "cell 3 text");
      Assert (Cell_Count (Doc) = 4, "four cells");
   end Test_Table;

   procedure Build_Examples is
      Head    : Header;
      Pending : Tag_Range;
      S       : Slice;
      Ok      : Boolean;
   begin
      Clear (Doc);
      Make_Head ("Scenario Outline", "o", 1, Head);
      Add_Scenario (Doc, Outline, Head, (others => <>), Ok);
      Put ("@x", S);
      Add_Tag (Doc, S, Pending, Ok);
      Put ("@y", S);
      Add_Tag (Doc, S, Pending, Ok);
      Make_Head ("Examples", "", 3, Head);
      Add_Examples (Doc, Head, Pending, Ok);
      Check (Ok, "examples");
      for Row in 1 .. 3 loop
         Add_Examples_Row (Doc, Fabula.Line_Number (3 + Row), Ok);
         Check (Ok, "examples row");
         Put (Row'Image, S);
         Add_Examples_Cell (Doc, S, Ok);
         Check (Ok, "examples cell");
      end loop;
   end Build_Examples;

   procedure Test_Examples (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Build_Examples;
      Assert (Scenario (Doc, 1).Examples = (1, 1), "the outline owns it");
      Assert (Examples (Doc, 1).Tags = (1, 2), "both tags attach");
      Assert (Examples (Doc, 1).Header_Row = 1, "row 1 is the header");
      Assert (Examples (Doc, 1).Rows = (2, 3), "rows 2-3 are data");
      Assert (Examples_Row (Doc, 3).Line = 6, "row 3's line");
      Assert (Examples_Row (Doc, 3).Cells = (3, 3), "row 3 owns cell 3");
   end Test_Examples;

   procedure Test_Doc_String (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Head : Header;
      S    : Slice;
      Ok   : Boolean;
   begin
      Clear (Doc);
      Make_Head ("Scenario", "s", 1, Head);
      Add_Scenario (Doc, Plain, Head, (others => <>), Ok);
      Put ("a step", S);
      Add_Step (Doc, Fabula.Scan.K_Given, S, 2, Ok);
      Put ("json", S);
      Add_Doc_String (Doc, Fabula.Scan.Backticks, S, 3, Ok);
      Check (Ok, "doc string");
      Put ("x", S);
      Add_Doc_Line (Doc, S, Ok);
      Put ("y", S);
      Add_Doc_Line (Doc, S, Ok);
      Check (Ok, "doc line");
      Assert (Step (Doc, 1).Doc = 1, "the step owns the doc string");
      Assert (Doc_String (Doc, 1).Lines = (1, 2), "both lines attach");
      Assert (Doc_String (Doc, 1).Fence = Fabula.Scan.Backticks, "fence");
      Assert
        (Text (Doc, Doc_String (Doc, 1).Content_Type) = "json",
         "content type");
      Assert (Text (Doc, Doc_Line (Doc, 2)) = "y", "second line");
   end Test_Doc_String;

   procedure Test_Descriptions (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Head : Header;
      Ok   : Boolean;
   begin
      Clear (Doc);
      Make_Head ("Feature", "f", 1, Head);
      Set_Feature (Doc, Head, (others => <>));
      Describe (Doc, Feature_Block, "one", Ok);
      Describe (Doc, Feature_Block, "two", Ok);
      Check (Ok, "description");
      Make_Head ("Scenario", "s", 4, Head);
      Add_Scenario (Doc, Plain, Head, (others => <>), Ok);
      Describe (Doc, Scenario_Block, "three", Ok);
      Assert
        (Text (Doc, Feature (Doc).Head.Description) = "one" & ASCII.LF & "two",
         "feature description lines join by LF");
      Assert
        (Text (Doc, Scenario (Doc, 1).Head.Description) = "three",
         "a scenario description");
   end Test_Descriptions;

   --  The smallest pool: one rule past capacity is refused and the
   --  count stays at the capacity.
   procedure Test_Pool_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Head : Header;
      Ok   : Boolean;
   begin
      Clear (Doc);
      Make_Head ("Rule", "r", 1, Head);
      for I in 1 .. Fabula.Limits.Max_Rules loop
         Add_Rule (Doc, Head, Ok);
         Check (Ok, "rule" & I'Image);
      end loop;
      Add_Rule (Doc, Head, Ok);
      Assert (not Ok, "a rule past Max_Rules must be refused");
      Assert
        (Rule_Count (Doc) = Rule_Handle (Fabula.Limits.Max_Rules),
         "the refusal leaves the count at capacity");
   end Test_Pool_Overflow;

   --  A document lives at library level in the suite and in the shell;
   --  it must stay a few megabytes, not grow with nesting.
   procedure Test_Size (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Megabyte : constant := 1_048_576;
      Bytes    : constant Natural := Doc'Size / 8;
   begin
      Assert
        (Bytes <= 4 * Megabyte,
         "a document is" & Bytes'Image & " bytes, over 4 MB");
   end Test_Size;

   --  One pool's range arithmetic, through the cell pool's instance.
   procedure Test_Pool_Ranges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      One : constant Cell_Range := Cell_Pool.Extended (Cell_Pool.Empty, 3);
      Two : constant Cell_Range := Cell_Pool.Extended (One, 4);
   begin
      Assert (Cell_Pool.Is_Empty (Cell_Pool.Empty), "Empty holds nothing");
      Assert (One = (3, 3), "an empty range becomes its new member alone");
      Assert (Two = (3, 4), "a range widens to its newest member");
      Assert (Cell_Pool.Width (Two) = 2, "a range's width");
      Assert (Cell_Pool.Width (Cell_Pool.Empty) = 0, "the empty width");
      Assert (Cell_Pool.Span (Two, 4) = 2, "a range inside its pool spans");
      Assert (Cell_Pool.Span (Two, 3) = 0, "a range past its pool spans none");
      Assert (Cell_Pool.Span (Cell_Pool.Empty, 0) = 0, "the empty span");
      Assert (Cell_Pool.Inside (Cell_Pool.Empty, 0), "empty is inside");
      Assert (not Cell_Pool.Inside (Two, 3), "a range past the pool is not");
      Assert (not Cell_Pool.Is_Live (Cell_Pool.None, 5), "None is no member");
      Assert (Cell_Pool.Is_Live (5, 5), "the newest member is live");
      Assert (not Cell_Pool.Is_Live (6, 5), "a handle past the count is not");
      Assert (not Cell_Pool.Has_Newest (Cell_Pool.None), "an empty pool");
      Assert (Cell_Pool.Has_Newest (1), "a pool of one has a newest member");
      Assert (Cell_Pool.Newest (1) = 1, "the only member is the newest");
      Assert (Cell_Pool.Newest (5) = 5, "the newest member is the count");
   end Test_Pool_Ranges;

   procedure Test_Clear (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Build_Blocks;
      Assert (not Is_Empty (Doc), "a built document is not empty");
      Clear (Doc);
      Assert (Is_Empty (Doc), "Clear empties every pool");
      Assert (not Feature (Doc).Present, "Clear drops the feature");
   end Test_Clear;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Text_Round_Trip'Access, "text round trip");
      Register_Routine (T, Test_Arena_Overflow'Access, "arena overflow");
      Register_Routine (T, Test_Blocks'Access, "blocks own their steps");
      Register_Routine (T, Test_Table'Access, "step tables");
      Register_Routine (T, Test_Examples'Access, "examples blocks");
      Register_Routine (T, Test_Doc_String'Access, "doc strings");
      Register_Routine (T, Test_Descriptions'Access, "descriptions");
      Register_Routine (T, Test_Pool_Overflow'Access, "pool overflow");
      Register_Routine (T, Test_Pool_Ranges'Access, "pool range arithmetic");
      Register_Routine (T, Test_Clear'Access, "clear");
      Register_Routine (T, Test_Size'Access, "a document's size");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Ast (arena document)"));

end Fabula_Ast_Tests;
