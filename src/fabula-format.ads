--  Console and JSON text building: every function returns one bounded
--  piece (a line, a JSON fragment) built from data the caller already
--  holds. Nothing here touches IO; Fabula.Shell writes what these
--  functions return, styled and sequenced as it sees fit. A stored
--  node range is a value, not a proof of its own bounds: every walk
--  guards its index against the Document's pool count, so a stale
--  handle renders as empty rather than reading past a pool. See
--  docs/report_wiring.md for the full call sequence and rulings.
with Fabula.Ast;
with Fabula.Limits;
with Fabula.Parse;
with Fabula.Results;

package Fabula.Format
  with SPARK_Mode
is

   use type Ast.Table_Handle;
   use type Parse.Error_Kind;

   ---------------------------------------------------------------------
   --  Styling. Pairs one for one with Fabula.Shell.Console.Style, minus
   --  its Verbose role: the caller applies that one style uniformly to
   --  everything the Verbose lines below return, so no per-piece Role
   --  is needed for them. The shell maps Role to Style when it prints
   --  a piece, keeping this package free of the shell's IO and
   --  environment concerns.
   ---------------------------------------------------------------------

   type Role is (Plain, Passed, Failed, Skipped, Undefined, Location, Error);

   function Style_Of (S : Results.Status) return Role
   is (case S is
         when Results.Passed    => Passed,
         when Results.Failed    => Failed,
         when Results.Skipped   => Skipped,
         when Results.Undefined => Undefined);

   ---------------------------------------------------------------------
   --  Status words and the bracket label each step line opens with.
   ---------------------------------------------------------------------

   function Status_Word (S : Results.Status) return String
   with Post => Status_Word'Result'Length in 6 .. 9;
   --  "PASSED", "FAILED", "SKIPPED", "UNDEFINED".

   Bracket_Label_Length : constant := 16;
   --  "[" & 3 spaces & word & padding & "] ": the reference
   --  interpreter's step_prefix, byte-verified against the oracle.

   function Bracket_Label (S : Results.Status) return String
   with Post => Bracket_Label'Result'Length = Bracket_Label_Length;
   --  "[   PASSED    ] ", "[   FAILED    ] ", "[   SKIPPED   ] ",
   --  "[   UNDEFINED ] " -- printed with Style_Of (S).

   ---------------------------------------------------------------------
   --  Header, step and location text. A Feature/Rule/Background/
   --  Scenario/Outline header prints Header_Text then Location_Text; a
   --  step prints Bracket_Label (styled) then Step_Text then the same
   --  Location_Text. Location prints with role Location (gray);
   --  Header_Text and Step_Text are Plain.
   ---------------------------------------------------------------------

   Max_Piece : constant := Limits.Max_Report_Line_Length;

   function Header_Text (Keyword, Name : String) return String
   with Pre => Keyword'Length + 2 + Name'Length <= Max_Piece;
   --  "<Keyword>: <Name>".

   function Step_Text (Keyword, Text : String) return String
   with Pre => Keyword'Length + 1 + Text'Length <= Max_Piece;
   --  "<Keyword> <Text>" -- a "*" keyword prints "* Text", the same
   --  one-space rule as every other keyword.

   Location_Extra : constant := 24;
   --  Two leading spaces, a colon and headroom for the line number's
   --  digits (Natural's widest 'Image is ten digits).

   function Location_Text (File : String; Line_No : Natural) return String
   with Pre => File'Length <= Max_Piece - Location_Extra;
   --  "  <File>:<Line_No>".

   ---------------------------------------------------------------------
   --  Tables. A table's columns are widened to the longest resolved
   --  cell first, then each row renders against that width.
   ---------------------------------------------------------------------

   type Column_Widths is array (1 .. Limits.Max_Table_Columns) of Natural;

   --  The resolved width of each of T's columns, all 0 for a stale T
   --  (0 or past the Document's current table count) and 0 past a
   --  column's own count or a stale stored index (never read past a
   --  pool). A cell whose resolution does not fit (Expand.Resolved
   --  Ok = False) counts as width 0: the shipped corpus and examples
   --  never hit this, so it is a defined fallback, not a probed rule.
   function Table_Widths
     (Doc        : Ast.Document;
      T          : Ast.Table_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Column_Widths;

   --  "  | c1 | c2 |", Row's cells resolved and padded to Widths. A
   --  stale Row (past the current row pool) renders as "  |".
   function Table_Row_Text
     (Doc        : Ast.Document;
      Row        : Ast.Row_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle;
      Widths     : Column_Widths) return String;

   ---------------------------------------------------------------------
   --  Doc strings. The reference interpreter always prints "\"\"\"",
   --  whatever fence the source used; content lines print one per
   --  console line, resolved, with no added indentation (the reference
   --  interpreter's own console printer adds none for a doc string,
   --  unlike its table printer).
   ---------------------------------------------------------------------

   Doc_Fence_Text : constant String := """""""";

   --  L's resolved text, or "" for a stale L (past the current doc-line
   --  pool).
   function Doc_Content_Text
     (Doc        : Ast.Document;
      L          : Ast.Doc_Line_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return String;

   ---------------------------------------------------------------------
   --  Count summaries. Each category prints only when its count is
   --  above zero (probe-verified: a zero-scenario run prints
   --  "0 Scenario ()"); the whole line is plain text -- the reference
   --  interpreter colors each category, but that is a TTY-only effect
   --  invisible once NO_COLOR or a non-terminal output strips it, so
   --  per-category coloring is out of this phase's scope.
   ---------------------------------------------------------------------

   function Scenarios_Summary (C : Results.Counts) return String;
   --  "<n> Scenario(s) (<failed>, <skipped>, <passed>)", each category
   --  omitted when zero, no scenario "undefined" category (the
   --  reference interpreter has none: Fabula.Results never reports a
   --  scenario Undefined either).

   function Steps_Summary (C : Results.Counts) return String;
   --  "<n> Step(s) (<failed>, <undefined>, <skipped>, <passed>)".

   ---------------------------------------------------------------------
   --  The failed-scenarios trailer. Filled by the caller from
   --  Scenario_Closed notices; TDD plan item 6 covers fill, overflow
   --  saturation (silent -- a report is best-effort, not a refusal
   --  surface) and render.
   ---------------------------------------------------------------------

   Failed_Scenarios_Header : constant String := "Failed Scenarios:";

   subtype Failed_Scenario_Count is
     Natural range 0 .. Limits.Max_Failed_Scenarios;

   --  About 200 KB at the shipped capacity: a caller's Failed_Store
   --  belongs at library level, never on a task's stack (the same
   --  rule Fabula.Shell.Files states for its own File_List).
   type Failed_Store is private;

   Empty_Failed_Store : constant Failed_Store;

   function Failed_Count (Store : Failed_Store) return Failed_Scenario_Count;

   function Has_Failures (Store : Failed_Store) return Boolean
   is (Failed_Count (Store) > 0);

   --  Records one failed scenario; once Store is full, further calls
   --  are no-ops and the earliest entries still render.
   procedure Add_Failed
     (Store : in out Failed_Store; Name, File : String; Line_No : Natural)
   with
     Pre  =>
       Name'Length <= Limits.Max_Name_Length
       and then File'Length <= Limits.Max_Path_Length,
     Post =>
       Failed_Count (Store)
       = Natural'Min
           (Failed_Count (Store)'Old + 1, Limits.Max_Failed_Scenarios);

   function Failed_Name (Store : Failed_Store; I : Positive) return String
   with Pre => I <= Failed_Count (Store);

   function Failed_File (Store : Failed_Store; I : Positive) return String
   with Pre => I <= Failed_Count (Store);

   function Failed_Line (Store : Failed_Store; I : Positive) return Natural
   with Pre => I <= Failed_Count (Store);

   ---------------------------------------------------------------------
   --  -v's non-hook lines, byte-copied from the oracle (docs/
   --  report_wiring.md has each probe). The hook "executing hook" /
   --  "not executing hook" lines stay out: no notice carries which
   --  hooks ran or were skipped, a ledgered gap, not a Format gap.
   ---------------------------------------------------------------------

   Verbose_Separator : constant String :=
     "[   VERBOSE   ] ----------------------------------";

   function Verbose_Scenario_Start
     (Name : String; File : String; Line_No : Natural) return String
   with Pre => File'Length <= Limits.Max_Path_Length;
   --  "[   VERBOSE   ] Scenario Start '<Name>' - File: <File>:<Line_No>".

   No_Tags_Given : constant String :=
     "[   VERBOSE   ] No tags given, continuing";

   --  The two-line tag check: "[   VERBOSE   ] Scenario tags '<Tags>'"
   --  then, indented to align, "checked against tag expression
   --  '<Expression>' -> '<True/False>', <continuing/stopping>".
   function Verbose_Tag_Check
     (Tags : String; Expression : String; Passed : Boolean) return String;

   Verbose_Skip : constant String :=
     "[   VERBOSE   ] Scenario skipped with 'skip_scenario'";

   Verbose_Ignore : constant String :=
     "[   VERBOSE   ] Scenario ignored with 'ignore_scenario'";

   Verbose_End : constant String := "[   VERBOSE   ] Scenario end";

   ---------------------------------------------------------------------
   --  Parse-error lines. A Refusal carries only a kind and a line
   --  (Fabula.Parse); the caller supplies the file, whether the
   --  refusal came from Finish (end of input, no next token) or Feed
   --  (a line the grammar rejected), and that line's raw text so
   --  First_Token can name the offending token, matching the oracle's
   --  three lexer shapes.
   ---------------------------------------------------------------------

   function Parse_Message (Kind : Parse.Error_Kind) return String
   with Pre => Kind /= Parse.None;
   --  The oracle's own wording where a probe or its source pins one --
   --  Tag_Line_Malformed included, the oracle's own analogue reached
   --  once its tag scan stops at the first non-tag token (see
   --  docs/report_wiring.md). fabula's own wording, ledgered as a
   --  named divergence, only for Pool_Exhausted (no oracle analogue)
   --  and the never-produced Expected_Examples_Table.

   function First_Token (Text : String) return String
   with Pre => Text'Length <= Limits.Max_Line_Length;
   --  The first run of non-blank characters in Text, empty when Text
   --  is blank or empty.

   function First_Bad_Tag_Token (Text : String) return String
   with Pre => Text'Length <= Limits.Max_Line_Length;
   --  The first token in Text that does not open a tag ('@...'),
   --  skipping whitespace and whole tag tokens first -- the oracle's
   --  own tag scanner stops here too. Empty when every token tags.

   function Parse_Error_Text
     (File    : String;
      Line_No : Natural;
      Kind    : Parse.Error_Kind;
      At_End  : Boolean;
      Token   : String) return String
   with
     Pre =>
       Kind /= Parse.None
       and then File'Length <= Limits.Max_Path_Length
       and then Token'Length <= Limits.Max_Line_Length;
   --  "<File>:<Line_No>: Error at '<Token>': <message>" when At_End is
   --  False and Kind takes a token (Tag_Line_Malformed names the first
   --  non-tag token via First_Bad_Tag_Token, not Token's own first
   --  word); "...: Error at end: <message>" when At_End is True;
   --  "...: Error : <message>" for the two kinds with no offending
   --  token (Unterminated_Doc_String, Pool_Exhausted) -- Token is then
   --  ignored.

   Parse_Error_Trailer : constant String := "Error while parsing script";

   ---------------------------------------------------------------------
   --  JSON. The key set, nesting and alphabetical key order are probed
   --  byte-for-byte against a rebuilt oracle binary (docs/report_wiring
   --  .md has the full transcript). Depth is the nesting level the
   --  schema fixes each field at, one more than the object or array
   --  that holds it; twice Depth gives the indent the probe confirms.
   ---------------------------------------------------------------------

   Feature_Fields_Depth      : constant := 2;
   Scenario_Object_Depth     : constant := 3;
   Scenario_Fields_Depth     : constant := 4;
   Step_Object_Depth         : constant := 5;
   Step_Fields_Depth         : constant := 6;
   Match_Result_Fields_Depth : constant := 7;
   Argument_Object_Depth     : constant := 7;
   Argument_Fields_Depth     : constant := 8;
   Row_Object_Depth          : constant := 9;
   Row_Fields_Depth          : constant := 10;
   Cell_Item_Depth           : constant := 11;

   Max_Depth : constant := 16;
   --  Comfortably above Cell_Item_Depth, the deepest field this schema
   --  nests; a Depth beyond this is a defect in the caller, not a
   --  reachable JSON shape, and every glue function below is bounded
   --  by it so its own indentation provably fits a String result.

   subtype Depth_Value is Positive range 1 .. Max_Depth;

   function Escape_Json (Source : String) return String
   with
     Pre  => Source'Length <= Limits.Max_Line_Length,
     Post => Escape_Json'Result'Length <= Limits.Max_Escaped_Text_Length;
   --  Source with '"', '\' and every control character escaped
   --  ('\n', '\r', '\t', '\b', '\f' by name, else "\u00XX"). Every
   --  other Format function that emits JSON text takes its String
   --  fields already escaped -- Format never escapes the same text
   --  twice.

   type Joined_Text is record
      Ok  : Boolean := False;
      Len : Natural range 0 .. Limits.Max_Line_Length := 0;
      Val : String (1 .. Limits.Max_Line_Length) := [others => ' '];
   end record;

   function Value (J : Joined_Text) return String
   is (J.Val (1 .. J.Len));

   --  D's content lines, space-joined, one string (probe-verified: the
   --  oracle's own JSON report joins doc-string lines with a single
   --  space, not a newline, unlike its per-line console printer). Ok
   --  is False when the join would not fit Max_Line_Length; the
   --  shipped corpus and examples never hit this.
   function Doc_String_Content
     (Doc        : Ast.Document;
      D          : Ast.Doc_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Joined_Text;

   --  S's stored lines (the Ast joins a header's description with LF),
   --  re-joined with a single space each -- the reference interpreter's
   --  own join. Ok is False, and Value a safely truncated prefix, when
   --  the join would not fit Max_Line_Length.
   function Description_Content
     (Doc : Ast.Document; S : Ast.Slice) return Joined_Text;

   --  A scenario's id: "<Feature_Name>;<Scenario_Name>", or, under a
   --  Rule, "<Feature_Name>;<Rule_Name>;<Scenario_Name>". Occurrence is
   --  0 for a plain scenario; for an outline's concrete scenario the
   --  id gains a "(N) " prefix, N the row's 1-based position within
   --  its OWN Examples block (never across the whole scenario -- the
   --  caller resets its counter on every block change). See
   --  docs/report_wiring.md for the Rule-folding divergence this
   --  encodes and the probes behind both rules.
   function Scenario_Id
     (Feature_Name  : String;
      Rule_Name     : String;
      Scenario_Name : String;
      Occurrence    : Natural) return String
   with
     Pre  =>
       Feature_Name'Length <= Limits.Max_Name_Length
       and then Rule_Name'Length <= Limits.Max_Name_Length
       and then Scenario_Name'Length <= Limits.Max_Name_Length,
     Post => Scenario_Id'Result'Length <= Limits.Max_Escaped_Text_Length;

   --  Structural glue, generic over the schema's fixed depths above.
   --  More is True when a sibling field follows and a trailing comma
   --  is needed.

   function Open_Object (Depth : Depth_Value) return String
   with Post => Open_Object'Result'Length = 2 * Depth + 1;

   --  "match" and "result" open on the same line as their key (the
   --  probe: `"match": {`), unlike an array's own items, which open on
   --  a line of their own -- Open_Object above.
   function Open_Named_Object (Key : String; Depth : Depth_Value) return String
   with Pre => Key'Length <= Limits.Max_Name_Length;

   function Close_Object (Depth : Depth_Value; More : Boolean) return String
   with
     Post => Close_Object'Result'Length = 2 * Depth + (if More then 2 else 1);

   function Open_Array (Key : String; Depth : Depth_Value) return String
   with Pre => Key'Length <= Limits.Max_Name_Length;

   function Close_Array (Depth : Depth_Value; More : Boolean) return String
   with
     Post => Close_Array'Result'Length = 2 * Depth + (if More then 2 else 1);

   function Empty_Array_Field
     (Key : String; Depth : Depth_Value; More : Boolean) return String
   with Pre => Key'Length <= Limits.Max_Name_Length;

   function String_Field
     (Key, Escaped_Value : String; Depth : Depth_Value; More : Boolean)
      return String
   with
     Pre  =>
       Key'Length <= Limits.Max_Name_Length
       and then Escaped_Value'Length <= Limits.Max_Escaped_Text_Length,
     Post => String_Field'Result'Length > 0;

   --  A bare string inside an array with no key of its own -- one tag,
   --  one table cell. Every array of strings the reference interpreter
   --  emits ("tags", a row's "cells") uses this shape, never
   --  String_Field's.
   function String_Item
     (Escaped_Value : String; Depth : Depth_Value; More : Boolean)
      return String
   with Pre => Escaped_Value'Length <= Limits.Max_Escaped_Text_Length;

   function Number_Field
     (Key : String; Value : Natural; Depth : Depth_Value; More : Boolean)
      return String
   with Pre => Key'Length <= Limits.Max_Name_Length;

private

   type Failed_Entry is record
      Name     : String (1 .. Limits.Max_Name_Length) := [others => ' '];
      Name_Len : Natural range 0 .. Limits.Max_Name_Length := 0;
      File     : String (1 .. Limits.Max_Path_Length) := [others => ' '];
      File_Len : Natural range 0 .. Limits.Max_Path_Length := 0;
      Line     : Natural := 0;
   end record;

   type Failed_Entries is
     array (1 .. Limits.Max_Failed_Scenarios) of Failed_Entry;

   type Failed_Store is record
      Count : Failed_Scenario_Count := 0;
      Items : Failed_Entries;
   end record;

   Empty_Failed_Store : constant Failed_Store :=
     (Count => 0, Items => [others => <>]);

   function Failed_Count (Store : Failed_Store) return Failed_Scenario_Count
   is (Store.Count);

end Fabula.Format;
