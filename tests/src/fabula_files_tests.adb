with Ada.Directories;
with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast;
with Fabula.Frames;
with Fabula.Limits;
with Fabula.Parse;
with Fabula.Shell.Files; use Fabula.Shell.Files;

with Fabula_Fixtures;      use Fabula_Fixtures;
with Fabula_Shell_Scratch; use Fabula_Shell_Scratch;

package body Fabula_Files_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Line_Number;
   use type Fabula.Ast.Step_Handle;
   use type Fabula.Parse.Error_Kind;
   use type Fabula.Parse.Refusal;

   Corpus : constant String := "tests/data/cwt/parser";

   LF  : constant Character := ASCII.LF;
   CR  : constant Character := ASCII.CR;
   Max : constant := Fabula.Limits.Max_Line_Length;

   --  The corpus in byte order, the order Discover walks a directory in.
   Sorted_Corpus : constant Lines :=
     [+"10_continue_on_failure.feature",
      +"11_manual_fails.feature",
      +"1_first_scenario.feature",
      +"2_scenario_outline.feature",
      +"3_background.feature",
      +"4_tags.feature",
      +"5_tagged_hooks.feature",
      +"6_tables.feature",
      +"7_doc_strings.feature",
      +"8_custom_parameters.feature",
      +"9_rules.feature",
      +"edge_docstring_no_content_lines.feature",
      +"edge_examples_before_any_scenario.feature",
      +"edge_keyword_then_eof_comment.feature",
      +"edge_scenario_outline_missing_examples_key.feature",
      +"edge_step_text_escaped_quote.feature",
      +"edge_table_cell_escaped_pipe.feature",
      +"edge_table_cell_with_hash.feature",
      +"edge_table_cell_with_quotes.feature",
      +"edge_unterminated_docstring.feature",
      +"stress-tests.feature"];

   --  Documents and file lists are large records: they live at library
   --  level, never on a test routine's stack.
   Reference        : Fabula.Ast.Document;
   Reference_Parser : Fabula.Parse.Parser;
   List             : File_List;

   procedure Expect (Got, Want : Search_Status; What : String) is
   begin
      Assert
        (Got = Want, What & ": expected " & Want'Image & ", got " & Got'Image);
   end Expect;

   procedure Expect (Got, Want : Load_Status; What : String) is
   begin
      Assert
        (Got = Want, What & ": expected " & Want'Image & ", got " & Got'Image);
   end Expect;

   function Path_Of (T : Target) return String
   is (Fabula.Frames.Value (T.Path));

   function Path_At (I : Positive) return String
   is (Fabula.Frames.Value (List.Files (I).Path));

   function Trimmed (N : Natural) return String
   is (Trim (N'Image, Left));

   ---------------------------------------------------------------------
   --  Split.
   ---------------------------------------------------------------------

   procedure Test_Split (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain : constant Target := Split ("dir/a.feature");
      Two   : constant Target := Split ("dir/a.feature:4:10");
      Same  : constant Target := Split ("a.feature:007:7");
      Word  : constant Target := Split ("a.feature:x:5");
      Drive : constant Target := Split ("C:\x\a.feature:3");
   begin
      Expect (Plain.Status, Found, "no suffix");
      Assert
        (Path_Of (Plain) = "dir/a.feature" and then Plain.Lines.Count = 0,
         "the path alone");
      Expect (Two.Status, Found, "two lines");
      Assert (Path_Of (Two) = "dir/a.feature", "the path before the lines");
      Assert
        (Two.Lines.Count = 2
         and then Selects (Two.Lines, 4)
         and then Selects (Two.Lines, 10),
         "lines 4 and 10");
      Assert
        (Same.Lines.Count = 1 and then Selects (Same.Lines, 7),
         "007 and 7 are one line");
      Assert
        (Path_Of (Word) = "a.feature:x"
         and then Word.Lines.Count = 1
         and then Selects (Word.Lines, 5),
         "a group holding a letter ends the lines");
      Assert
        (Path_Of (Drive) = "C:\x\a.feature" and then Selects (Drive.Lines, 3),
         "a drive letter stays in the path");
   end Test_Split;

   procedure Test_Split_Refusals (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect (Split ("a.feature:").Status, Bad_Line_Number, "an empty group");
      Expect
        (Split ("a.feature::4").Status,
         Bad_Line_Number,
         "an empty group before a line");
      Expect (Split ("a.feature:0").Status, Bad_Line_Number, "line zero");
      Expect
        (Split ("a.feature:2147483648").Status,
         Bad_Line_Number,
         "past Positive'Last");
      Expect (Split ("a.feature:2147483647").Status, Found, "Positive'Last");
   end Test_Split_Refusals;

   --  "a.feature" followed by the lines 1 .. N.
   function With_Lines (N : Natural) return String is
      Result : Unbounded_String := To_Unbounded_String ("a.feature");
   begin
      for I in 1 .. N loop
         Append (Result, ":" & Trimmed (I));
      end loop;
      return To_String (Result);
   end With_Lines;

   procedure Test_Split_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Most : constant := Fabula.Limits.Max_Line_Selections;
      Path : constant String (1 .. Fabula.Limits.Max_Path_Length) :=
        [others => 'p'];
   begin
      Expect (Split (With_Lines (Most)).Status, Found, "the most lines");
      Expect
        (Split (With_Lines (Most + 1)).Status,
         Too_Many_Lines,
         "one line more");
      Expect (Split (Path).Status, Found, "the longest path");
      Expect (Split (Path & "q").Status, Path_Too_Long, "one character more");
      Expect
        (Split (Path & "q:3").Status, Path_Too_Long, "with a line after it");
   end Test_Split_Bounds;

   ---------------------------------------------------------------------
   --  Load.
   ---------------------------------------------------------------------

   --  Enough of a Document to tell two parses apart.
   function Shape_Of (D : Fabula.Ast.Document) return String
   is (Fabula.Ast.Scenario_Count (D)'Image
       & Fabula.Ast.Step_Count (D)'Image
       & Fabula.Ast.Table_Count (D)'Image
       & Fabula.Ast.Doc_String_Count (D)'Image
       & Fabula.Ast.Examples_Count (D)'Image
       & Fabula.Ast.Tag_Count (D)'Image
       & Fabula.Ast.Text_Used (D)'Image);

   --  Load gives the verdict the corpus suite's own feed gives.
   procedure Check_Corpus_File (Name : String) is
      R : Load_Result;
   begin
      Parse_Corpus (Name, Reference_Parser, Reference);
      Load (Corpus & "/" & Name, R);
      if Fabula.Parse.Failed (Reference_Parser) then
         Expect (R.Status, Refused, Name);
         Assert
           (R.Refusal = Fabula.Parse.Error (Reference_Parser),
            Name & ": the same refusal");
         Assert (R.Line = R.Refusal.Line, Name & ": Line names it");
      else
         Expect (R.Status, Loaded, Name);
         Assert
           (Shape_Of (Document.all) = Shape_Of (Reference),
            Name
            & ": expected"
            & Shape_Of (Reference)
            & ", got"
            & Shape_Of (Document.all));
      end if;
   end Check_Corpus_File;

   procedure Test_Load_Corpus (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for Name of Sorted_Corpus loop
         Check_Corpus_File (To_String (Name));
      end loop;
   end Test_Load_Corpus;

   procedure Test_Load_Refused_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Load_Result;
   begin
      Load (Corpus & "/edge_examples_before_any_scenario.feature", R);
      Expect (R.Status, Refused, "Examples before a scenario");
      Assert
        (R.Line = 5 and then Line_Text (R) = "  Examples:",
         "line 5 as written, got"
         & R.Line'Image
         & " """
         & Line_Text (R)
         & """");
      Load (Corpus & "/edge_unterminated_docstring.feature", R);
      Expect (R.Status, Refused, "a lone fence");
      Assert
        (R.Line = 1 and then Line_Text (R) = "```",
         "the fence, got" & R.Line'Image & " """ & Line_Text (R) & """");
   end Test_Load_Refused_Text;

   --  An open doc string refuses at end of input, naming its fence: the
   --  line text comes from an earlier line than the last one read.
   procedure Test_Load_Earlier_Line
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path  : constant String := Fresh_Dir ("load") & "/open_doc.feature";
      Fence : constant String := "      """"""";
      R     : Load_Result;
   begin
      Write_File
        (Path,
         "Feature: f"
         & LF
         & "  Scenario: s"
         & LF
         & "    Given a step"
         & LF
         & Fence
         & LF
         & "      text"
         & LF
         & "      more"
         & LF);
      Load (Path, R);
      Expect (R.Status, Refused, "an open doc string");
      Assert
        (R.Refusal.Kind = Fabula.Parse.Unterminated_Doc_String,
         "refused as " & R.Refusal.Kind'Image);
      Assert
        (R.Line = 4 and then Line_Text (R) = Fence,
         "the fence, got" & R.Line'Image & " """ & Line_Text (R) & """");
   end Test_Load_Earlier_Line;

   procedure Test_Load_Too_Long (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant String := Fresh_Dir ("load") & "/long.feature";
      Long : constant String (1 .. Max + 1) := [others => 'x'];
      R    : Load_Result;
   begin
      Write_File
        (Path,
         "Feature: f"
         & LF
         & "  Scenario: s"
         & LF
         & Long
         & LF
         & "    Given a step"
         & LF);
      Load (Path, R);
      Expect (R.Status, Too_Long, "a line one past the limit");
      Assert (R.Line = 3, "line 3, got" & R.Line'Image);
      Assert (Line_Text (R) = Long (1 .. Max), "its first Max characters");
   end Test_Load_Too_Long;

   --  CRLF line ends read as LF; a line of exactly Max characters before
   --  its CR fits; a last line with no LF still counts.
   procedure Test_Load_Line_Ends (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Dir  : constant String := Fresh_Dir ("load");
      Step : constant String := "    Given " & String'(1 .. Max - 10 => 'y');
      R    : Load_Result;
   begin
      Assert (Step'Length = Max, "the step line fills the limit");
      Write_File
        (Dir & "/crlf.feature",
         "Feature: f" & CR & LF & "  Scenario: s" & CR & LF & Step & CR & LF);
      Load (Dir & "/crlf.feature", R);
      Expect (R.Status, Loaded, "CRLF, one line at the limit");
      Assert
        (Fabula.Ast.Text
           (Document.all, Fabula.Ast.Feature (Document.all).Head.Name)
         = "f",
         "the feature name keeps no CR");
      Assert
        (Fabula.Ast.Text (Document.all, Fabula.Ast.Step (Document.all, 1).Text)
         = Step (11 .. Step'Last),
         "the step text keeps no CR");
      Write_File
        (Dir & "/no_lf.feature",
         "Feature: f" & LF & "  Scenario: s" & LF & "    Given a step");
      Load (Dir & "/no_lf.feature", R);
      Expect (R.Status, Loaded, "no final LF");
      Assert (Fabula.Ast.Step_Count (Document.all) = 1, "the last line");
   end Test_Load_Line_Ends;

   --  At_End tells the two refusal origins apart: a mid-file prose error
   --  comes from Feed, a dangling Rule at end of input from Finish.
   procedure Test_Load_At_End (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Path : constant String := Fresh_Dir ("load") & "/dangling_rule.feature";
      R    : Load_Result;
   begin
      Load (Corpus & "/edge_examples_before_any_scenario.feature", R);
      Expect (R.Status, Refused, "Examples before a scenario");
      Assert (not R.At_End, "a mid-file prose error comes from Feed");
      Write_File (Path, "Feature: f" & LF & "  Rule: r" & LF);
      Load (Path, R);
      Expect (R.Status, Refused, "a Rule with no scenario after it");
      Assert
        (R.Refusal.Kind = Fabula.Parse.Expected_Scenario,
         "refused as " & R.Refusal.Kind'Image);
      Assert (R.At_End, "a dangling Rule at end of input comes from Finish");
   end Test_Load_At_End;

   procedure Test_Load_Unreadable (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Dir : constant String := Fresh_Dir ("load");
      R   : Load_Result;
   begin
      Write_File (Dir & "/empty.feature", "");
      Load (Dir & "/empty.feature", R);
      Expect (R.Status, Empty, "an empty file");
      Load (Dir & "/missing.feature", R);
      Expect (R.Status, Unreadable, "a missing file");
      Load (Dir, R);
      Expect (R.Status, Unreadable, "a directory");
   end Test_Load_Unreadable;

   ---------------------------------------------------------------------
   --  Line reading.  Load reads a file in chunks of Chunk bytes into a
   --  line buffer of Max + 1 characters; these pin what it makes of
   --  line lengths and line ends at both bounds.
   ---------------------------------------------------------------------

   Chunk : constant := Read_Chunk_Bytes;

   --  A Rule with no scenario after it refuses at end of input and names
   --  the file's last line, so Load counts every line and Fetch_Line
   --  reads them all again to quote the last one.
   Dangling : constant String := "Feature: f" & LF & "  Rule: r" & LF;

   --  A comment line of N characters, or an empty line when N is 0.  Its
   --  letters cycle, so a byte lost or read twice shows in the text.
   function Comment (N : Natural) return String
   is (if N = 0
       then ""
       else
         "#"
         & String'
             [for I in 1 .. N - 1 =>
                Character'Val (Character'Pos ('a') + I mod 26)]);

   --  Comment lines of at most Width bytes each, LF included, that fill
   --  exactly Bytes bytes.
   Width : constant := 1_000;

   function Filler (Bytes : Natural) return String is
   begin
      if Bytes = 0 then
         return "";
      elsif Bytes <= Width then
         return Comment (Bytes - 1) & LF;
      else
         return Comment (Width - 1) & LF & Filler (Bytes - Width);
      end if;
   end Filler;

   --  Dangling, then filler up to file offset At_Byte (1-based), where
   --  the next line starts.
   function Up_To (At_Byte : Positive) return String
   is (Dangling & Filler (At_Byte - 1 - Dangling'Length));

   --  The lines in Content as a line reader counts them: one per LF,
   --  and one more for bytes after the last LF.
   function Lines_In (Content : String) return Natural
   is (Ada.Strings.Fixed.Count (Content, String'(1 => LF))
       + (if Content'Length > 0 and then Content (Content'Last) /= LF
          then 1
          else 0));

   --  Loads Content, which ends inside a dangling Rule, and expects the
   --  refusal at its last line, quoted as Text.
   procedure Expect_Last_Line (Content, Text, What : String) is
      Path : constant String := Fresh_Dir ("lines") & "/probe.feature";
      R    : Load_Result;
   begin
      Write_File (Path, Content);
      Load (Path, R);
      Expect (R.Status, Refused, What);
      Assert
        (R.At_End and then R.Line = Fabula.Line_Number (Lines_In (Content)),
         What & ": the last line, got" & R.Line'Image);
      Assert
        (Line_Text (R) = Text,
         What & ": its text, got """ & Line_Text (R) & """");
   end Expect_Last_Line;

   --  Loads Before & Long & After and expects Long, the line after
   --  Before, to be too long, its first Max characters kept.
   procedure Expect_Too_Long (Before, Long, After, What : String) is
      Path : constant String := Fresh_Dir ("lines") & "/long.feature";
      R    : Load_Result;
   begin
      Write_File (Path, Before & Long & After);
      Load (Path, R);
      Expect (R.Status, Too_Long, What);
      Assert
        (R.Line = Fabula.Line_Number (Lines_In (Before) + 1),
         What & ": its line, got" & R.Line'Image);
      Assert
        (Line_Text (R) = Long (Long'First .. Long'First + Max - 1),
         What & ": its first Max characters");
   end Expect_Too_Long;

   --  Lines at the buffer's bound, away from any chunk boundary.
   procedure Test_Read_Lengths (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      After : constant String := LF & "# after" & LF;
   begin
      Expect_Last_Line
        (Dangling & Comment (Max) & LF, Comment (Max), "Max characters");
      Expect_Last_Line
        (Dangling & Comment (Max), Comment (Max), "Max, no final LF");
      Expect_Last_Line
        (Dangling & Comment (Max) & CR & LF, Comment (Max), "Max and CRLF");
      Expect_Last_Line
        (Dangling & Comment (Max) & CR, Comment (Max), "Max and a last CR");
      Expect_Too_Long (Dangling, Comment (Max + 1), After, "Max + 1");
      Expect_Too_Long (Dangling, Comment (Max + 1), "", "Max + 1, no LF");
      Expect_Too_Long
        (Dangling, Comment (Max + 1), CR & After, "Max + 1 and CRLF");
      Expect_Too_Long (Dangling, Comment (Max + 1), "" & CR, "Max + 1, CR");
      Expect_Too_Long
        (Dangling, Comment (Max) & CR & CR, After, "Max, then two CRs");
      Expect_Too_Long
        (Dangling, Comment (3 * Chunk), After, "a line over three chunks");
   end Test_Read_Lengths;

   --  Line ends and lines that fall on a chunk boundary: byte Chunk is
   --  the first chunk's last byte.
   procedure Test_Read_Chunk_Ends (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Line : constant String := Comment (100);
      Next : constant String := "# next";
   begin
      Expect_Last_Line
        (Up_To (Chunk - 100) & Line & CR & LF, Line, "CR at the chunk end");
      Expect_Last_Line
        (Up_To (Chunk - 100) & Line & CR, Line, "CR at the chunk end, EOF");
      Expect_Last_Line
        (Up_To (Chunk - 101) & Line & CR & LF, Line, "LF at the chunk end");
      Expect_Last_Line
        (Up_To (Chunk - 99) & Line & CR & LF, Line, "CR after the chunk");
      Expect_Last_Line
        (Up_To (Chunk - 100) & Line & LF & Next & LF,
         Next,
         "LF at the chunk end, a line after");
      Expect_Last_Line
        (Up_To (Chunk - 99) & Line & LF & Next & LF,
         Next,
         "a line that fills the chunk");
      Expect_Last_Line
        (Up_To (2 * Chunk - 100) & Line & CR & LF,
         Line,
         "CR at the second chunk's end");
      Expect_Last_Line
        (Up_To (Chunk - 150) & Comment (300),
         Comment (300),
         "a last line over two chunks");
      Expect_Last_Line
        (Up_To (Chunk - 150) & Comment (300) & CR & LF & Next & LF,
         Next,
         "a line over two chunks, a line after");
   end Test_Read_Chunk_Ends;

   --  The buffer's bound and a chunk boundary together: the line's
   --  character Max + 1 is the first chunk's last byte, or the next.
   procedure Test_Read_Both_Bounds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      After : constant String := LF & "# after" & LF;
   begin
      Expect_Last_Line
        (Up_To (Chunk - Max) & Comment (Max) & CR & LF,
         Comment (Max),
         "Max, then CR at the chunk end");
      Expect_Last_Line
        (Up_To (Chunk - Max + 1) & Comment (Max) & CR & LF,
         Comment (Max),
         "Max at the chunk end, then CR");
      Expect_Last_Line
        (Up_To (Chunk - Max + 1) & Comment (Max) & CR,
         Comment (Max),
         "Max at the chunk end, then a last CR");
      Expect_Too_Long
        (Up_To (Chunk - Max), Comment (Max + 1), After, "Max + 1, then LF");
      Expect_Too_Long
        (Up_To (Chunk - Max), Comment (Max + 2), After, "Max + 2 over it");
      Expect_Too_Long
        (Up_To (Chunk - Max), Comment (Max + 1), CR & After, "then CRLF");
      Expect_Too_Long
        (Up_To (Chunk - Max), Comment (Max + 1), "", "then end of file");
   end Test_Read_Both_Bounds;

   --  Short line ends: an empty last line, a lone CR, a CR that is not
   --  the last character, and bytes read as they are.
   procedure Test_Read_Line_Ends (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raw : constant String :=
        "# "
        & ASCII.NUL
        & Character'Val (16#E9#)
        & Character'Val (16#80#)
        & Character'Val (16#FF#);
   begin
      Expect_Last_Line (Dangling & "# a" & LF, "# a", "a final LF");
      Expect_Last_Line (Dangling & "# a" & LF & LF, "", "an empty last line");
      Expect_Last_Line (Dangling & CR, "", "a lone CR");
      Expect_Last_Line (Dangling & CR & LF, "", "a lone CRLF");
      Expect_Last_Line
        (Dangling & "# a" & CR & CR & LF, "# a" & CR, "one CR dropped");
      Expect_Last_Line
        (Dangling & "# a" & CR & "b" & LF, "# a" & CR & "b", "a CR within");
      Expect_Last_Line (Dangling & Raw & LF, Raw, "NUL and upper-half bytes");
   end Test_Read_Line_Ends;

   --  A file of one empty line holds a line; a file of no bytes is Empty.
   procedure Test_Read_Tiny (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Dir  : constant String := Fresh_Dir ("tiny");
      R    : Load_Result;
      Kept : Load_Status;
   begin
      Write_File (Dir & "/lf.feature", "" & LF);
      Load (Dir & "/lf.feature", R);
      Kept := R.Status;
      Assert (Kept /= Empty, "one LF is a line, got " & Kept'Image);
      Write_File (Dir & "/cr.feature", "" & CR);
      Load (Dir & "/cr.feature", R);
      Expect (R.Status, Kept, "one CR reads as one LF");
      Write_File (Dir & "/crlf.feature", CR & LF);
      Load (Dir & "/crlf.feature", R);
      Expect (R.Status, Kept, "one CRLF reads as one LF");
      Write_File (Dir & "/empty.feature", "");
      Load (Dir & "/empty.feature", R);
      Expect (R.Status, Empty, "no bytes");
   end Test_Read_Tiny;

   ---------------------------------------------------------------------
   --  Discover.
   ---------------------------------------------------------------------

   procedure Test_Discover_Corpus (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Search_Status;
   begin
      List.Count := 0;
      Discover (Corpus, List, S);
      Expect (S, Found, "the corpus directory");
      Assert
        (List.Count = Sorted_Corpus'Length,
         "every corpus file, got" & List.Count'Image);
      for I in Sorted_Corpus'Range loop
         Assert
           (Path_At (I) = Corpus & "/" & To_String (Sorted_Corpus (I)),
            "file" & I'Image & " is " & Path_At (I));
         Assert (List.Files (I).Lines.Count = 0, "no line selections");
      end loop;
   end Test_Discover_Corpus;

   --  A small tree, made in a scrambled order: files, subdirectories,
   --  and names a search must pass over.
   Tree_Files : constant Lines :=
     [+"b.feature",
      +"a.feature",
      +"C.feature",
      +"10.feature",
      +"2.feature",
      +"_under.feature",
      +"aa/x.feature",
      +"sub/z.feature",
      +"sub/deeper/y.feature",
      +"notes.txt",
      +"x.feature.bak",
      +"Upper.FEATURE",
      +"dirfeat.feature/inner.feature",
      +".feature"];

   --  What Discover gives for it: byte order, subdirectories walked
   --  where they sort, only names ending in ".feature" after a stem.
   Tree_Order : constant Lines :=
     [+"10.feature",
      +"2.feature",
      +"C.feature",
      +"_under.feature",
      +"a.feature",
      +"aa/x.feature",
      +"b.feature",
      +"dirfeat.feature/inner.feature",
      +"sub/deeper/y.feature",
      +"sub/z.feature"];

   function Make_Tree return String is
      Tree : constant String := Fresh_Dir ("tree");
   begin
      for Rel of Tree_Files loop
         declare
            Full : constant String := Tree & "/" & To_String (Rel);
         begin
            Ada.Directories.Create_Path
              (Ada.Directories.Containing_Directory (Full));
            Write_File (Full, "Feature: " & To_String (Rel) & LF);
         end;
      end loop;
      return Tree;
   end Make_Tree;

   procedure Test_Discover_Tree (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : constant String := Make_Tree;
      S    : Search_Status;
   begin
      List.Count := 0;
      Discover (Tree, List, S);
      Expect (S, Found, "the tree");
      Assert
        (List.Count = Tree_Order'Length,
         "the tree's feature files, got" & List.Count'Image);
      for I in Tree_Order'Range loop
         Assert
           (Path_At (I) = Tree & "/" & To_String (Tree_Order (I)),
            "file" & I'Image & " is " & Path_At (I));
      end loop;
      List.Count := 0;
      Discover (Tree & "/:4", List, S);
      Expect (S, Found, "a directory with a slash and a line");
      Assert
        (Path_At (1) = Tree & "/10.feature", "one separator: " & Path_At (1));
      Assert
        (List.Files (1).Lines.Count = 0, "a directory drops its selection");
   end Test_Discover_Tree;

   procedure Test_Discover_Arguments
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tree : constant String := Make_Tree;
      S    : Search_Status;
   begin
      List.Count := 0;
      Discover (Tree & "/a.feature:3:1", List, S);
      Expect (S, Found, "a file with lines");
      Assert
        (List.Count = 1 and then Path_At (1) = Tree & "/a.feature",
         "the file itself");
      Assert
        (List.Files (1).Lines.Count = 2
         and then Selects (List.Files (1).Lines, 3)
         and then Selects (List.Files (1).Lines, 1),
         "lines 3 and 1");
      Discover (Tree & "/notes.txt", List, S);
      Expect (S, Not_Feature, "a text file");
      Discover (Tree & "/missing.feature", List, S);
      Expect (S, Missing, "a missing file");
      Discover (Tree & "/missing_dir:4", List, S);
      Expect (S, Missing, "a missing path with a line");
      Discover (Tree & "/a.feature:", List, S);
      Expect (S, Bad_Line_Number, "a bad selection");
      Assert (List.Count = 1, "failed calls leave the list alone");
      Discover (Tree & "/a.feature", List, S);
      Assert
        (S = Found and then List.Count = 2, "a file named twice runs twice");
   end Test_Discover_Arguments;

   procedure Test_Discover_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Room : constant := Fabula.Limits.Max_Features_Per_Run - 9;
      Tree : constant String := Make_Tree;
      Deep : Unbounded_String := To_Unbounded_String (Fresh_Dir ("deep"));
      S    : Search_Status;
   begin
      List.Count := Room;
      Discover (Tree, List, S);
      Expect (S, Too_Many_Files, "one file past the limit");
      Assert (List.Count = Room, "the list is left as it was");
      List.Count := Room - 1;
      Discover (Tree, List, S);
      Expect (S, Found, "exactly full");
      for Level in 2 .. Fabula.Limits.Max_Search_Depth loop
         Append (Deep, "/d");
      end loop;
      Ada.Directories.Create_Path (To_String (Deep));
      Write_File (To_String (Deep) & "/a.feature", "Feature: deep" & LF);
      List.Count := 0;
      Discover (Fabula_Shell_Scratch.Root & "/deep", List, S);
      Expect (S, Found, "the deepest level searched");
      Assert (List.Count = 1, "its file");
      Ada.Directories.Create_Path (To_String (Deep) & "/d");
      Discover (Fabula_Shell_Scratch.Root & "/deep", List, S);
      Expect (S, Too_Deep, "one level more");
      Assert (List.Count = 1, "left as it was");
   end Test_Discover_Bounds;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Split'Access, "Split reads line selections");
      Register_Routine
        (T, Test_Split_Refusals'Access, "Split refuses bad line numbers");
      Register_Routine (T, Test_Split_Bounds'Access, "Split's two bounds");
      Register_Routine
        (T, Test_Load_Corpus'Access, "Load matches the corpus verdicts");
      Register_Routine
        (T, Test_Load_Refused_Text'Access, "a refusal keeps its line text");
      Register_Routine
        (T, Test_Load_Earlier_Line'Access, "a refusal at an earlier line");
      Register_Routine
        (T, Test_Load_Too_Long'Access, "an overlong line is refused");
      Register_Routine (T, Test_Load_Line_Ends'Access, "CRLF and a last line");
      Register_Routine
        (T, Test_Load_At_End'Access, "At_End tells Feed and Finish apart");
      Register_Routine
        (T, Test_Load_Unreadable'Access, "empty, missing, a directory");
      Register_Routine
        (T, Test_Read_Lengths'Access, "line lengths at the buffer's bound");
      Register_Routine
        (T, Test_Read_Chunk_Ends'Access, "line ends at a chunk boundary");
      Register_Routine
        (T, Test_Read_Both_Bounds'Access, "the buffer's bound on a boundary");
      Register_Routine
        (T, Test_Read_Line_Ends'Access, "short line ends and raw bytes");
      Register_Routine
        (T, Test_Read_Tiny'Access, "one-byte files and an empty one");
      Register_Routine
        (T, Test_Discover_Corpus'Access, "the corpus in byte order");
      Register_Routine
        (T, Test_Discover_Tree'Access, "a tree: order, recursion, filter");
      Register_Routine
        (T, Test_Discover_Arguments'Access, "file arguments and refusals");
      Register_Routine
        (T, Test_Discover_Bounds'Access, "the file and depth bounds");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Shell.Files"));

end Fabula_Files_Tests;
