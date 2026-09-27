with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Strings;             use Ada.Strings;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Ada.Text_IO;             use Ada.Text_IO;

with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast;   use Fabula.Ast;
with Fabula.Limits;
with Fabula.Parse; use Fabula.Parse;

package body Fabula_Corpus_Tests is

   use AUnit.Test_Cases.Registration;

   --  The suite runs from the crate root (alr test).
   Corpus   : constant String := "tests/data/cwt/parser/";
   Manifest : constant String := Corpus & "MANIFEST.md";

   Corpus_Files : constant := 21;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;
   P   : Parser;

   package Line_Vectors is new
     Ada.Containers.Vectors (Positive, Unbounded_String);

   --  A whole file, read and closed before any assertion can fire, so
   --  a failing routine never leaves a file open for the next one.
   function Read_Lines (Path : String) return Line_Vectors.Vector is
      File   : File_Type;
      Result : Line_Vectors.Vector;
   begin
      Open (File, In_File, Path);
      while not End_Of_File (File) loop
         Result.Append (To_Unbounded_String (Get_Line (File)));
      end loop;
      Close (File);
      return Result;
   end Read_Lines;

   --  Feeds one corpus file through Start, Feed and Finish.
   procedure Parse_File (Name : String) is
      Source : constant Line_Vectors.Vector := Read_Lines (Corpus & Name);
   begin
      Start (P, Doc);
      for Number in 1 .. Natural (Source.Length) loop
         declare
            Line : constant String := To_String (Source (Number));
         begin
            Assert
              (Line'Length <= Fabula.Limits.Max_Line_Length,
               Name & " line" & Number'Image & " is over the line limit");
            Feed (P, Doc, Line, Fabula.Source_Line (Number));
         end;
      end loop;
      Finish (P, Doc);
   end Parse_File;

   ---------------------------------------------------------------------
   --  The manifest table.
   ---------------------------------------------------------------------

   Max_Fields : constant := 10;
   type Field_Array is array (1 .. Max_Fields) of Unbounded_String;

   type Fields is record
      Items : Field_Array;
      Count : Natural := 0;
   end record;

   --  The trimmed text between each pair of consecutive '|'.
   function Split (Line : String) return Fields is
      Result : Fields;
      Bar    : Natural := 0;
   begin
      for I in Line'Range loop
         if Line (I) = '|' then
            if Bar > 0 and then Result.Count < Max_Fields then
               Result.Count := Result.Count + 1;
               Result.Items (Result.Count) :=
                 To_Unbounded_String (Trim (Line (Bar + 1 .. I - 1), Both));
            end if;
            Bar := I;
         end if;
      end loop;
      return Result;
   end Split;

   function Field (F : Fields; I : Positive) return String
   is (To_String (F.Items (I)));

   function Is_Row (F : Fields) return Boolean
   is (F.Count = Max_Fields and then Tail (Field (F, 1), 8) = ".feature");

   procedure For_Each_Row (Action : not null access procedure (F : Fields)) is
   begin
      for Line of Read_Lines (Manifest) loop
         declare
            F : constant Fields := Split (To_String (Line));
         begin
            if Is_Row (F) then
               Action (F);
            end if;
         end;
      end loop;
   end For_Each_Row;

   ---------------------------------------------------------------------
   --  Counting the document.
   ---------------------------------------------------------------------

   type Count_Kind is (Plain_Count, Outlines, Rows, Steps, Tables, Docs);
   type Counts is array (Count_Kind) of Natural;

   function Data_Rows (E : Examples_Node) return Natural
   is (if E.Rows.Last >= E.Rows.First
       then Natural (E.Rows.Last - E.Rows.First) + 1
       else 0);

   function Counted return Counts is
      Result : Counts := [others => 0];
   begin
      for S in 1 .. Scenario_Count (Doc) loop
         if Scenario (Doc, S).Kind = Plain then
            Result (Plain_Count) := Result (Plain_Count) + 1;
         else
            Result (Outlines) := Result (Outlines) + 1;
         end if;
      end loop;
      for E in 1 .. Examples_Count (Doc) loop
         Result (Rows) := Result (Rows) + Data_Rows (Examples (Doc, E));
      end loop;
      Result (Steps) := Natural (Step_Count (Doc));
      Result (Tables) := Natural (Table_Count (Doc));
      Result (Docs) := Natural (Doc_String_Count (Doc));
      return Result;
   end Counted;

   function Size (R : Step_Range) return Natural
   is (if R.Last >= R.First then Natural (R.Last - R.First) + 1 else 0);

   --  Every step belongs to the background or to one scenario.
   function Owned_Steps return Natural is
      Total : Natural := Size (Background (Doc).Steps);
   begin
      for S in 1 .. Scenario_Count (Doc) loop
         Total := Total + Size (Scenario (Doc, S).Steps);
      end loop;
      return Total;
   end Owned_Steps;

   procedure Check_Parse (F : Fields) is
      Name   : constant String := Field (F, 1);
      Got    : constant Counts := Counted;
      Column : Positive := 3;
   begin
      Assert
        (not Failed (P),
         Name
         & " must parse, refused "
         & Error (P).Kind'Image
         & " at"
         & Error (P).Line'Image);
      for K in Count_Kind loop
         Assert
           (Got (K) = Natural'Value (Field (F, Column)),
            Name & ": " & K'Image & " is" & Got (K)'Image);
         Column := Column + 1;
      end loop;
      Assert (Owned_Steps = Got (Steps), Name & ": every step has an owner");
      if Field (F, Max_Fields) = "" then
         Assert
           (Got (Plain_Count) + Got (Rows) = Natural'Value (Field (F, 9)),
            Name & ": plain + rows must equal the oracle's count");
      end if;
   end Check_Parse;

   procedure Check_Refusal (F : Fields) is
      Got : constant String :=
        "refuses " & Error (P).Kind'Image & " at line" & Error (P).Line'Image;
   begin
      Assert
        (To_Lower (Got) = To_Lower (Field (F, 2)),
         Field (F, 1) & ": expected " & Field (F, 2) & ", got " & Got);
   end Check_Refusal;

   procedure Check_Row (F : Fields) is
   begin
      Assert
        (Ada.Directories.Exists (Corpus & Field (F, 1)),
         "a manifest row names a missing file: " & Field (F, 1));
      Parse_File (Field (F, 1));
      if Field (F, 2) = "parses" then
         Check_Parse (F);
      else
         Check_Refusal (F);
      end if;
   end Check_Row;

   ---------------------------------------------------------------------
   --  Routines.
   ---------------------------------------------------------------------

   Rows_Seen : Natural := 0;

   procedure Count_Row (F : Fields) is
      pragma Unreferenced (F);
   begin
      Rows_Seen := Rows_Seen + 1;
   end Count_Row;

   Wanted : Unbounded_String;
   Found  : Boolean := False;

   procedure Match_Row (F : Fields) is
   begin
      Found := Found or else Field (F, 1) = To_String (Wanted);
   end Match_Row;

   --  Every corpus file has exactly one manifest row, and no row names
   --  a file that is not here.
   procedure Test_Coverage (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Files  : Natural := 0;
   begin
      Ada.Directories.Start_Search (Search, Corpus, "*.feature");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Files := Files + 1;
         Wanted := To_Unbounded_String (Ada.Directories.Simple_Name (Item));
         Found := False;
         For_Each_Row (Match_Row'Access);
         Assert (Found, "no manifest row for " & To_String (Wanted));
      end loop;
      Ada.Directories.End_Search (Search);
      Rows_Seen := 0;
      For_Each_Row (Count_Row'Access);
      Assert (Files = Corpus_Files, "the corpus holds" & Files'Image);
      Assert (Rows_Seen = Files, "one row per file, got" & Rows_Seen'Image);
   end Test_Coverage;

   procedure Test_Rows (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      For_Each_Row (Check_Row'Access);
   end Test_Rows;

   --  "file:row:column: value" against the file's first step table.
   procedure Check_Cell (Spec : String) is
      C1    : constant Natural := Index (Spec, ":");
      C2    : constant Natural := Index (Spec, ":", C1 + 1);
      C3    : constant Natural := Index (Spec, ":", C2 + 1);
      Row   : constant Positive := Positive'Value (Spec (C1 + 1 .. C2 - 1));
      Col   : constant Positive := Positive'Value (Spec (C2 + 1 .. C3 - 1));
      Value : constant String := Spec (C3 + 2 .. Spec'Last);
      R     : Row_Index;
   begin
      Parse_File (Spec (Spec'First .. C1 - 1));
      Assert (not Failed (P) and then Table_Count (Doc) >= 1, Spec);
      R := Table (Doc, 1).Rows.First + Row_Index (Row) - 1;
      Assert
        (Text
           (Doc,
            Cell (Doc, Table_Row (Doc, R).Cells.First + Cell_Index (Col) - 1))
         = Value,
         Spec);
   end Check_Cell;

   procedure Test_Cells (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      In_Block : Boolean := False;
      Checked  : Natural := 0;
   begin
      for Item of Read_Lines (Manifest) loop
         declare
            Line : constant String := To_String (Item);
         begin
            if In_Block and then Line /= "```" then
               Check_Cell (Line);
               Checked := Checked + 1;
            end if;
            In_Block := (In_Block and Line /= "```") or Line = "```text";
         end;
      end loop;
      Assert (Checked > 0, "the manifest lists expected cells");
   end Test_Cells;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Coverage'Access, "one manifest row per corpus file");
      Register_Routine (T, Test_Rows'Access, "every manifest row holds");
      Register_Routine (T, Test_Cells'Access, "edge_table_cell_* cell text");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("cwt parser corpus (manifest)"));

end Fabula_Corpus_Tests;
