with AUnit.Assertions;      use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Ast;   use Fabula.Ast;
with Fabula.Parse; use Fabula.Parse;

with Fabula_Fixtures; use Fabula_Fixtures;

package body Fabula_Stepless_Tests is

   use AUnit.Test_Cases.Registration;
   use type Fabula.Line_Number;
   use type Examples_Range;
   use type Examples_Row_Range;
   use type Tag_Range;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;
   P   : Parser;

   procedure Run (Source : Lines) is
   begin
      Parse_Lines (Source, P, Doc);
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

   --  A header line ends a step-less block as it ends a block with
   --  steps: the block stays, with no steps, and the next header opens
   --  its own block with its own tags.  The official Gherkin parser and
   --  behave read the files of the tests below so; the reference
   --  interpreter takes the second header as the first block's
   --  description.
   Three_Steps : constant Lines :=
     [+"    Given An empty box",
      +"    When I place 1 x ""apple"" in it",
      +"    Then The box contains 1 item"];

   procedure Test_Stepless_Scenario
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: A scenario with no steps, no tag after it",
          +"",
          +"  Scenario: Empty",
          +"",
          +"  Scenario: Untagged"]
         & Three_Steps);
      Assert_Parses ("an untagged scenario after an empty one");
      Assert (Scenario_Count (Doc) = 2, "two scenarios");
      Assert (Str (Scenario (Doc, 1).Head.Name) = "Empty", "the empty one");
      Assert (Step_Pool.Width (Scenario (Doc, 1).Steps) = 0, "has no steps");
      Assert (Str (Scenario (Doc, 2).Head.Name) = "Untagged", "the next one");
      Assert (Step_Pool.Width (Scenario (Doc, 2).Steps) = 3, "has three");
      Assert
        (Is_Empty (Scenario (Doc, 1).Head.Description),
         "the next header is no description");

      Run
        ([+"Feature: A scenario with no steps",
          +"",
          +"  Scenario: Empty",
          +"",
          +"  @tagged",
          +"  Scenario: Tagged"]
         & Three_Steps);
      Assert_Parses ("a tagged scenario after an empty one");
      Assert (Scenario_Count (Doc) = 2, "two scenarios, tagged");
      Assert
        (Tag_Pool.Is_Empty (Scenario (Doc, 1).Tags), "the empty one: no tag");
      Assert (Str (Scenario (Doc, 2).Head.Name) = "Tagged", "the tagged one");
      Assert (Scenario (Doc, 2).Tags = (1, 1), "keeps its tag");
      Assert (Str (Tag (Doc, 1)) = "@tagged", "the tag");
      Assert (Step_Pool.Width (Scenario (Doc, 2).Steps) = 3, "and its steps");
   end Test_Stepless_Scenario;

   procedure Test_Stepless_Background
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: A background with no steps",
          +"",
          +"  Background: Nothing yet",
          +"",
          +"  Scenario: First",
          +"    Given An empty box",
          +"    Then The box contains 0 items",
          +"",
          +"  Scenario: Second"]
         & Three_Steps);
      Assert_Parses ("scenarios after an empty background");
      Assert (Feature (Doc).Has_Background, "the background stays");
      Assert
        (Str (Background (Doc).Head.Name) = "Nothing yet", "its name stays");
      Assert (Step_Pool.Width (Background (Doc).Steps) = 0, "with no steps");
      Assert (Scenario_Count (Doc) = 2, "both scenarios");
      Assert (Str (Scenario (Doc, 1).Head.Name) = "First", "the first");
      Assert (Step_Pool.Width (Scenario (Doc, 1).Steps) = 2, "its two steps");
      Assert (Str (Scenario (Doc, 2).Head.Name) = "Second", "the second");

      Run
        ([+"Feature: f",
          +"Background: b",
          +"Rule: r",
          +"Scenario: s",
          +"Given x",
          +"Scenario: last"]);
      Assert_Parses ("a rule after an empty background");
      Assert (Rule_Count (Doc) = 1, "the rule opens after the background");
      Assert (Scenario_Count (Doc) = 2, "the empty last scenario stays");
   end Test_Stepless_Background;

   --  A rule after a step-less scenario opens.  As after a step, these
   --  are refused: a malformed tag line, an Examples line under a plain
   --  scenario, a description line that starts with '@', and tags
   --  between a header and its first step.
   procedure Test_Stepless_Rule (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: A step-less scenario before a rule",
          +"",
          +"  Scenario: Empty",
          +"",
          +"  Rule: Boxes hold items",
          +"",
          +"    Scenario: Inside the rule"]
         & Three_Steps);
      Assert_Parses ("a rule after an empty scenario");
      Assert (Scenario_Count (Doc) = 2, "the empty scenario and the rule's");
      Assert (Scenario (Doc, 1).Rule = No_Rule, "the empty one: no rule");
      Assert (Rule_Count (Doc) = 1, "the rule opens");
      Assert
        (Str (Rule (Doc, 1).Head.Name) = "Boxes hold items",
         "the rule's name");
      Assert (Scenario (Doc, 2).Rule = 1, "the rule's scenario joins it");
      Assert (Step_Pool.Width (Scenario (Doc, 2).Steps) = 3, "with its steps");

      Run ([+"Feature: f", +"Scenario: a", +"@a b", +"Scenario: b"]);
      Assert_Refuses (Tag_Line_Malformed, 3, "bad tags after an empty one");
      Run ([+"Feature: f", +"Scenario: a", +"Examples:", +"| a |"]);
      Assert_Refuses
        (Expected_Scenario, 3, "Examples after an empty plain scenario");
      Run ([+"Feature: f", +"Scenario: a", +"@a"]);
      Assert_Refuses (Expected_Scenario, 3, "tags, then end of input");
      Run ([+"Feature: f", +"Scenario: a", +"@see the ticket", +"Given x"]);
      Assert_Refuses (Tag_Line_Malformed, 3, "a description line with '@'");
      Run ([+"Feature: f", +"Scenario: a", +"@wip", +"Given x"]);
      Assert_Refuses (Expected_Scenario, 4, "tags before the first step");
   end Test_Stepless_Rule;

   --  The same rule for an outline with no steps and an Examples block
   --  with no rows: the next Examples, tag, scenario, outline or rule
   --  line opens its own block.
   procedure Test_Stepless_Outline
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"  Scenario Outline: empty outline",
          +"    Examples:",
          +"      | a |",
          +"      | 1 |",
          +"      | 2 |",
          +"  Scenario: after",
          +"    Given x"]);
      Assert_Parses ("Examples after an outline with no steps");
      Assert (Scenario_Count (Doc) = 2, "the outline and the scenario");
      Assert (Step_Pool.Width (Scenario (Doc, 1).Steps) = 0, "no steps");
      Assert (Examples_Count (Doc) = 1, "its Examples block");
      Assert (Scenario (Doc, 1).Examples = (1, 1), "belongs to the outline");
      Assert (Examples (Doc, 1).Rows = (2, 3), "two data rows");

      Run
        ([+"Feature: f",
          +"  Scenario Outline: empty",
          +"  @tagged",
          +"  Scenario Outline: full",
          +"    Given <n>",
          +"    Examples:",
          +"      | n |",
          +"      | 1 |"]);
      Assert_Parses ("a tagged outline after an empty one");
      Assert (Scenario_Count (Doc) = 2, "two outlines");
      Assert (Tag_Pool.Is_Empty (Scenario (Doc, 1).Tags), "no tag on one");
      Assert (Scenario (Doc, 2).Tags = (1, 1), "the tag on the second");
      Assert (Scenario (Doc, 2).Examples = (1, 1), "the Examples on it");
   end Test_Stepless_Outline;

   procedure Test_Rowless_Examples
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"  Scenario Outline: o",
          +"    Given <n>",
          +"    Examples: no rows",
          +"    Examples: real",
          +"      | n |",
          +"      | 2 |",
          +"    Examples: no rows again",
          +"    @tagged",
          +"    Scenario: tagged after",
          +"      Given x",
          +"  Scenario Outline: second",
          +"    Given x",
          +"    Examples: empty before a rule",
          +"  Rule: r",
          +"    Scenario: in the rule",
          +"      Given x"]);
      Assert_Parses ("Examples blocks with no rows");
      Assert (Examples_Count (Doc) = 4, "four Examples blocks");
      Assert (Scenario (Doc, 1).Examples = (1, 3), "three on the outline");
      Assert (Str (Examples (Doc, 1).Head.Name) = "no rows", "the first");
      Assert
        (Examples (Doc, 1).Header_Row = No_Examples_Row, "has no header row");
      Assert (Str (Examples (Doc, 2).Head.Name) = "real", "the second");
      Assert (Examples (Doc, 2).Rows = (2, 2), "has one data row");
      Assert
        (Str (Examples (Doc, 3).Head.Name) = "no rows again", "the third");
      Assert (Scenario_Count (Doc) = 4, "four scenarios");
      Assert
        (Str (Scenario (Doc, 2).Head.Name) = "tagged after", "the tagged one");
      Assert (Scenario (Doc, 2).Tags = (1, 1), "keeps its tag");
      Assert (Scenario (Doc, 3).Examples = (4, 4), "the fourth block");
      Assert (Rule_Count (Doc) = 1, "the rule after it opens");
      Assert (Scenario (Doc, 4).Rule = 1, "with its scenario");
   end Test_Rowless_Examples;

   --  A Feature or Background line after an Examples header is
   --  description, as in the official Gherkin grammar.
   procedure Test_Examples_Description
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run
        ([+"Feature: f",
          +"  Scenario Outline: o",
          +"    Given <n>",
          +"    Examples:",
          +"    Background: late",
          +"    Feature: again",
          +"      | n |",
          +"      | 1 |"]);
      Assert_Parses ("header lines an Examples description keeps");
      Assert
        (Str (Examples (Doc, 1).Head.Description)
         = "Background: late" & ASCII.LF & "Feature: again",
         "both lines are its description");
      Assert (Examples (Doc, 1).Rows = (2, 2), "the table follows");
   end Test_Examples_Description;

   ---------------------------------------------------------------------
   --  Every header line in every step-less head, one cell each.  A
   --  file is the head's prefix, the header line, then Head_Suffix; a
   --  cell names the refusal, or the node counts and whether the
   --  header line went into the head's description.
   ---------------------------------------------------------------------

   type Head_Kind is (In_Background, In_Scenario, In_Outline, In_Examples);

   type Header_Line is
     (Scenario_Line,
      Outline_Line,
      Rule_Line,
      Good_Tags,
      Bad_Tags,
      Feature_Line,
      Background_Line,
      Examples_Line);

   type Cell_Outcome is record
      Refusal   : Error_Kind := None;
      Scenarios : Natural := 0;
      Rules     : Natural := 0;
      Blocks    : Natural := 0;
      Tags      : Natural := 0;
      Described : Boolean := False;
   end record;

   function Runs
     (Scenarios : Natural;
      Rules     : Natural := 0;
      Blocks    : Natural := 0;
      Tags      : Natural := 0;
      Described : Boolean := False) return Cell_Outcome
   is ((None, Scenarios, Rules, Blocks, Tags, Described));

   function Refused (Kind : Error_Kind) return Cell_Outcome
   is ((Refusal => Kind, others => <>));

   Head_Cells : constant array (Head_Kind, Header_Line) of Cell_Outcome :=
     [In_Background =>
        [Scenario_Line   => Runs (2),
         Outline_Line    => Runs (2),
         Rule_Line       => Runs (1, Rules => 1),
         Good_Tags       => Runs (1, Tags => 1),
         Bad_Tags        => Refused (Tag_Line_Malformed),
         Feature_Line    => Runs (1, Described => True),
         Background_Line => Runs (1, Described => True),
         Examples_Line   => Runs (1, Described => True)],
      In_Scenario   =>
        [Scenario_Line   => Runs (3),
         Outline_Line    => Runs (3),
         Rule_Line       => Runs (2, Rules => 1),
         Good_Tags       => Runs (2, Tags => 1),
         Bad_Tags        => Refused (Tag_Line_Malformed),
         Feature_Line    => Runs (2, Described => True),
         Background_Line => Runs (2, Described => True),
         Examples_Line   => Refused (Expected_Scenario)],
      In_Outline    =>
        [Scenario_Line   => Runs (3),
         Outline_Line    => Runs (3),
         Rule_Line       => Runs (2, Rules => 1),
         Good_Tags       => Runs (2, Tags => 1),
         Bad_Tags        => Refused (Tag_Line_Malformed),
         Feature_Line    => Runs (2, Described => True),
         Background_Line => Runs (2, Described => True),
         Examples_Line   => Runs (2, Blocks => 1)],
      In_Examples   =>
        [Scenario_Line   => Runs (3, Blocks => 1),
         Outline_Line    => Runs (3, Blocks => 1),
         Rule_Line       => Runs (2, Rules => 1, Blocks => 1),
         Good_Tags       => Runs (2, Blocks => 1, Tags => 1),
         Bad_Tags        => Refused (Tag_Line_Malformed),
         Feature_Line    => Runs (2, Blocks => 1, Described => True),
         Background_Line => Runs (2, Blocks => 1, Described => True),
         Examples_Line   => Runs (2, Blocks => 2)]];

   function Head_Prefix (H : Head_Kind) return Lines
   is (case H is
         when In_Background => [+"Feature: f", +"Background: b"],
         when In_Scenario   => [+"Feature: f", +"Scenario: s"],
         when In_Outline    => [+"Feature: f", +"Scenario Outline: o"],
         when In_Examples   =>
           [+"Feature: f",
            +"Scenario Outline: o",
            +"Given <x>",
            +"Examples: e"]);

   function Header_Text (E : Header_Line) return Unbounded_String
   is (case E is
         when Scenario_Line   => +"Scenario: next",
         when Outline_Line    => +"Scenario Outline: next",
         when Rule_Line       => +"Rule: next",
         when Good_Tags       => +"@next",
         when Bad_Tags        => +"@next bad",
         when Feature_Line    => +"Feature: next",
         when Background_Line => +"Background: next",
         when Examples_Line   => +"Examples: next");

   Head_Suffix : constant Lines := [+"Scenario: last", +"Given x"];

   --  The description a header line in head H would extend.
   function Head_Description (H : Head_Kind) return Fabula.Ast.Slice
   is (case H is
         when In_Background            => Background (Doc).Head.Description,
         when In_Scenario | In_Outline => Scenario (Doc, 1).Head.Description,
         when In_Examples              => Examples (Doc, 1).Head.Description);

   procedure Assert_Runs (H : Head_Kind; Want : Cell_Outcome; What : String) is
   begin
      Assert_Parses (What);
      Assert
        (Natural (Scenario_Count (Doc)) = Want.Scenarios, What & ": nodes");
      Assert (Natural (Rule_Count (Doc)) = Want.Rules, What & ": rules");
      Assert (Natural (Examples_Count (Doc)) = Want.Blocks, What & ": blocks");
      Assert (Natural (Tag_Count (Doc)) = Want.Tags, What & ": tags");
      Assert
        (Is_Empty (Head_Description (H)) = not Want.Described,
         What & ": the head's description");
   end Assert_Runs;

   procedure Check_Cell (H : Head_Kind; E : Header_Line) is
      Want    : constant Cell_Outcome := Head_Cells (H, E);
      Head    : constant Lines := Head_Prefix (H);
      At_Line : constant Fabula.Line_Number :=
        Fabula.Line_Number (Head'Length + 1);
      What    : constant String := H'Image & " + " & E'Image;
   begin
      Run (Head & Header_Text (E) & Head_Suffix);
      if Want.Refusal = None then
         Assert_Runs (H, Want, What);
      else
         Assert_Refuses (Want.Refusal, At_Line, What);
      end if;
   end Check_Cell;

   procedure Test_Head_Cells (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for H in Head_Kind loop
         for E in Header_Line loop
            Check_Cell (H, E);
         end loop;
      end loop;
   end Test_Head_Cells;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Stepless_Scenario'Access, "a step-less scenario ends");
      Register_Routine
        (T, Test_Stepless_Background'Access, "a step-less background ends");
      Register_Routine
        (T, Test_Stepless_Rule'Access, "a rule, and refusals as after a step");
      Register_Routine
        (T, Test_Stepless_Outline'Access, "a step-less outline ends");
      Register_Routine
        (T, Test_Rowless_Examples'Access, "Examples with no rows end too");
      Register_Routine
        (T, Test_Examples_Description'Access, "an Examples description");
      Register_Routine
        (T, Test_Head_Cells'Access, "every header line in every head");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Parse (step-less blocks)"));

end Fabula_Stepless_Tests;
