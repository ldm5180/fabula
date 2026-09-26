with AUnit.Assertions;      use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Limits;
with Fabula.Scan; use Fabula.Scan;

package body Fabula_Scan_Tests is

   use AUnit.Test_Cases.Registration;

   --  Every Check_* helper re-derives its expectation from the SLICE
   --  content Classify hands back, not from hand-computed indices, so
   --  a case reads as "this line means this text" rather than as
   --  brittle numbers a future refactor would have to recompute.

   procedure Check_Header
     (Input : String; Expected : Line_Class; Title : String; Indent : Natural)
   is
      C : constant Classification := Classify (Input);
   begin
      Assert
        (C.Class = Expected,
         Input
         & ": expected class "
         & Expected'Image
         & ", got "
         & C.Class'Image);
      Assert
        (C.Indent = Indent,
         Input
         & ": expected indent"
         & Indent'Image
         & ", got"
         & C.Indent'Image);
      if Title'Length = 0 then
         Assert
           (C.Title_Last < C.Title_First,
            Input & ": expected an empty title slice");
      else
         Assert
           (C.Title_Last - C.Title_First + 1 = Title'Length
            and then Input (C.Title_First .. C.Title_Last) = Title,
            Input & ": expected title """ & Title & """");
      end if;
   end Check_Header;

   procedure Check_Step
     (Input            : String;
      Expected_Keyword : Step_Keyword;
      Text             : String;
      Indent           : Natural)
   is
      C : constant Classification := Classify (Input);
   begin
      Assert
        (C.Class = Step_Line,
         Input & ": expected Step_Line, got " & C.Class'Image);
      Assert
        (C.Keyword = Expected_Keyword,
         Input
         & ": expected keyword "
         & Expected_Keyword'Image
         & ", got "
         & C.Keyword'Image);
      Assert
        (C.Indent = Indent,
         Input
         & ": expected indent"
         & Indent'Image
         & ", got"
         & C.Indent'Image);
      if Text'Length = 0 then
         Assert
           (C.Text_Last < C.Text_First,
            Input & ": expected an empty step text slice");
      else
         Assert
           (C.Text_Last - C.Text_First + 1 = Text'Length
            and then Input (C.Text_First .. C.Text_Last) = Text,
            Input & ": expected step text """ & Text & """");
      end if;
   end Check_Step;

   procedure Check_Fence
     (Input          : String;
      Expected_Fence : Fence_Kind;
      Content_Type   : String;
      Indent         : Natural)
   is
      C : constant Classification := Classify (Input);
   begin
      Assert
        (C.Class = Doc_Fence,
         Input & ": expected Doc_Fence, got " & C.Class'Image);
      Assert
        (C.Fence = Expected_Fence,
         Input
         & ": expected fence "
         & Expected_Fence'Image
         & ", got "
         & C.Fence'Image);
      Assert
        (C.Indent = Indent,
         Input
         & ": expected indent"
         & Indent'Image
         & ", got"
         & C.Indent'Image);
      if Content_Type'Length = 0 then
         Assert
           (C.Type_Last < C.Type_First,
            Input & ": expected an empty content-type slice");
      else
         Assert
           (C.Type_Last - C.Type_First + 1 = Content_Type'Length
            and then Input (C.Type_First .. C.Type_Last) = Content_Type,
            Input & ": expected content type """ & Content_Type & """");
      end if;
   end Check_Fence;

   procedure Check_Body
     (Input     : String;
      Expected  : Line_Class;
      Body_Text : String;
      Indent    : Natural)
   is
      C : constant Classification := Classify (Input);
   begin
      Assert
        (C.Class = Expected,
         Input
         & ": expected class "
         & Expected'Image
         & ", got "
         & C.Class'Image);
      Assert
        (C.Indent = Indent,
         Input
         & ": expected indent"
         & Indent'Image
         & ", got"
         & C.Indent'Image);
      Assert
        (C.Body_Last - C.Body_First + 1 = Body_Text'Length
         and then Input (C.Body_First .. C.Body_Last) = Body_Text,
         Input & ": expected body """ & Body_Text & """");
   end Check_Body;

   procedure Check_Simple (Input : String; Expected : Line_Class) is
      C : constant Classification := Classify (Input);
   begin
      Assert
        (C.Class = Expected,
         Input
         & ": expected class "
         & Expected'Image
         & ", got "
         & C.Class'Image);
      Assert
        (C.Indent = 0, Input & ": expected indent 0, got" & C.Indent'Image);
   end Check_Simple;

   procedure Test_Headers (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Case_Record is record
         Input    : Unbounded_String;
         Expected : Line_Class;
         Title    : Unbounded_String;
         Indent   : Natural;
      end record;
      Cases : constant array (Positive range <>) of Case_Record :=
        [(To_Unbounded_String ("Feature: x"),
          Feature_Header,
          To_Unbounded_String ("x"),
          0),
         (To_Unbounded_String ("  Feature: x"),
          Feature_Header,
          To_Unbounded_String ("x"),
          2),
         (To_Unbounded_String ("Scenario: y"),
          Scenario_Header,
          To_Unbounded_String ("y"),
          0),
         (To_Unbounded_String ("  Scenario: y"),
          Scenario_Header,
          To_Unbounded_String ("y"),
          2),
         (To_Unbounded_String ("Example: z"),
          Scenario_Header,
          To_Unbounded_String ("z"),
          0),
         (To_Unbounded_String ("Scenario Outline: o"),
          Outline_Header,
          To_Unbounded_String ("o"),
          0),
         (To_Unbounded_String ("Scenario Template: t"),
          Outline_Header,
          To_Unbounded_String ("t"),
          0),
         (To_Unbounded_String ("Rule: r"),
          Rule_Header,
          To_Unbounded_String ("r"),
          0),
         (To_Unbounded_String ("Background: b"),
          Background_Header,
          To_Unbounded_String ("b"),
          0),
         (To_Unbounded_String ("Examples: e"),
          Examples_Header,
          To_Unbounded_String ("e"),
          0),
         (To_Unbounded_String ("Scenarios: s"),
          Examples_Header,
          To_Unbounded_String ("s"),
          0)];
   begin
      for C of Cases loop
         Check_Header
           (To_String (C.Input), C.Expected, To_String (C.Title), C.Indent);
      end loop;
   end Test_Headers;

   procedure Test_Header_Edge_Cases
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      CR : constant String := [1 => ASCII.CR];
   begin
      --  A trailing carriage return counts as whitespace (CRLF input):
      --  the title slice excludes it.
      Check_Header ("Feature: x" & CR, Feature_Header, "x", 0);
      --  A header keyword with nothing after it has an empty title.
      Check_Header ("Feature:", Feature_Header, "", 0);
   end Test_Header_Edge_Cases;

   procedure Test_Header_Collision_Guards
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  `Examples:` and `Scenarios:` are Examples_Header synonyms, not
      --  Scenario_Header, even though they share the "S...:" family.
      Assert
        (Classify ("Examples: e").Class /= Scenario_Header,
         "Examples: must not classify as Scenario_Header");
      Assert
        (Classify ("Scenarios: s").Class /= Scenario_Header,
         "Scenarios: must not classify as Scenario_Header");
      Assert
        (Classify ("Examples: e").Class = Examples_Header,
         "Examples: must classify as Examples_Header");
      Assert
        (Classify ("Scenarios: s").Class = Examples_Header,
         "Scenarios: must classify as Examples_Header");
   end Test_Header_Collision_Guards;

   procedure Test_Colon_Keyword_Boundaries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      type Case_Record is record
         Keyword  : Unbounded_String;
         Expected : Line_Class;
      end record;
      --  One row per colon keyword pins its Text_Length: a wrong
      --  length either eats into the title (too short) or misses the
      --  match entirely (too long), and both cases below catch it.
      Cases : constant array (Positive range <>) of Case_Record :=
        [(To_Unbounded_String ("Feature:"), Feature_Header),
         (To_Unbounded_String ("Scenario:"), Scenario_Header),
         (To_Unbounded_String ("Example:"), Scenario_Header),
         (To_Unbounded_String ("Scenario Outline:"), Outline_Header),
         (To_Unbounded_String ("Scenario Template:"), Outline_Header),
         (To_Unbounded_String ("Rule:"), Rule_Header),
         (To_Unbounded_String ("Background:"), Background_Header),
         (To_Unbounded_String ("Examples:"), Examples_Header),
         (To_Unbounded_String ("Scenarios:"), Examples_Header)];
   begin
      for C of Cases loop
         declare
            Keyword : constant String := To_String (C.Keyword);
         begin
            Check_Header (Keyword & "x", C.Expected, "x", 0);
            Check_Header (Keyword, C.Expected, "", 0);
         end;
      end loop;
   end Test_Colon_Keyword_Boundaries;

   procedure Test_Steps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Case_Record is record
         Input   : Unbounded_String;
         Keyword : Step_Keyword;
         Text    : Unbounded_String;
         Indent  : Natural;
      end record;
      CR    : constant String := [1 => ASCII.CR];
      Cases : constant array (Positive range <>) of Case_Record :=
        [(To_Unbounded_String ("Given a"),
          K_Given,
          To_Unbounded_String ("a"),
          0),
         (To_Unbounded_String ("  Given a"),
          K_Given,
          To_Unbounded_String ("a"),
          2),
         (To_Unbounded_String ("When b"),
          K_When,
          To_Unbounded_String ("b"),
          0),
         (To_Unbounded_String ("Then c"),
          K_Then,
          To_Unbounded_String ("c"),
          0),
         (To_Unbounded_String ("And d"), K_And, To_Unbounded_String ("d"), 0),
         (To_Unbounded_String ("But e"), K_But, To_Unbounded_String ("e"), 0),
         (To_Unbounded_String ("* The box"),
          K_Star,
          To_Unbounded_String ("The box"),
          0),
         (To_Unbounded_String ("*"), K_Star, To_Unbounded_String (""), 0),
         (To_Unbounded_String ("*bare"),
          K_Star,
          To_Unbounded_String ("bare"),
          0),
         --  cwt matches by starts_with, not a word boundary, so a
         --  keyword run straight into the following text ("Givenx")
         --  is a step with text "x".
         (To_Unbounded_String ("Givenx"),
          K_Given,
          To_Unbounded_String ("x"),
          0),
         (To_Unbounded_String ("Given"), K_Given, To_Unbounded_String (""), 0),
         (To_Unbounded_String ("Given a   "),
          K_Given,
          To_Unbounded_String ("a"),
          0),
         (To_Unbounded_String ("Given a" & CR),
          K_Given,
          To_Unbounded_String ("a"),
          0)];
   begin
      for C of Cases loop
         Check_Step
           (To_String (C.Input), C.Keyword, To_String (C.Text), C.Indent);
      end loop;
   end Test_Steps;

   procedure Test_Doc_Fences (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Case_Record is record
         Input  : Unbounded_String;
         Fence  : Fence_Kind;
         Ctype  : Unbounded_String;
         Indent : Natural;
      end record;
      Triple_Quote : constant String := [1 .. 3 => '"'];
      Cases        : constant array (Positive range <>) of Case_Record :=
        [(To_Unbounded_String (Triple_Quote),
          Quotes,
          To_Unbounded_String (""),
          0),
         (To_Unbounded_String (Triple_Quote & "json"),
          Quotes,
          To_Unbounded_String ("json"),
          0),
         --  cwt right-trims the whole line, then takes substr(3): the
         --  content type keeps its leading whitespace.
         (To_Unbounded_String (Triple_Quote & " json"),
          Quotes,
          To_Unbounded_String (" json"),
          0),
         (To_Unbounded_String ("```"), Backticks, To_Unbounded_String (""), 0),
         (To_Unbounded_String ("```md"),
          Backticks,
          To_Unbounded_String ("md"),
          0)];
   begin
      for C of Cases loop
         Check_Fence
           (To_String (C.Input), C.Fence, To_String (C.Ctype), C.Indent);
      end loop;
   end Test_Doc_Fences;

   procedure Test_Indentation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Header_Case is record
         Text  : Unbounded_String;
         Class : Line_Class;
      end record;
      --  Every one of the 14 keywords, indented by two spaces, must
      --  classify the same as unindented and report Indent 2.
      Header_Cases : constant array (Positive range <>) of Header_Case :=
        [(To_Unbounded_String ("Feature:"), Feature_Header),
         (To_Unbounded_String ("Scenario:"), Scenario_Header),
         (To_Unbounded_String ("Example:"), Scenario_Header),
         (To_Unbounded_String ("Scenario Outline:"), Outline_Header),
         (To_Unbounded_String ("Scenario Template:"), Outline_Header),
         (To_Unbounded_String ("Rule:"), Rule_Header),
         (To_Unbounded_String ("Background:"), Background_Header),
         (To_Unbounded_String ("Examples:"), Examples_Header),
         (To_Unbounded_String ("Scenarios:"), Examples_Header)];
      type Step_Case is record
         Text    : Unbounded_String;
         Keyword : Step_Keyword;
      end record;
      Step_Cases   : constant array (Positive range <>) of Step_Case :=
        [(To_Unbounded_String ("Given"), K_Given),
         (To_Unbounded_String ("When"), K_When),
         (To_Unbounded_String ("Then"), K_Then),
         (To_Unbounded_String ("And"), K_And),
         (To_Unbounded_String ("But"), K_But)];
      Tab          : constant String := [1 => ASCII.HT];
      Triple_Quote : constant String := [1 .. 3 => '"'];
   begin
      for C of Header_Cases loop
         Check_Header ("  " & To_String (C.Text) & " x", C.Class, "x", 2);
      end loop;
      for C of Step_Cases loop
         Check_Step ("  " & To_String (C.Text) & " x", C.Keyword, "x", 2);
      end loop;
      --  Indent counts characters, not visual columns: one tab is one
      --  character of indent, not a tab stop's width.
      Check_Step (Tab & "Given x", K_Given, "x", 1);
      Check_Fence ("    " & Triple_Quote & "json", Quotes, "json", 4);
   end Test_Indentation;

   procedure Test_Tag_Lines (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Body ("@smoke @fast", Tag_Line, "@smoke @fast", 0);
      Check_Body ("  @smoke", Tag_Line, "@smoke", 2);
   end Test_Tag_Lines;

   procedure Test_Table_Rows (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Body ("| a | b |", Table_Row, "| a | b |", 0);
   end Test_Table_Rows;

   procedure Test_Descriptions (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Two_Quotes : constant String := [1 .. 2 => '"'];
   begin
      Check_Body ("just prose", Description, "just prose", 0);
      Check_Body ("Feature", Description, "Feature", 0);
      Check_Body ("Feature :", Description, "Feature :", 0);
      --  Fewer than three identical fence characters is not a fence.
      Check_Body (Two_Quotes, Description, Two_Quotes, 0);
   end Test_Descriptions;

   procedure Test_Comments (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Simple ("# any", Comment);
      Check_Simple ("#", Comment);
      --  fabula supports English only, so a language directive is an
      --  ordinary comment, with no special-cased code.
      Check_Simple ("# language: en", Comment);
   end Test_Comments;

   procedure Test_Blank_Lines (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Simple ("", Blank);
      Check_Simple ("   ", Blank);
      Check_Simple ([1 => ASCII.HT], Blank);
      Check_Simple ([1 => ASCII.CR], Blank);
   end Test_Blank_Lines;

   procedure Test_Max_Line_Length (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Longest : constant String (1 .. Fabula.Limits.Max_Line_Length) :=
        [others => 'x'];
      C       : constant Classification := Classify (Longest);
   begin
      Assert
        (C.Class = Description,
         "a line of the shipped maximum length must still classify");
      Assert
        (C.Body_Last - C.Body_First + 1 = Longest'Length,
         "the maximum-length line's body must span the whole line");
   end Test_Max_Line_Length;

   procedure Test_Spelling (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Spelling (K_Given) = "Given", "Given");
      Assert (Spelling (K_When) = "When", "When");
      Assert (Spelling (K_Then) = "Then", "Then");
      Assert (Spelling (K_And) = "And", "And");
      Assert (Spelling (K_But) = "But", "But");
      Assert (Spelling (K_Star) = "*", "the star bullet");
   end Test_Spelling;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Headers'Access, "keyword headers, plain and indented");
      Register_Routine
        (T, Test_Header_Edge_Cases'Access, "CRLF and an empty title");
      Register_Routine
        (T,
         Test_Header_Collision_Guards'Access,
         "Examples:/Scenarios: are not Scenario_Header");
      Register_Routine
        (T,
         Test_Colon_Keyword_Boundaries'Access,
         "each colon keyword's Text_Length, both edges");
      Register_Routine
        (T, Test_Steps'Access, "step keywords and the * bullet");
      Register_Routine
        (T, Test_Doc_Fences'Access, "doc-string fences and content types");
      Register_Routine
        (T, Test_Indentation'Access, "every keyword indented, plus tab");
      Register_Routine (T, Test_Tag_Lines'Access, "tag lines");
      Register_Routine (T, Test_Table_Rows'Access, "table rows");
      Register_Routine (T, Test_Descriptions'Access, "description fallback");
      Register_Routine (T, Test_Comments'Access, "comments");
      Register_Routine (T, Test_Blank_Lines'Access, "blank lines");
      Register_Routine
        (T, Test_Max_Line_Length'Access, "shipped maximum line length");
      Register_Routine (T, Test_Spelling'Access, "a step keyword's spelling");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Scan (line classifier)"));

end Fabula_Scan_Tests;
