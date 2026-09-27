with AUnit.Assertions;      use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Ast;   use Fabula.Ast;
with Fabula.Limits;
with Fabula.Parse; use Fabula.Parse;
with Fabula.Scan;

package body Fabula_Parse_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Scan.Fence_Kind;
   use type Fabula.Line_Number;
   use type Doc_Line_Range;
   use type Examples_Row_Range;
   use type Row_Range;
   use type Tag_Range;

   function "+" (Source : String) return Unbounded_String
   renames To_Unbounded_String;

   type Lines is array (Positive range <>) of Unbounded_String;

   Q3 : constant String := [1 .. 3 => '"'];
   B3 : constant String := [1 .. 3 => '`'];
   HT : constant Character := ASCII.HT;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;
   P   : Parser;

   procedure Run (Source : Lines) is
   begin
      Start (P, Doc);
      for I in Source'Range loop
         Feed (P, Doc, To_String (Source (I)), Fabula.Source_Line (I));
      end loop;
      Finish (P, Doc);
   end Run;

   function Str (S : Fabula.Ast.Slice) return String
   is (Text (Doc, S));

   function Outcome return String
   is (Error (P).Kind'Image & " at" & Error (P).Line'Image);

   procedure Assert_Parses (What : String) is
   begin
      Assert (not Failed (P), What & ": must parse, got " & Outcome);
   end Assert_Parses;

   procedure Assert_Refuses
     (Kind : Error_Kind; Line : Fabula.Line_Number; What : String) is
   begin
      Assert
        (Error (P) = (Kind, Line),
         What
         & ": expected "
         & Kind'Image
         & " at"
         & Line'Image
         & ", got "
         & Outcome);
   end Assert_Refuses;

   --  Either fence kind closes either opener; content lines are
   --  trimmed on both sides; the content type keeps leading blanks.
   procedure Test_Doc_String_Fences
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"  Scenario: s",
          +"    Given a",
          +("    " & Q3 & "  json  "),
          +"      x  ",
          +(HT & " y" & HT),
          +("    " & B3),
          +"    Then b"]);
      Assert_Parses ("a cross-fence doc string");
      Assert (Step_Count (Doc) = 2, "the step after the doc string parses");
      Assert (Step (Doc, 1).Doc = 1, "the first step owns the doc string");
      Assert (Doc_String (Doc, 1).Fence = Fabula.Scan.Quotes, "opener kind");
      Assert (Doc_String (Doc, 1).Line = 4, "opening line");
      Assert
        (Str (Doc_String (Doc, 1).Content_Type) = "  json",
         "content type keeps leading blanks, drops trailing ones");
      Assert (Doc_String (Doc, 1).Lines = (1, 2), "two content lines");
      Assert (Str (Doc_Line (Doc, 1)) = "x", "both-side trim, spaces");
      Assert (Str (Doc_Line (Doc, 2)) = "y", "both-side trim, tabs");
      Assert (Str (Step (Doc, 2).Text) = "b", "the next step");
   end Test_Doc_String_Fences;

   --  A fence run anywhere on a content line closes the doc string;
   --  the text before it is dropped, text after it is refused.
   procedure Test_Closing_Runs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Head : constant Lines :=
        [+"Feature: f", +"Scenario: s", +"Given a", +("  " & Q3)];
   begin
      Run (Head & [+"keep", +("drop " & Q3), +"Then b"]);
      Assert_Parses ("a closing run after text");
      Assert (Doc_String (Doc, 1).Lines = (1, 1), "only the full line");
      Assert (Str (Doc_Line (Doc, 1)) = "keep", "the kept line");
      Assert (Step_Count (Doc) = 2, "parsing resumes after the close");
      Run (Head & [+("say " & Q3 & "hi" & Q3 & " there")]);
      Assert_Refuses (Expected_Scenario, 5, "text after a closing run");
      Run (Head & [+"body", +(Q3 & " trailing")]);
      Assert_Refuses (Expected_Scenario, 6, "a closing fence with text");
      Run (Head & [+"body", +(Q3 & "json")]);
      Assert_Refuses (Expected_Scenario, 6, "a content type on a closer");
   end Test_Closing_Runs;

   procedure Test_One_Line_Doc (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Head : constant Lines := [+"Feature: f", +"Scenario: s", +"Given a"];
   begin
      Run (Head & [+("  " & Q3 & "x" & Q3)]);
      Assert_Parses ("a one-line doc string");
      Assert (Step (Doc, 1).Doc = 1, "the step owns it");
      Assert
        (Doc_String (Doc, 1).Lines.Last < Doc_String (Doc, 1).Lines.First,
         "no content lines");
      Assert
        (Str (Doc_String (Doc, 1).Content_Type) = "x" & Q3,
         "the reference interpreter's content type for it");
      Run (Head & [+(Q3 & "x" & Q3 & " y")]);
      Assert_Refuses (Expected_Scenario, 4, "text after a one-line doc");
   end Test_One_Line_Doc;

   procedure Test_Unterminated_Doc
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run ([+"Feature: f", +"Scenario: s", +"Given a", +Q3, +"one", +"two"]);
      Assert_Refuses
        (Unterminated_Doc_String, 4, "an open doc string at end of input");
      Run ([+Q3, +"abc", +Q3, +"Feature: f"]);
      Assert_Refuses
        (Expected_Feature, 3, "a doc string before the Feature header");
      Run
        ([+"Feature: f",
          +"Scenario: s",
          +"Given a",
          +Q3,
          +"t",
          +Q3,
          +"  | x |"]);
      Assert_Refuses (Expected_Scenario, 7, "a table after a doc string");
   end Test_Unterminated_Doc;

   --  Cell text is raw between unescaped pipes, trimmed; step tables
   --  drop one pair of surrounding quotes, Examples keep them.
   procedure Test_Table_Cells (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"Scenario: s",
          +"Given a",
          +"  | a\|b | ""q"" | #1 |",
          +"",
          +"  # a comment inside the table",
          +("  |" & HT & "x\\| y |  z  |")]);
      Assert_Parses ("a step table");
      Assert (Table (Doc, 1).Rows = (1, 2), "blank lines keep one table");
      Assert (Str (Cell (Doc, 1)) = "a\|b", "an escaped pipe stays text");
      Assert (Str (Cell (Doc, 2)) = "q", "surrounding quotes dropped");
      Assert (Str (Cell (Doc, 3)) = "#1", "a hash is text in a cell");
      Assert (Str (Cell (Doc, 4)) = "x\\", "an even backslash run ends");
      Assert (Str (Cell (Doc, 6)) = "z", "cells are trimmed");
      Assert (Table_Row (Doc, 2).Line = 7, "row line");
      Run
        ([+"Feature: f",
          +"Scenario Outline: o",
          +"Given x <a>",
          +"Examples:",
          +"| a |",
          +"| ""q"" |"]);
      Assert_Parses ("an Examples table");
      Assert (Str (Cell (Doc, 2)) = """q""", "Examples cells keep quotes");
   end Test_Table_Cells;

   procedure Test_Table_Refusals (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Head : constant Lines := [+"Feature: f", +"Scenario: s", +"Given a"];
   begin
      Run (Head & [+"| a | b |", +"| c |", +"| d | e |"]);
      Assert_Refuses (Ragged_Table, 5, "a short row");
      Run (Head & [+"| a | b"]);
      Assert_Refuses (Unterminated_Table_Row, 4, "a first row left open");
      Run (Head & [+"| a |", +"| b \|"]);
      Assert_Refuses (Unterminated_Table_Row, 5, "an escaped last pipe");
      Run
        ([+"Feature: f",
          +"Scenario Outline: o",
          +"Given x",
          +"Examples:",
          +"| a |",
          +"| 1 | 2 |"]);
      Assert_Refuses (Ragged_Table, 6, "a wide Examples row");
      Run ([+"Feature: f", +"Scenario: s", +"Given a", +"Examples:"]);
      Assert_Refuses (Expected_Scenario, 4, "Examples after a scenario");
   end Test_Table_Refusals;

   --  One tag line attaches across comments and blank lines; tags are
   --  stored with their '@', and abutting tags are two.
   procedure Test_Tags (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run
        ([+"@f",
          +"Feature: f",
          +"  @a  @b",
          +"  # between",
          +"",
          +"  Scenario: s",
          +"    Given x",
          +"  @x@y",
          +"  Scenario Outline: o",
          +"    Given x",
          +"    @e",
          +"    Examples:",
          +"      | a |"]);
      Assert_Parses ("tagged blocks");
      Assert (Feature (Doc).Tags = (1, 1), "the feature's tag");
      Assert (Scenario (Doc, 1).Tags = (2, 3), "tags across a comment");
      Assert (Str (Tag (Doc, 2)) = "@a", "tags keep their '@'");
      Assert (Str (Tag (Doc, 3)) = "@b", "second tag");
      Assert (Scenario (Doc, 2).Tags = (4, 5), "abutting tags are two");
      Assert (Str (Tag (Doc, 5)) = "@y", "the abutting tag");
      Assert (Examples (Doc, 1).Tags = (6, 6), "the Examples block's tag");
   end Test_Tags;

   procedure Test_Tag_Refusals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run ([+"Feature: f", +"@a b", +"Scenario: s"]);
      Assert_Refuses (Tag_Line_Malformed, 2, "a token without '@'");
      Run ([+"Feature: f", +"@a # note", +"Scenario: s"]);
      Assert_Refuses (Tag_Line_Malformed, 2, "a comment after tags");
      Run ([+"Feature: f", +"@a", +"@b", +"Scenario: s"]);
      Assert_Refuses (Expected_Scenario, 3, "a second tag line");
      Run ([+"@a", +"@b", +"Feature: f"]);
      Assert_Refuses (Expected_Feature, 2, "a second feature tag line");
      Run ([+"Feature: f", +"@r", +"Rule: r"]);
      Assert_Refuses (Expected_Scenario, 3, "a tagged rule");
      Run ([+"Feature: f", +"@b", +"Background:"]);
      Assert_Refuses (Expected_Scenario, 3, "a tagged background");
      Run ([+"Feature: f", +"Scenario: s", +"Given a", +"@a"]);
      Assert_Refuses (Expected_Scenario, 4, "tags before end of input");
   end Test_Tag_Refusals;

   --  Description lines extend the header before them; in a feature
   --  that includes step-like lines and table rows.
   procedure Test_Descriptions (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"  line one",
          +"  Whenever x",
          +"",
          +"  | a |",
          +"  Scenario: s",
          +"    about s",
          +"    Given a"]);
      Assert_Parses ("descriptions");
      Assert
        (Str (Feature (Doc).Head.Description)
         = "line one" & ASCII.LF & "Whenever x" & ASCII.LF & "| a |",
         "feature description, three lines");
      Assert
        (Str (Scenario (Doc, 1).Head.Description) = "about s",
         "scenario description");
      Assert (Step_Count (Doc) = 1, "the step still parses");
      Run ([+"Feature: f", +"Scenario: s", +"Given a", +"not a step"]);
      Assert_Refuses (Expected_Scenario, 4, "prose between steps");
   end Test_Descriptions;

   --  The reference interpreter's description rule: a background,
   --  scenario or outline description runs until its first step.
   procedure Test_Swallowing (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run ([+"Feature: f", +"Scenario: a", +"Scenario: b", +"Given x"]);
      Assert_Parses ("a stepless scenario");
      Assert (Scenario_Count (Doc) = 1, "the second header is prose");
      Assert (Str (Scenario (Doc, 1).Head.Name) = "a", "the first survives");
      Run
        ([+"Feature: f",
          +"Rule: r",
          +"Background:",
          +"Given x",
          +"Scenario: s",
          +"Given y"]);
      Assert_Parses ("a rule background");
      Assert (not Feature (Doc).Has_Background, "a rule has no background");
      Assert (Step_Count (Doc) = 1, "its step is description");
      Assert (Scenario (Doc, 1).Rule = 1, "the scenario joins the rule");
      Run
        ([+"Feature: f",
          +"Scenario Outline: o",
          +"Examples:",
          +"| a |",
          +"| 1 |"]);
      Assert_Parses ("an outline with no steps");
      Assert (Examples_Count (Doc) = 0, "its Examples are description");
   end Test_Swallowing;

   --  A doc string inside each of the six descriptions.  After each one
   --  a "told" line follows that only the right resumed state swallows
   --  as description: resuming any other state changes the document.
   Swallowed_Docs : constant Lines :=
     [+"Feature: f",
      +("  " & Q3),
      +"  in the feature description",
      +("  " & Q3),
      +"  Given told feature",
      +"  Background: b",
      +("    " & Q3),
      +"    in the background head",
      +("    " & B3),
      +"    Scenario: told background",
      +"    Given a",
      +"  Rule: r",
      +("    " & Q3),
      +"    in the rule head",
      +("    " & Q3),
      +"    Background: told rule",
      +"  Scenario: s",
      +("    " & B3),
      +"    in the scenario head",
      +("    " & B3),
      +"    Rule: told scenario",
      +"    Given b",
      +"  Scenario Outline: o",
      +("    " & Q3),
      +"    in the outline head",
      +("    " & Q3),
      +"    Examples: told outline",
      +"    Given <x>",
      +"    Examples:",
      +("      " & Q3),
      +"      in the examples head",
      +("      " & Q3),
      +"      Given told examples",
      +"      | x |",
      +"      | 1 |"];

   procedure Test_Swallowed_Docs (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run (Swallowed_Docs);
      Assert_Parses ("doc strings inside descriptions");
      Assert (Doc_String_Count (Doc) = 0, "no doc string is stored");
      Assert (Doc_Line_Count (Doc) = 0, "no doc-string line is stored");
      Assert
        (Str (Feature (Doc).Head.Description) = "Given told feature",
         "the feature description resumed");
      Assert
        (Str (Background (Doc).Head.Description) = "Scenario: told background",
         "the background head resumed");
      Assert (Rule_Count (Doc) = 1, "one rule");
      Assert
        (Str (Rule (Doc, 1).Head.Description) = "Background: told rule",
         "the rule head resumed");
      Assert (Scenario_Count (Doc) = 2, "one scenario and one outline");
      Assert
        (Str (Scenario (Doc, 1).Head.Description) = "Rule: told scenario",
         "the scenario head resumed");
      Assert
        (Str (Scenario (Doc, 2).Head.Description) = "Examples: told outline",
         "the outline head resumed");
      Assert (Examples_Count (Doc) = 1, "one Examples block");
      Assert
        (Str (Examples (Doc, 1).Head.Description) = "Given told examples",
         "the Examples head resumed");
      Assert (Examples (Doc, 1).Rows = (2, 2), "one data row");
      Assert (Step_Count (Doc) = 3, "the three real steps");
   end Test_Swallowed_Docs;

   --  A Rule must be followed by a scenario or an outline: end of input
   --  in a rule's header or description refuses at the last line fed.
   procedure Test_Dangling_Rule (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run ([+"Feature: f", +"  Rule: r"]);
      Assert_Refuses (Expected_Scenario, 2, "a rule, then end of input");
      Run ([+"Feature: f", +"  Rule: r", +"    some description"]);
      Assert_Refuses (Expected_Scenario, 3, "a described rule, then end");
      Run ([+"Feature: f", +"  Scenario: s", +"    Given a", +"  Rule: r"]);
      Assert_Refuses (Expected_Scenario, 4, "steps, a rule, then end");
   end Test_Dangling_Rule;

   --  After the first refusal every later Feed and the Finish change
   --  neither the refusal nor the document.
   procedure Test_Stickiness (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"Scenario: s",
          +"Given a",
          +"not a step",
          +"Given b",
          +"Scenario: t",
          +"Given c"]);
      Assert_Refuses (Expected_Scenario, 4, "the first refusal");
      Assert (Step_Count (Doc) = 1, "no step after the refusal");
      Assert (Scenario_Count (Doc) = 1, "no scenario after the refusal");
      Feed (P, Doc, "Scenario: u", 8);
      Finish (P, Doc);
      Assert_Refuses (Expected_Scenario, 4, "Feed and Finish after it");
   end Test_Stickiness;

   --  The smallest pool (rules), overflowed by a generated file: each
   --  rule needs a scenario and a step, or the next Rule is prose.
   function Many_Rules return Lines is
      Count  : constant := Fabula.Limits.Max_Rules + 1;
      Result : Lines (1 .. 1 + 3 * Count);
   begin
      Result (1) := +"Feature: f";
      for R in 0 .. Count - 1 loop
         Result (2 + 3 * R) := +"Rule: r";
         Result (3 + 3 * R) := +"Scenario: s";
         Result (4 + 3 * R) := +"Given x";
      end loop;
      return Result;
   end Many_Rules;

   procedure Test_Pool_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run (Many_Rules);
      Assert_Refuses
        (Pool_Exhausted,
         2 + 3 * Fabula.Limits.Max_Rules,
         "the rule one past Max_Rules");
      Assert
        (Rule_Count (Doc) = Rule_Handle (Fabula.Limits.Max_Rules),
         "the rule pool is full, not overrun");
   end Test_Pool_Overflow;

   --  The tag pool overflowed one tag at a time: each scenario takes
   --  two tags, so the tag line of the scenario one past half the pool
   --  is the first that no longer fits.
   function Many_Tagged_Scenarios return Lines is
      Count  : constant := Fabula.Limits.Max_Tags / 2 + 1;
      Result : Lines (1 .. 1 + 3 * Count);
   begin
      Result (1) := +"Feature: f";
      for S in 0 .. Count - 1 loop
         Result (2 + 3 * S) := +"@a @b";
         Result (3 + 3 * S) := +"Scenario: s";
         Result (4 + 3 * S) := +"Given x";
      end loop;
      return Result;
   end Many_Tagged_Scenarios;

   procedure Test_Tag_Pool_Overflow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run (Many_Tagged_Scenarios);
      Assert_Refuses
        (Pool_Exhausted,
         2 + 3 * (Fabula.Limits.Max_Tags / 2),
         "the tag line one past the pool");
      Assert
        (Tag_Count (Doc) = Tag_Handle (Fabula.Limits.Max_Tags),
         "the tag pool is full, not overrun");
   end Test_Tag_Pool_Overflow;

   --  A document that leaves Room bytes of the text arena free: the
   --  headers "Feature: f" and "Scenario: s" store 17 bytes, and steps
   --  of Chunk bytes, plus one shorter step, fill the rest.
   Room  : constant := 4;
   Chunk : constant := 2_000;
   Fill  : constant := Fabula.Limits.Text_Arena_Bytes - Room - 17;

   function Nearly_Full return Lines is
      Full_Steps : constant := Fill / Chunk;
      Result     : Lines (1 .. 3 + Full_Steps);
   begin
      Result (1) := +"Feature: f";
      Result (2) := +"Scenario: s";
      for S in 1 .. Full_Steps loop
         Result (2 + S) := +("Given " & [1 .. Chunk => 'x']);
      end loop;
      Result (Result'Last) := +("Given " & [1 .. Fill mod Chunk => 'y']);
      return Result;
   end Nearly_Full;

   --  A header whose keyword no longer fits refuses, even when its empty
   --  title would still fit: the failed keyword write sticks, so the
   --  title is not written and the scenario is not added.
   procedure Test_Header_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Setup : constant Lines := Nearly_Full;
   begin
      Run (Setup);
      Assert_Parses ("the nearly full document");
      Assert
        (Text_Used (Doc) = Fabula.Limits.Text_Arena_Bytes - Room,
         "the arena has room for less than one keyword");
      Run (Setup & [+"Scenario:"]);
      Assert_Refuses
        (Pool_Exhausted, Setup'Length + 1, "a keyword past the arena");
      Assert (Scenario_Count (Doc) = 1, "the refused scenario is not added");
   end Test_Header_Overflow;

   --  A doc string that closes where no state can take it refuses as
   --  the state it met: before the Feature header, and after it.
   procedure Test_Refuse_Close (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run ([+"@t", +Q3, +"abc", +Q3, +"Feature: f"]);
      Assert_Refuses (Expected_Feature, 4, "a stray doc string before it");
      Run
        ([+"Feature: f",
          +"Scenario: s",
          +"Given a",
          +"  | x |",
          +Q3,
          +"abc",
          +Q3]);
      Assert_Refuses (Expected_Scenario, 7, "a stray doc string after it");
   end Test_Refuse_Close;

   procedure Test_Prologue (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run ([]);
      Assert_Refuses (Expected_Feature, 0, "an empty file");
      Run ([+"# only a comment", +""]);
      Assert_Refuses (Expected_Feature, 2, "a file with no Feature");
      Run ([+"Given a"]);
      Assert_Refuses (Expected_Feature, 1, "a step before the Feature");
      Run ([+"Feature:#"]);
      Assert_Parses ("a keyword run into a hash");
      Assert (Str (Feature (Doc).Head.Name) = "#", "the title is the hash");
      Assert
        (Str (Feature (Doc).Head.Keyword) = "Feature",
         "the keyword without its colon");
   end Test_Prologue;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Doc_String_Fences'Access, "doc string fences and trims");
      Register_Routine
        (T, Test_Closing_Runs'Access, "a fence run anywhere closes");
      Register_Routine (T, Test_One_Line_Doc'Access, "one-line doc strings");
      Register_Routine
        (T, Test_Unterminated_Doc'Access, "doc string refusal lines");
      Register_Routine (T, Test_Table_Cells'Access, "table cell text");
      Register_Routine (T, Test_Table_Refusals'Access, "table refusals");
      Register_Routine (T, Test_Tags'Access, "tags attach to one block");
      Register_Routine (T, Test_Tag_Refusals'Access, "tag refusals");
      Register_Routine (T, Test_Descriptions'Access, "description lines");
      Register_Routine
        (T, Test_Swallowing'Access, "descriptions run to their first step");
      Register_Routine
        (T, Test_Swallowed_Docs'Access, "doc strings inside descriptions");
      Register_Routine
        (T, Test_Dangling_Rule'Access, "a rule with no scenario refuses");
      Register_Routine (T, Test_Stickiness'Access, "refusals stick");
      Register_Routine (T, Test_Pool_Overflow'Access, "pool overflow");
      Register_Routine
        (T, Test_Tag_Pool_Overflow'Access, "tag pool overflow on a tag line");
      Register_Routine
        (T, Test_Header_Overflow'Access, "a header keyword past the arena");
      Register_Routine
        (T, Test_Refuse_Close'Access, "a stray doc string's two refusals");
      Register_Routine (T, Test_Prologue'Access, "before the Feature");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Parse (parser machine)"));

end Fabula_Parse_Tests;
