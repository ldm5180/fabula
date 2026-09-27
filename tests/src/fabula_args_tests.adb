with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Args;    use Fabula.Args;
with Fabula.Ast;     use Fabula.Ast;
with Fabula.Expand;
with Fabula.Expressions;
with Fabula.Numbers; use Fabula.Numbers;
with Fabula.Parse;   use Fabula.Parse;

with Fabula_Fixtures; use Fabula_Fixtures;

package body Fabula_Args_Tests is

   use AUnit.Test_Cases.Registration;
   use type Integer_Reads.Read;
   use type Long_Reads.Read;
   use type Real_Reads.Read;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.  The runner hands a List this
   --  reference; the Document must outlive every List made from it.
   Doc     : aliased Document;
   P       : Parser;
   Doc_Ref : constant Document_Access := Doc'Access;

   LF : constant String := [1 => ASCII.LF];

   No_Captures : constant Fabula.Expressions.Capture_List :=
     (Count => 0, Items => <>);

   Big_Long : constant Long_Long_Integer := 9_000_000_000;

   --  Eleven nines: past Integer'Last, well inside Long_Long_Integer.
   Eleven_Nines : constant Long_Long_Integer := 99_999_999_999;

   procedure Load (Name : String) is
   begin
      Parse_Corpus (Name, P, Doc);
      Assert (not Failed (P), Name & " must parse");
   end Load;

   --  The List for Pattern matched against Text, captures only.
   function Matched (Pattern, Text : String) return List is
      Compiled : constant Fabula.Expressions.Compiled :=
        Fabula.Expressions.Compile (Pattern);
      Result   : constant Fabula.Expressions.Step_Match :=
        Fabula.Expressions.Match (Compiled, Text);
   begin
      Assert (Fabula.Expressions.Valid (Compiled), Pattern & " must compile");
      Assert (Result.Found, Pattern & " must match " & Text);
      return Make (Text, Result.Captures);
   end Matched;

   --  Step N of scenario S, its doc string and table attached, and the
   --  Examples row of Ref when the scenario is an outline.
   function Step_Args
     (S : Scenario_Index; N : Positive; Ref : Fabula.Expand.Example_Ref)
      return List
   is
      Node : constant Step_Node :=
        Step (Doc, Scenario (Doc, S).Steps.First + Step_Handle (N) - 1);
      A    : List := Make (Text (Doc, Node.Text), No_Captures);
   begin
      Attach (A, Doc_Ref, Node.Doc, Node.Table);
      if Ref.Block /= 0 then
         Set_Example (A, Ref.Header_Row, Ref.Data_Row);
      end if;
      return A;
   end Step_Args;

   function Plain_Step (S : Scenario_Index; N : Positive) return List
   is (Step_Args (S, N, (others => <>)));

   ---------------------------------------------------------------------
   --  Captures.
   ---------------------------------------------------------------------

   procedure Test_Captures (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : constant List :=
        Matched
          ("I place {int} x {string} in {word} at {float} for {long} with {}",
           "I place 3 x ""pen"" in box at -.5 for 9000000000 with the rest");
   begin
      Assert (Count (A) = 6, "six captures, got" & Count (A)'Image);
      Assert (Int (A, 1) = Integer_Reads.Success (3), "1: {int}");
      Assert (Text (A, 2) = "pen", "2: {string} without its quotes");
      Assert (Word (A, 3) = "box", "3: {word}");
      Assert
        (Real (A, 4) = Real_Reads.Success (-0.5),
         "4: {float} with no leading digit");
      Assert
        (Long (A, 5) = Long_Reads.Success (Big_Long),
         "5: {long} past Integer'Last");
      Assert (Text (A, 6) = "the rest", "6: {} to the end");
      Assert (not Has_Doc (A) and then not Has_Table (A), "no doc, no table");
   end Test_Captures;

   --  Readers convert by the type the caller asks for.
   procedure Test_Caller_Types (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : constant List := Matched ("{double} and {int}", "1.25 and -7");
   begin
      Assert (Real (A, 1) = Real_Reads.Success (1.25), "a {double}");
      Assert (Int (A, 2) = Integer_Reads.Success (-7), "a negative {int}");
      Assert
        (Long (A, 2) = Long_Reads.Success (-7),
         "the same capture read as a Long");
      Assert (Real (A, 2) = Real_Reads.Success (-7.0), "and as a Real");
      Assert (Text (A, 1) = "1.25", "and as text");
   end Test_Caller_Types;

   --  A read that cannot hold the capture is a failed result, never an
   --  exception.  A {word} of digits reads as a number, as the reference
   --  interpreter's own conversion does.
   procedure Test_Cross_Type (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : constant List :=
        Matched
          ("{float} then {word} then {word} then {int}",
           "1.5 then 7 then seven then 99999999999");
   begin
      Assert
        (Int (A, 1) = Integer_Reads.Failure (Malformed),
         "a {float} read as an Int");
      Assert
        (Long (A, 1) = Long_Reads.Failure (Malformed),
         "a {float} read as a Long");
      Assert (Int (A, 2) = Integer_Reads.Success (7), "a {word} of digits");
      Assert
        (Int (A, 3) = Integer_Reads.Failure (Malformed),
         "a {word} of letters");
      Assert
        (Real (A, 3) = Real_Reads.Failure (Malformed),
         "a {word} of letters read as a Real");
      Assert
        (Int (A, 4) = Integer_Reads.Failure (Out_Of_Range),
         "an {int} past Integer'Last");
      Assert
        (Long (A, 4) = Long_Reads.Success (Eleven_Nines),
         "the same {int} read as a Long");
   end Test_Cross_Type;

   --  A {word} or {} capture of exactly two double quotes reads as the
   --  empty string, as an empty Examples value substitutes to them.
   procedure Test_Empty_Quotes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : constant List := Matched ("{word} then {}", """"" then """"");
      B : constant List := Matched ("say {string}", "say """"");
   begin
      Assert (Word (A, 1) = "", "a {word} of two quotes");
      Assert (Text (A, 2) = "", "a {} of two quotes");
      Assert (Text (B, 1) = "", "an empty {string}");
   end Test_Empty_Quotes;

   ---------------------------------------------------------------------
   --  Doc strings.
   ---------------------------------------------------------------------

   procedure Test_Doc_String (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : List;
   begin
      Load ("7_doc_strings.feature");
      A := Plain_Step (1, 1);
      Assert (Has_Doc (A), "the step owns a doc string");
      Assert (Doc_Line_Count (A) = 2, "two lines");
      Assert (Doc_Line (A, 1) = "This is a docstring with quotes", "line 1");
      Assert (Doc_Line (A, 2) = "after a step", "line 2");
      Assert
        (Doc_String (A)
         = "This is a docstring with quotes" & LF & "after a step",
         "the lines joined by LF, got """ & Doc_String (A) & """");
      Assert (Doc_Type (A) = "", "no content type");
      A := Plain_Step (3, 1);
      Assert
        (Doc_Line (A, 1) = "This is a docstring", "trailing blank trimmed");
      Assert
        (Doc_Line (A, 3) = "as std::vector<std::string>",
         "a plain scenario substitutes nothing");
      A := Plain_Step (4, 2);
      Assert (Doc_Type (A) = "json", "a content type");
      Assert
        (Doc_String (A)
         = "{ ""value_usd"": 250, ""contents"": ""electronics"" }",
         "a one-line doc string");
      Assert (not Has_Doc (Plain_Step (1, 2)), "a step with no doc string");
   end Test_Doc_String;

   procedure Test_Doc_Outline (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Ref : Fabula.Expand.Example_Ref;
   begin
      Load ("7_doc_strings.feature");
      Ref := Fabula.Expand.First_Example (Doc, 5);
      Assert
        (Doc_String (Step_Args (5, 2, Ref))
         = "Ship to: Berlin, Germany. Barcode template: <barcode>",
         "the first row substituted, got "
         & Doc_String (Step_Args (5, 2, Ref)));
      Ref := Fabula.Expand.Next_Example (Doc, 5, Ref);
      Assert
        (Doc_Line (Step_Args (5, 2, Ref), 1)
         = "Ship to: Tokyo, Japan. Barcode template: <barcode>",
         "the second row substituted");
      Load ("edge_docstring_no_content_lines.feature");
      Assert (Has_Doc (Plain_Step (1, 1)), "a doc string with no lines");
      Assert (Doc_Line_Count (Plain_Step (1, 1)) = 0, "has none");
      Assert (Doc_String (Plain_Step (1, 1)) = "", "and joins to nothing");
   end Test_Doc_Outline;

   ---------------------------------------------------------------------
   --  Tables: raw, hashes, rows_hash.
   ---------------------------------------------------------------------

   procedure Test_Raw (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : List;
   begin
      Load ("6_tables.feature");
      A := Plain_Step (1, 2);
      Assert (Has_Table (A), "the step owns a table");
      Assert (Row_Count (A) = 3, "three rows, got" & Row_Count (A)'Image);
      Assert (Col_Count (A) = 2, "two columns");
      Assert (Cell (A, 1, 1) = "apple", "(1, 1)");
      Assert (Cell (A, 2, 1) = "strawberry", "(2, 1)");
      Assert (Cell (A, 3, 2) = "5", "(3, 2)");
      Assert
        (Cell_Int (A, 2, 2) = Integer_Reads.Success (3),
         "(2, 2) as an integer");
      Assert
        (Cell_Int (A, 1, 1) = Integer_Reads.Failure (Malformed),
         "(1, 1) is not an integer");
      Assert (not Has_Table (Plain_Step (1, 1)), "a step with no table");
   end Test_Raw;

   procedure Test_Hashes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : List;
   begin
      Load ("6_tables.feature");
      A := Plain_Step (6, 2);
      Assert (Has_Column (A, "ITEM"), "ITEM heads a column");
      Assert (not Has_Column (A, "apple"), "a data cell is not a key");
      Assert (Hash_Value (A, 1, "ITEM") = "apple", "data row 1");
      Assert (Hash_Value (A, 2, "QUANTITY") = "6", "data row 2");
      Load ("edge_table_cell_with_hash.feature");
      A := Plain_Step (1, 1);
      Assert (Hash_Value (A, 1, "#1") = "issue #7", "a key with a hash");
      Assert
        (Hash_Value (A, 2, "leading hash") = "inside word", "second column");
   end Test_Hashes;

   procedure Test_Rows_Hash (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : List;
   begin
      Load ("6_tables.feature");
      A := Plain_Step (8, 2);
      Assert (Col_Count (A) = 2, "a two-column table");
      Assert (Pair_Value (A, "ITEM") = "really good apples", "ITEM");
      Assert (Pair_Value (A, "QUANTITY") = "3", "QUANTITY");
      Assert
        (not Has_Pair (A, "really good apples"),
         "column 2 holds values, not keys");
      Load ("edge_table_cell_with_quotes.feature");
      A := Plain_Step (1, 1);
      Assert (Pair_Value (A, "[""x = 1""]") = "plain", "a quoted key");
      Assert (Pair_Value (A, """unterminated") = "odd quote", "an odd quote");
      Assert
        (Hash_Value (A, 1, "[""x = 1""]") = "[""m 7"", ""eval n""]",
         "the same table as hashes");
      Load ("edge_table_cell_escaped_pipe.feature");
      Assert
        (Pair_Value (Plain_Step (1, 1), "a\|b") = "escaped pipe",
         "an escaped pipe stays in its key");
   end Test_Rows_Hash;

   procedure Test_Table_Outline (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ref : Fabula.Expand.Example_Ref;
      A   : List;
   begin
      Load ("6_tables.feature");
      Ref := Fabula.Expand.First_Example (Doc, 5);
      A := Step_Args (5, 1, Ref);
      Assert (Cell (A, 1, 1) = "pen", "<item 1> in row 1");
      Assert
        (Cell_Int (A, 2, 2) = Integer_Reads.Success (3), "<count 2> in row 2");
      Ref := Fabula.Expand.Next_Example (Doc, 5, Ref);
      Assert (Cell (Step_Args (5, 1, Ref), 2, 1) = "table", "the next row");
      Ref := Fabula.Expand.First_Example (Doc, 7);
      A := Step_Args (7, 2, Ref);
      Assert (Hash_Value (A, 1, "ITEM") = """shirt""", "a hashes outline");
      Ref := Fabula.Expand.Next_Example (Doc, 7, Ref);
      Assert
        (Hash_Value (Step_Args (7, 2, Ref), 1, "QUANTITY") = "100",
         "its second row");
   end Test_Table_Outline;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Captures'Access, "every reader, left to right from 1");
      Register_Routine
        (T, Test_Caller_Types'Access, "the caller's type decides");
      Register_Routine
        (T, Test_Cross_Type'Access, "a read the capture cannot fill fails");
      Register_Routine
        (T, Test_Empty_Quotes'Access, "two quotes read as empty");
      Register_Routine (T, Test_Doc_String'Access, "doc string views");
      Register_Routine
        (T, Test_Doc_Outline'Access, "doc strings in an outline, and empty");
      Register_Routine (T, Test_Raw'Access, "table: raw view");
      Register_Routine (T, Test_Hashes'Access, "table: hashes view");
      Register_Routine (T, Test_Rows_Hash'Access, "table: rows_hash view");
      Register_Routine
        (T, Test_Table_Outline'Access, "tables in an outline substitute");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Args (a matched step's arguments)"));

end Fabula_Args_Tests;
