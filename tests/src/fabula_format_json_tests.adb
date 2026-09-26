with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast;    use Fabula.Ast;
with Fabula.Expand; use Fabula.Expand;
with Fabula.Format; use Fabula.Format;
with Fabula.Parse;  use Fabula.Parse;

with Fabula_Fixtures; use Fabula_Fixtures;

package body Fabula_Format_Json_Tests is

   use AUnit.Test_Cases.Registration;

   --  A document is a megabyte-scale record: it lives at library level,
   --  never on a test routine's stack.
   Doc : Document;
   P   : Parser;

   --  A literal double quote and backslash, built once so the JSON
   --  tests below compose expected text by concatenation instead of
   --  counting doubled quotes in a string literal.
   Q  : constant Character := '"';
   BS : constant Character := '\';

   --  Twice Depth spaces, the same indent rule Fabula.Format's own
   --  nesting depths use, so an expected JSON line is built by depth,
   --  never by counting spaces in a string literal.
   function Sp (Depth : Positive) return String
   is ([1 .. 2 * Depth => ' ']);

   procedure Load (Name : String) is
   begin
      Parse_Corpus (Name, P, Doc);
      Assert (not Failed (P), Name & " must parse");
   end Load;

   procedure Load_Lines (Source : Fabula_Fixtures.Lines) is
   begin
      Fabula_Fixtures.Parse_Lines (Source, P, Doc);
      Assert (not Failed (P), "the fixture must parse");
   end Load_Lines;

   function Nth_Step (S : Scenario_Index; N : Positive) return Step_Node
   is (Step (Doc, Scenario (Doc, S).Steps.First + Step_Handle (N) - 1));

   ---------------------------------------------------------------------
   --  Escaping and the space-joined doc-string / description content.
   ---------------------------------------------------------------------

   procedure Test_Escape_Json_Plain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Escape_Json ("An empty box") = "An empty box",
         "plain text is untouched");
   end Test_Escape_Json_Plain;

   procedure Test_Escape_Json_Torture
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : constant String :=
        "a" & Q & "b" & BS & "c" & ASCII.LF & "d" & ASCII.HT & "e";
      Want   : constant String :=
        "a" & BS & Q & "b" & BS & BS & "c" & "\n" & "d" & "\t" & "e";
   begin
      Assert
        (Escape_Json (Source) = Want,
         "quote, backslash, newline and tab, all escaped: got """
         & Escape_Json (Source)
         & """");
   end Test_Escape_Json_Torture;

   --  CR, backspace and form feed by name; a control character with no
   --  named escape (vertical tab, 0x0B) as "\u000b" -- lowercase hex,
   --  matching common JSON tooling.
   procedure Test_Escape_Json_Control_Chars
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : constant String :=
        "a"
        & ASCII.CR
        & "b"
        & ASCII.BS
        & "c"
        & ASCII.FF
        & "d"
        & Character'Val (11)
        & "e";
      Want   : constant String := "a\rb\bc\fd\u000be";
   begin
      Assert
        (Escape_Json (Source) = Want,
         "CR, backspace, form feed and \u000b (lowercase hex), got: """
         & Escape_Json (Source)
         & """");
   end Test_Escape_Json_Control_Chars;

   procedure Test_Doc_String_Content_Space_Joined
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      J : Joined_Text;
   begin
      Load ("7_doc_strings.feature");
      J := Doc_String_Content (Doc, Nth_Step (1, 1).Doc, 0, 0);
      Assert (J.Ok, "two short lines fit");
      Assert
        (Value (J) = "This is a docstring with quotes after a step",
         "space-joined, byte-verified against the rebuilt oracle's JSON"
         & " report (its own join, not a newline join)");
   end Test_Doc_String_Content_Space_Joined;

   --  A doc-string content line carrying every character Escape_Json
   --  names by name: a quote, a backslash, a tab.
   procedure Test_Doc_String_Escaping_Torture
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Fence : constant String := Q & Q & Q;
   begin
      Load_Lines
        ([+"Feature: f",
          +"  Scenario: s",
          +"    Given a",
          +Fence,
          +("a "
            & Q
            & "quoted"
            & Q
            & " word and a"
            & BS
            & "slash and a"
            & ASCII.HT
            & "tab"),
          +Fence]);
      declare
         Line    : constant Doc_Line_Handle :=
           Doc_String (Doc, Nth_Step (1, 1).Doc).Lines.First;
         Escaped : constant String :=
           Escape_Json (Doc_Content_Text (Doc, Line, 0, 0));
      begin
         Assert
           (Escaped
            = "a "
              & BS
              & Q
              & "quoted"
              & BS
              & Q
              & " word and a\\slash and a\ttab",
            "quote, backslash and tab inside a doc line, got: " & Escaped);
      end;
   end Test_Doc_String_Escaping_Torture;

   procedure Test_Clean_Description
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Load ("1_first_scenario.feature");
      Assert
        (Escape_Json (Text (Doc, Feature (Doc).Head.Description))
         = "This is my cucumber-cpp hello world",
         "1_first_scenario.feature's one description line, escaped clean"
         & " -- never the oracle's own junk artifacts for the blank line"
         & " that follows it (p9 ruling: lean clean, ledgered)");
   end Test_Clean_Description;

   procedure Test_Description_Content_Multi_Line
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      J : Joined_Text;
   begin
      Load ("6_tables.feature");
      J := Description_Content (Doc, Feature (Doc).Head.Description);
      Assert (J.Ok, "four short lines fit");
      Assert
        (Value (J)
         = "We have three options: - raw access - rows hash - key/value"
           & " pairs",
         "the Ast's LF-joined lines re-joined with single spaces (the"
         & " oracle's own join), got: "
         & Value (J));
   end Test_Description_Content_Multi_Line;

   ---------------------------------------------------------------------
   --  Scenario ids: plain, under a Rule, an outline's occurrence.
   ---------------------------------------------------------------------

   procedure Test_Scenario_Id (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Scenario_Id ("F", "", "S", 0) = "F;S", "a plain scenario's id");
      Assert
        (Scenario_Id ("F", "R", "S", 0) = "F;R;S",
         "fabula's Rule attachment folded into the id (named divergence)");
      Assert
        (Scenario_Id ("F", "", "S", 1) = "(1) F;S",
         "an outline's first concrete scenario, the oracle's own prefix");
      Assert
        (Scenario_Id ("F", "", "S", 2) = "(2) F;S",
         "its second concrete scenario");
   end Test_Scenario_Id;

   --  Review correction: the oracle DOES fold the Rule into the id of
   --  the first scenario textually after a Rule header (source-read,
   --  probe-confirmed on a rebuilt oracle: two scenarios under one
   --  Rule give ids "probe;R;first" then "probe;second" -- only the
   --  SECOND drops the Rule). 9_rules.feature has exactly one scenario
   --  after its Rule, so this pins the kept-Rule case.
   procedure Test_Rule_Id_9_Rules (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Load ("9_rules.feature");
      Assert
        (Scenario (Doc, 2).Rule = 1, "the second scenario joins the rule");
      declare
         Feature_Name  : constant String :=
           Text (Doc, Feature (Doc).Head.Name);
         Rule_Name     : constant String :=
           Text (Doc, Rule (Doc, 1).Head.Name);
         Scenario_Name : constant String :=
           Text (Doc, Scenario (Doc, 2).Head.Name);
         Id            : constant String :=
           Scenario_Id (Feature_Name, Rule_Name, Scenario_Name, 0);
      begin
         Assert
           (Id = Feature_Name & ";" & Rule_Name & ";" & Scenario_Name,
            "the three names join with ';', got: " & Id);
         Assert
           (Id
            = "The Rules keyword;This is a rule, which helps me to"
              & " structure my feature file;An example is the same as a"
              & " scenario",
            "byte-pinned against the trimmed header titles, got: " & Id);
      end;
   end Test_Rule_Id_9_Rules;

   --  The oracle restarts an outline's "(N) " count at 1 for each
   --  Examples block rather than numbering across the whole scenario
   --  (source-read, probe-confirmed: a two-block, three-row outline
   --  gives ids "(1)", "(2)", "(1)"). This walks Fabula.Expand exactly
   --  as P10 must: track Ref.Block, reset the counter when it changes.
   procedure Test_Outline_Occurrence_Restarts_Per_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ref        : Example_Ref;
      Block      : Examples_Handle := 0;
      Occurrence : Natural := 0;
   begin
      Load_Lines
        ([+"Feature: f",
          +"  Scenario Outline: o",
          +"    Given x",
          +"    Examples:",
          +"      | a |",
          +"      | 1 |",
          +"      | 2 |",
          +"    Examples:",
          +"      | a |",
          +"      | 3 |"]);
      Ref := First_Example (Doc, 1);
      Assert (Ref.Block /= 0, "the first block has a data row");
      Block := Ref.Block;
      Occurrence := 1;
      Assert
        (Scenario_Id ("f", "", "o", Occurrence) = "(1) f;o", "block 1, row 1");
      Ref := Next_Example (Doc, 1, Ref);
      Occurrence := (if Ref.Block = Block then Occurrence + 1 else 1);
      Block := Ref.Block;
      Assert
        (Scenario_Id ("f", "", "o", Occurrence) = "(2) f;o", "block 1, row 2");
      Ref := Next_Example (Doc, 1, Ref);
      Occurrence := (if Ref.Block = Block then Occurrence + 1 else 1);
      Assert
        (Scenario_Id ("f", "", "o", Occurrence) = "(1) f;o",
         "block 2, row 1 restarts the count");
   end Test_Outline_Occurrence_Restarts_Per_Block;

   ---------------------------------------------------------------------
   --  The JSON structural glue: one step object, a feature/scenario
   --  envelope, a tags array, a table argument's full nesting.
   ---------------------------------------------------------------------

   --  The head of one JSON step object, through its "match" block: open
   --  brace, arguments, keyword, line, match/location, close. Split
   --  from the tail below to keep each routine's body short.
   --
   --  Ruling: "location" holds the matched step definition's
   --  registered pattern text (Fabula.Registry.Pattern_Text), stable
   --  and meaningful, where the oracle writes a C++ source path with
   --  no fabula analogue. Named divergence, ledgered in
   --  docs/report_wiring.md.
   function Step_Object_Head return String
   is (Open_Object (Step_Object_Depth)
       & ASCII.LF
       & Empty_Array_Field ("arguments", Step_Fields_Depth, True)
       & ASCII.LF
       & String_Field ("keyword", "Given", Step_Fields_Depth, True)
       & ASCII.LF
       & Number_Field ("line", 9, Step_Fields_Depth, True)
       & ASCII.LF
       & Open_Named_Object ("match", Step_Fields_Depth)
       & ASCII.LF
       & String_Field
           ("location", "An empty box", Match_Result_Fields_Depth, False)
       & ASCII.LF
       & Close_Object (Step_Fields_Depth, True));

   function Expected_Step_Object_Head return String
   is (Sp (Step_Object_Depth)
       & "{"
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & Q
       & "arguments"
       & Q
       & ": [],"
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & Q
       & "keyword"
       & Q
       & ": "
       & Q
       & "Given"
       & Q
       & ","
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & Q
       & "line"
       & Q
       & ": 9,"
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & Q
       & "match"
       & Q
       & ": {"
       & ASCII.LF
       & Sp (Match_Result_Fields_Depth)
       & Q
       & "location"
       & Q
       & ": "
       & Q
       & "An empty box"
       & Q
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & "},");

   --  The tail: name, the "result" block for a passed step, close brace.
   function Step_Object_Tail return String
   is (String_Field ("name", "An empty box", Step_Fields_Depth, True)
       & ASCII.LF
       & Open_Named_Object ("result", Step_Fields_Depth)
       & ASCII.LF
       & String_Field ("status", "passed", Match_Result_Fields_Depth, False)
       & ASCII.LF
       & Close_Object (Step_Fields_Depth, False)
       & ASCII.LF
       & Close_Object (Step_Object_Depth, False));

   function Expected_Step_Object_Tail return String
   is (Sp (Step_Fields_Depth)
       & Q
       & "name"
       & Q
       & ": "
       & Q
       & "An empty box"
       & Q
       & ","
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & Q
       & "result"
       & Q
       & ": {"
       & ASCII.LF
       & Sp (Match_Result_Fields_Depth)
       & Q
       & "status"
       & Q
       & ": "
       & Q
       & "passed"
       & Q
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & "}"
       & ASCII.LF
       & Sp (Step_Object_Depth)
       & "}");

   procedure Test_Json_Step_Object_Passed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Step_Object_Head = Expected_Step_Object_Head,
         "a passed step object's head, got: " & Step_Object_Head);
      Assert
        (Step_Object_Tail = Expected_Step_Object_Tail,
         "a passed step object's tail, got: " & Step_Object_Tail);
   end Test_Json_Step_Object_Passed;

   procedure Test_Json_Step_Object_Failed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result_Body : constant String :=
        String_Field
          ("error_message",
           Escape_Json ("Value 1 is not equal to 2"),
           Match_Result_Fields_Depth,
           True)
        & ASCII.LF
        & String_Field ("status", "failed", Match_Result_Fields_Depth, False);
   begin
      Assert
        (Result_Body
         = Sp (Match_Result_Fields_Depth)
           & Q
           & "error_message"
           & Q
           & ": "
           & Q
           & "Value 1 is not equal to 2"
           & Q
           & ","
           & ASCII.LF
           & Sp (Match_Result_Fields_Depth)
           & Q
           & "status"
           & Q
           & ": "
           & Q
           & "failed"
           & Q,
         "a failed step's result object: error_message before status,"
         & " alphabetical key order, got: "
         & Result_Body);
   end Test_Json_Step_Object_Failed;

   procedure Test_Json_Step_Object_Undefined
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result_Body : constant String :=
        String_Field
          ("error_message", "Undefined step", Match_Result_Fields_Depth, True)
        & ASCII.LF
        & String_Field
            ("status", "undefined", Match_Result_Fields_Depth, False);
   begin
      Assert
        (Result_Body
         = Sp (Match_Result_Fields_Depth)
           & Q
           & "error_message"
           & Q
           & ": "
           & Q
           & "Undefined step"
           & Q
           & ","
           & ASCII.LF
           & Sp (Match_Result_Fields_Depth)
           & Q
           & "status"
           & Q
           & ": "
           & Q
           & "undefined"
           & Q,
         "an undefined step's result object, got: " & Result_Body);
   end Test_Json_Step_Object_Undefined;

   function Feature_Head return String
   is (String_Field ("description", "", Feature_Fields_Depth, True)
       & ASCII.LF
       & Open_Array ("elements", Feature_Fields_Depth));

   function Expected_Feature_Head return String
   is (Sp (Feature_Fields_Depth)
       & Q
       & "description"
       & Q
       & ": "
       & Q
       & Q
       & ","
       & ASCII.LF
       & Sp (Feature_Fields_Depth)
       & Q
       & "elements"
       & Q
       & ": [");

   function Scenario_Head return String
   is (Open_Object (Scenario_Object_Depth)
       & ASCII.LF
       & String_Field ("description", "", Scenario_Fields_Depth, True)
       & ASCII.LF
       & String_Field ("id", "F;S", Scenario_Fields_Depth, True)
       & ASCII.LF
       & String_Field ("keyword", "Scenario", Scenario_Fields_Depth, True));

   function Expected_Scenario_Head return String
   is (Sp (Scenario_Object_Depth)
       & "{"
       & ASCII.LF
       & Sp (Scenario_Fields_Depth)
       & Q
       & "description"
       & Q
       & ": "
       & Q
       & Q
       & ","
       & ASCII.LF
       & Sp (Scenario_Fields_Depth)
       & Q
       & "id"
       & Q
       & ": "
       & Q
       & "F;S"
       & Q
       & ","
       & ASCII.LF
       & Sp (Scenario_Fields_Depth)
       & Q
       & "keyword"
       & Q
       & ": "
       & Q
       & "Scenario"
       & Q
       & ",");

   procedure Test_Json_Feature_Scenario_Envelope
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Feature_Head = Expected_Feature_Head,
         "the feature's head, got: " & Feature_Head);
      Assert
        (Scenario_Head = Expected_Scenario_Head,
         "one scenario's head, got: " & Scenario_Head);
   end Test_Json_Feature_Scenario_Envelope;

   --  "tags": ["@will_fail_before"], oracle-probed on 11_manual_fails.
   function Tags_Array return String
   is (Open_Array ("tags", Scenario_Fields_Depth)
       & ASCII.LF
       & String_Item ("@will_fail_before", Step_Object_Depth, False)
       & ASCII.LF
       & Close_Array (Scenario_Fields_Depth, False));

   function Expected_Tags_Array return String
   is (Sp (Scenario_Fields_Depth)
       & Q
       & "tags"
       & Q
       & ": ["
       & ASCII.LF
       & Sp (Step_Object_Depth)
       & Q
       & "@will_fail_before"
       & Q
       & ASCII.LF
       & Sp (Scenario_Fields_Depth)
       & "]");

   procedure Test_Json_Tags_Array (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Tags_Array = Expected_Tags_Array,
         "a one-tag array, got: " & Tags_Array);
   end Test_Json_Tags_Array;

   --  A table argument's full nesting: "arguments": [ { "rows": [ {
   --  "cells": [ "apple", "2" ] } ] } ], oracle byte-verified indent
   --  depths (report_tables.json: arguments 12, argument object 14,
   --  rows 16, row object 18, cells 20, cell items 22).
   function Table_Argument return String
   is (Open_Array ("arguments", Step_Fields_Depth)
       & ASCII.LF
       & Open_Object (Argument_Object_Depth)
       & ASCII.LF
       & Open_Array ("rows", Argument_Fields_Depth)
       & ASCII.LF
       & Open_Object (Row_Object_Depth)
       & ASCII.LF
       & Open_Array ("cells", Row_Fields_Depth)
       & ASCII.LF
       & String_Item ("apple", Cell_Item_Depth, True)
       & ASCII.LF
       & String_Item ("2", Cell_Item_Depth, False)
       & ASCII.LF
       & Close_Array (Row_Fields_Depth, False)
       & ASCII.LF
       & Close_Object (Row_Object_Depth, False)
       & ASCII.LF
       & Close_Array (Argument_Fields_Depth, False)
       & ASCII.LF
       & Close_Object (Argument_Object_Depth, False)
       & ASCII.LF
       & Close_Array (Step_Fields_Depth, False));

   function Expected_Table_Argument return String
   is (Sp (Step_Fields_Depth)
       & Q
       & "arguments"
       & Q
       & ": ["
       & ASCII.LF
       & Sp (Argument_Object_Depth)
       & "{"
       & ASCII.LF
       & Sp (Argument_Fields_Depth)
       & Q
       & "rows"
       & Q
       & ": ["
       & ASCII.LF
       & Sp (Row_Object_Depth)
       & "{"
       & ASCII.LF
       & Sp (Row_Fields_Depth)
       & Q
       & "cells"
       & Q
       & ": ["
       & ASCII.LF
       & Sp (Cell_Item_Depth)
       & Q
       & "apple"
       & Q
       & ","
       & ASCII.LF
       & Sp (Cell_Item_Depth)
       & Q
       & "2"
       & Q
       & ASCII.LF
       & Sp (Row_Fields_Depth)
       & "]"
       & ASCII.LF
       & Sp (Row_Object_Depth)
       & "}"
       & ASCII.LF
       & Sp (Argument_Fields_Depth)
       & "]"
       & ASCII.LF
       & Sp (Argument_Object_Depth)
       & "}"
       & ASCII.LF
       & Sp (Step_Fields_Depth)
       & "]");

   procedure Test_Json_Table_Argument
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Table_Argument = Expected_Table_Argument,
         "a table argument's full nesting, got: " & Table_Argument);
   end Test_Json_Table_Argument;

   ---------------------------------------------------------------------

   procedure Add_Scalar_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Escape_Json_Plain'Access, "plain text escapes to itself");
      Register_Routine
        (T,
         Test_Escape_Json_Torture'Access,
         "quotes, backslash, newline and tab");
      Register_Routine
        (T,
         Test_Escape_Json_Control_Chars'Access,
         "CR, backspace, form feed and lowercase \u00xx");
      Register_Routine
        (T,
         Test_Doc_String_Content_Space_Joined'Access,
         "a doc string's JSON content, space-joined");
      Register_Routine
        (T,
         Test_Doc_String_Escaping_Torture'Access,
         "a doc string's content, escaped");
      Register_Routine
        (T, Test_Clean_Description'Access, "the clean-description ruling");
      Register_Routine
        (T,
         Test_Description_Content_Multi_Line'Access,
         "a multi-line description, space-joined");
   end Add_Scalar_Tests;

   procedure Add_Id_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Scenario_Id'Access, "scenario ids");
      Register_Routine
        (T, Test_Rule_Id_9_Rules'Access, "the first scenario after a Rule");
      Register_Routine
        (T,
         Test_Outline_Occurrence_Restarts_Per_Block'Access,
         "an outline's occurrence restarts per Examples block");
   end Add_Id_Tests;

   procedure Add_Structural_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Json_Step_Object_Passed'Access, "a passed step's JSON");
      Register_Routine
        (T, Test_Json_Step_Object_Failed'Access, "a failed step's result");
      Register_Routine
        (T,
         Test_Json_Step_Object_Undefined'Access,
         "an undefined step's result");
      Register_Routine
        (T,
         Test_Json_Feature_Scenario_Envelope'Access,
         "the feature and scenario JSON envelopes");
      Register_Routine (T, Test_Json_Tags_Array'Access, "a tags array");
      Register_Routine
        (T,
         Test_Json_Table_Argument'Access,
         "a table argument's full nesting");
   end Add_Structural_Tests;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Add_Scalar_Tests (T);
      Add_Id_Tests (T);
      Add_Structural_Tests (T);
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Format (JSON structural glue)"));

end Fabula_Format_Json_Tests;
