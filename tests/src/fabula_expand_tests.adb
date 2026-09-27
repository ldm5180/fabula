with AUnit.Assertions;  use AUnit.Assertions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Fabula;
with Fabula.Ast;    use Fabula.Ast;
with Fabula.Expand; use Fabula.Expand;
with Fabula.Limits;
with Fabula.Parse;  use Fabula.Parse;

with Fabula_Fixtures; use Fabula_Fixtures;

package body Fabula_Expand_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Line_Number;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;
   P   : Parser;

   Max : constant := Fabula.Limits.Max_Line_Length;

   procedure Load (Source : Lines) is
   begin
      Parse_Lines (Source, P, Doc);
      Assert (not Failed (P), "the fixture must parse");
   end Load;

   procedure Load (Name : String) is
   begin
      Parse_Corpus (Name, P, Doc);
      Assert (not Failed (P), Name & " must parse");
   end Load;

   ---------------------------------------------------------------------
   --  Substitution against one Examples row.
   ---------------------------------------------------------------------

   Substitution_Doc : constant Lines :=
     [+"Feature: f",
      +"  Scenario Outline: o",
      +"    Given <a> and <b> and <c>",
      +"    Examples:",
      +"      | a | b  | empty | angle |",
      +"      | 1 | xy |       | <b>   |"];

   function Header return Examples_Row_Index
   is (Examples (Doc, 1).Header_Row);

   function Data return Examples_Row_Index
   is (Examples (Doc, 1).Rows.First);

   function Sub (Text : String) return Text_Result
   is (Substituted (Doc, Text, Header, Data));

   procedure Assert_Sub (Text, Want : String; Unknown : Natural) is
      R : constant Text_Result := Sub (Text);
   begin
      Assert (R.Ok, Text & ": must fit");
      Assert
        (Value (R) = Want,
         Text & ": expected """ & Want & """, got """ & Value (R) & """");
      Assert
        (R.Unknown = Unknown,
         Text & ": unknown placeholders" & R.Unknown'Image);
   end Assert_Sub;

   procedure Test_Placeholders (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Load (Substitution_Doc);
      Assert_Sub ("<a> and <b> and <c>", "1 and xy and <c>", 1);
      Assert_Sub ("<a><b>", "1xy", 0);
      Assert_Sub ("no placeholder", "no placeholder", 0);
      Assert_Sub ("", "", 0);
   end Test_Placeholders;

   --  An empty value becomes "" and a value is never scanned again.
   procedure Test_Values (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Load (Substitution_Doc);
      Assert_Sub ("[<empty>]", "[""""]", 0);
      Assert_Sub ("<angle>", "<b>", 0);
   end Test_Values;

   --  A placeholder runs from '<' to the first '>' on the same line; a
   --  key no header names, the brackets included, stays as written.
   procedure Test_Brackets (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Load (Substitution_Doc);
      Assert_Sub ("<a <b>", "<a <b>", 1);
      Assert_Sub ("x<a>y<", "x1y<", 0);
      Assert_Sub ("<a", "<a", 0);
      Assert_Sub ("<a" & ASCII.CR & "> <b>", "<a" & ASCII.CR & "> xy", 0);
      Assert_Sub ("a > b <a>", "a > b 1", 0);
   end Test_Brackets;

   procedure Test_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Fits : constant String := (Max - 2) * 'x' & "<b>";
      Over : constant String := (Max - 1) * 'x' & "<b>";
   begin
      Load (Substitution_Doc);
      Assert (Sub (Fits).Ok, "an expansion to exactly the limit fits");
      Assert (Value (Sub (Fits))'Length = Max, "and fills it");
      Assert (not Sub (Over).Ok, "one character more refuses");
      Assert (Value_Or (Sub ("<a>"), "kept") = "1", "Value_Or of a good one");
      Assert
        (Value_Or (Sub (Over), "kept") = "kept",
         "Value_Or of a refused one is the default");
      Assert
        (not Substituted (Doc, "<a>", Header, Examples_Row_Count (Doc) + 1).Ok,
         "a row handle past the pool refuses");
      Assert
        (Concrete_Line (Doc, Examples_Row_Count (Doc) + 1) = 0,
         "and has no line");
   end Test_Overflow;

   ---------------------------------------------------------------------
   --  Concrete scenarios of the corpus outlines.
   ---------------------------------------------------------------------

   procedure Assert_Concrete
     (Ref  : Example_Ref;
      S    : Scenario_Index;
      Name : String;
      Line : Fabula.Line_Number) is
   begin
      Assert (Ref.Status = Row_Due, Name & ": a concrete scenario is due");
      Assert
        (Value (Concrete_Name (Doc, S, Ref.Header_Row, Ref.Data_Row)) = Name,
         "expected """
         & Name
         & """, got """
         & Value (Concrete_Name (Doc, S, Ref.Header_Row, Ref.Data_Row))
         & """");
      Assert
        (Concrete_Line (Doc, Ref.Data_Row) = Line,
         Name
         & ": the data row's line, got"
         & Concrete_Line (Doc, Ref.Data_Row)'Image);
   end Assert_Concrete;

   procedure Test_Concrete_Scenarios
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ref : Example_Ref;
   begin
      Load ("2_scenario_outline.feature");
      Ref := First_Example (Doc, 1);
      Assert_Concrete (Ref, 1, "Scenario Outline with ""apple""", 11);
      Ref := Next_Example (Doc, 1, Ref);
      Assert_Concrete (Ref, 1, "Scenario Outline with ""bananas""", 12);
      Ref := Next_Example (Doc, 1, Ref);
      Assert (Ref.Status = Ended, "two rows, then done");
      Ref := First_Example (Doc, 2);
      Assert_Concrete (Ref, 2, "Alternative Keywords", 21);
      Ref := Next_Example (Doc, 2, Next_Example (Doc, 2, Ref));
      Assert (Ref.Status = Ended, "two rows, then done");
      Assert
        (Next_Example (Doc, 2, Ref).Status = Ended,
         "an ended walk stays ended");
   end Test_Concrete_Scenarios;

   --  Every data row of every outline is one concrete scenario: the
   --  manifest's row count for the file.
   procedure Test_Concrete_Count (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Total : Natural := 0;
      Ref   : Example_Ref;
   begin
      Load ("6_tables.feature");
      for S in 1 .. Scenario_Count (Doc) loop
         Ref := First_Example (Doc, S);
         while Ref.Status = Row_Due loop
            Total := Total + 1;
            Ref := Next_Example (Doc, S, Ref);
         end loop;
         Assert (Ref.Status /= Stale, "no stored range runs past its pool");
      end loop;
      Assert (Total = 7, "the manifest's 7 rows, got" & Total'Image);
   end Test_Concrete_Count;

   ---------------------------------------------------------------------
   --  Step text, doc lines and table cells.
   ---------------------------------------------------------------------

   function Nth_Step (S : Scenario_Index; N : Positive) return Step_Node
   is (Step (Doc, Scenario (Doc, S).Steps.First + Step_Handle (N) - 1));

   function Resolve (S : Slice; Ref : Example_Ref) return String
   is (Value (Resolved (Doc, S, Ref.Header_Row, Ref.Data_Row)));

   procedure Test_Step_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Ref : Example_Ref;
   begin
      Load ("2_scenario_outline.feature");
      Ref := First_Example (Doc, 1);
      Assert
        (Resolve (Nth_Step (1, 2).Text, Ref) = "I place 1 x ""apple"" in it",
         "two placeholders in a step, got "
         & Resolve (Nth_Step (1, 2).Text, Ref));
      Assert
        (Value (Resolved (Doc, Nth_Step (1, 2).Text, 0, 0))
         = "I place <count> x <item> in it",
         "no Examples row: a plain copy");
      Load ("6_tables.feature");
      Ref := First_Example (Doc, 5);
      Assert
        (Resolve (Nth_Step (5, 2).Text, Ref) = "The box contains 8 items",
         "a key with a blank in it");
   end Test_Step_Text;

   procedure Test_Doc_Lines (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Ref   : Example_Ref;
      Label : Doc_String_Node;
      R     : Text_Result;
   begin
      Load ("7_doc_strings.feature");
      Ref := First_Example (Doc, 5);
      Label := Doc_String (Doc, Nth_Step (5, 2).Doc);
      R :=
        Resolved
          (Doc,
           Doc_Line (Doc, Label.Lines.First),
           Ref.Header_Row,
           Ref.Data_Row);
      Assert
        (Value (R) = "Ship to: Berlin, Germany. Barcode template: <barcode>",
         "a placeholder inside a doc line, got " & Value (R));
      Assert (R.Unknown = 1, "<barcode> names no column");
      R := Resolved (Doc, Nth_Step (5, 3).Text, Ref.Header_Row, Ref.Data_Row);
      Assert
        (Value (R)
         = "The shipping label should equal "
           & """Ship to: Berlin, Germany. Barcode template: <barcode>""",
         "a value holding <barcode>, got " & Value (R));
      Assert (R.Unknown = 0, "a value is never scanned again");
   end Test_Doc_Lines;

   function Cell_Of (Node : Step_Node; Row, Col : Positive) return Slice
   is (Cell
         (Doc,
          Table_Row
            (Doc, Table (Doc, Node.Table).Rows.First + Row_Handle (Row) - 1)
            .Cells
            .First
          + Cell_Handle (Col)
          - 1));

   procedure Test_Cells (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Ref : Example_Ref;
   begin
      Load ("6_tables.feature");
      Ref := First_Example (Doc, 3);
      Assert
        (Resolve (Cell_Of (Nth_Step (3, 2), 1, 1), Ref)
         = "a very fresh orange",
         "a placeholder inside a cell");
      Assert (Resolve (Cell_Of (Nth_Step (3, 2), 1, 2), Ref) = "2", "row 1");
      Ref := Next_Example (Doc, 3, Ref);
      Assert
        (Resolve (Cell_Of (Nth_Step (3, 2), 1, 1), Ref) = "a very fresh apple",
         "the second data row");
      Ref := First_Example (Doc, 5);
      Assert
        (Resolve (Cell_Of (Nth_Step (5, 1), 2, 1), Ref) = "book",
         "<item 2> in the second table row");
   end Test_Cells;

   --  A step fits when its text, doc lines and cells all expand within
   --  the line limit.
   Half : constant String := (Max / 2 + 1) * 'z';

   Fit_Doc : constant Lines :=
     [+"Feature: f",
      +"  Scenario Outline: o",
      +"    Given <big> alone",
      +"    When a cell doubles it",
      +"      | <big><big> |",
      +"    Then a doc line doubles it",
      +"      """"""",
      +"      <big><big>",
      +"      """"""",
      +"    And its text doubles it: <big><big>",
      +"    Examples:",
      +"      | big |",
      +("      | " & Half & " |")];

   procedure Test_Step_Fits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Load (Fit_Doc);
      Assert
        (Step_Fits (Doc, Nth_Step (1, 1), Header, Data), "a text that fits");
      Assert
        (not Step_Fits (Doc, Nth_Step (1, 2), Header, Data),
         "a cell over the limit");
      Assert
        (not Step_Fits (Doc, Nth_Step (1, 3), Header, Data),
         "a doc line over the limit");
      Assert
        (Step_Fits (Doc, Nth_Step (1, 2), 0, 0),
         "unexpanded, the same cell fits");
      Assert
        (not Resolved (Doc, Nth_Step (1, 4).Text, Header, Data).Ok,
         "a step text over the limit refuses");
      Assert
        (not Step_Fits (Doc, Nth_Step (1, 4), Header, Data),
         "a step text over the limit, with no doc string and no table");
   end Test_Step_Fits;

   ---------------------------------------------------------------------
   --  Several Examples blocks under one outline.
   ---------------------------------------------------------------------

   --  A block with only its header row yields no concrete scenario;
   --  the walk carries on into the blocks after it.
   Blocks_Doc : constant Lines :=
     [+"Feature: f",
      +"  Scenario Outline: o",
      +"    Given <a>",
      +"    Examples: header only",
      +"      | a |",
      +"    Examples: first",
      +"      | a |",
      +"      | 1 |",
      +"      | 2 |",
      +"    Examples: second",
      +"      | a |",
      +"      | 3 |"];

   procedure Assert_Row
     (Ref : Example_Ref; Value_Text : String; Line : Fabula.Line_Number) is
   begin
      Assert
        (Ref.Status = Row_Due, Value_Text & ": a concrete scenario is due");
      Assert
        (Concrete_Line (Doc, Ref.Data_Row) = Line,
         Value_Text
         & ": expected line"
         & Line'Image
         & ", got"
         & Concrete_Line (Doc, Ref.Data_Row)'Image);
      Assert
        (Value (Substituted (Doc, "<a>", Ref.Header_Row, Ref.Data_Row))
         = Value_Text,
         "the row's own value");
   end Assert_Row;

   procedure Test_Example_Blocks (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ref : Example_Ref;
   begin
      Load (Blocks_Doc);
      Assert (Examples_Count (Doc) = 3, "three blocks");
      Ref := First_Example (Doc, 1);
      Assert_Row (Ref, "1", 8);
      Ref := Next_Example (Doc, 1, Ref);
      Assert_Row (Ref, "2", 9);
      Ref := Next_Example (Doc, 1, Ref);
      Assert_Row (Ref, "3", 12);
      Ref := Next_Example (Doc, 1, Ref);
      Assert (Ref.Status = Ended, "three rows, then done");
   end Test_Example_Blocks;

   ---------------------------------------------------------------------
   --  Effective tags.
   ---------------------------------------------------------------------

   Tag_Doc : constant Lines :=
     [+"@f @shared",
      +"Feature: t",
      +"  @s @shared",
      +"  Scenario Outline: o",
      +"    Given x <a>",
      +"    @e @s",
      +"    Examples:",
      +"      | a |",
      +"      | 1 |",
      +"  Scenario: plain",
      +"    Given y"];

   function Tag_Text (Set : Tag_Set; I : Positive) return String
   is (Text (Doc, Tag (Doc, Set.Items (I))));

   procedure Test_Effective_Tags (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Outline : Tag_Set;
      Plain   : Tag_Set;
   begin
      Load (Tag_Doc);
      Outline := Effective_Tags (Doc, 1, Scenario (Doc, 1).Examples.First);
      Assert (Outline.Ok, "every tag range is inside the pool");
      Assert
        (Outline.Count = 4, "four distinct tags, got" & Outline.Count'Image);
      Assert (Tag_Text (Outline, 1) = "@s", "own tags first");
      Assert (Tag_Text (Outline, 2) = "@shared", "own tags first");
      Assert (Tag_Text (Outline, 3) = "@f", "then the Feature's");
      Assert (Tag_Text (Outline, 4) = "@e", "then the Examples block's");
      Assert (Contains (Doc, Outline, "@e"), "Contains sees @e");
      Assert (not Contains (Doc, Outline, "e"), "a tag keeps its '@'");
      Plain := Effective_Tags (Doc, 2, 0);
      Assert (Plain.Count = 2, "a plain scenario inherits the Feature's");
      Assert (Contains (Doc, Plain, "@shared"), "@shared");
      Assert (not Contains (Doc, Plain, "@e"), "not another block's tags");
   end Test_Effective_Tags;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Placeholders'Access, "placeholders, known and unknown");
      Register_Routine
        (T, Test_Values'Access, "an empty value, a value never rescanned");
      Register_Routine
        (T, Test_Brackets'Access, "where a placeholder starts and ends");
      Register_Routine
        (T, Test_Overflow'Access, "an expansion over the limit refuses");
      Register_Routine
        (T, Test_Concrete_Scenarios'Access, "concrete names and lines");
      Register_Routine
        (T, Test_Concrete_Count'Access, "one concrete scenario per data row");
      Register_Routine (T, Test_Step_Text'Access, "step text");
      Register_Routine (T, Test_Doc_Lines'Access, "doc lines");
      Register_Routine (T, Test_Cells'Access, "table cells");
      Register_Routine
        (T, Test_Step_Fits'Access, "a step's expansion fits or refuses");
      Register_Routine
        (T, Test_Example_Blocks'Access, "a header-only block, then two more");
      Register_Routine
        (T, Test_Effective_Tags'Access, "effective tags, deduplicated");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Expand (outline expansion)"));

end Fabula_Expand_Tests;
