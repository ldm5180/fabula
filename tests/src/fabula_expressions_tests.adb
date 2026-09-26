with AUnit.Assertions;      use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Limits;
with Fabula.Expressions; use Fabula.Expressions;

package body Fabula_Expressions_Tests is

   use AUnit.Test_Cases.Registration;

   function "+" (Source : String) return Unbounded_String
   renames To_Unbounded_String;

   --  The expectation a row gives when the step text must not match.
   No_Match : constant String := "(no match)";

   --  One pattern, one step text, and the captures the reference
   --  interpreter reports for them.  Captures render as KIND:text; in
   --  order, so a match with no captures renders as the empty string.
   type Case_Record is record
      Pattern : Unbounded_String;
      Text    : Unbounded_String;
      Expect  : Unbounded_String;
   end record;

   type Case_Array is array (Positive range <>) of Case_Record;

   HT : constant String := [1 => ASCII.HT];
   VT : constant String := [1 => ASCII.VT];
   FF : constant String := [1 => ASCII.FF];
   CR : constant String := [1 => ASCII.CR];
   LF : constant String := [1 => ASCII.LF];

   --  Each row is one reference fuzz seed: the seed's first line is the
   --  pattern and its second line the step text.
   Seed_Cases : constant Case_Array :=
     [--  Reference seed basic_int.
      (+"The stock count should be {int}",
       +"The stock count should be 5",
       +"P_INT:5;"),
      --  Reference seed basic_int_string.
      (+"I place {int} x {string} in it",
       +"I place 5 x ""book"" in it",
       +"P_INT:5;P_STRING:book;"),
      --  Reference seed anon.
      (+"I have {}",
       +"I have anything at all",
       +"P_ANONYMOUS:anything at all;"),
      --  Reference seed anonymous_then_literal_brace_count.
      (+"I have {}{56} things", +"I have foo{56} things", +"P_ANONYMOUS:foo;"),
      --  Reference seed escaped.
      (+"Literal parens \(and braces\) in {word}",
       +"Literal parens (and braces) in text",
       +"P_WORD:text;"),
      --  Reference seed no_params.
      (+"no params at all", +"no params at all", +""),
      --  Reference seed word.
      (+"I have {word}", +"I have hello", +"P_WORD:hello;")];

   --  The documented optional-plural and is/are examples.
   Doc_Cases : constant Case_Array :=
     [(+"The box contains {int} item(s)",
       +"The box contains 2 items",
       +"P_INT:2;"),
      (+"The box contains {int} item(s)",
       +"The box contains 1 item",
       +"P_INT:1;"),
      (+"{int} item(s) is/are {string}",
       +"2 items are ""x""",
       +"P_INT:2;P_STRING:x;"),
      (+"{int} item(s) is/are {string}",
       +"1 item is ""y""",
       +"P_INT:1;P_STRING:y;")];

   --  Parameters take the longest text first and give it back only
   --  when the rest of the pattern fails.
   Greedy_Cases : constant Case_Array :=
     [(+"a {} b", +"a x b y b", +"P_ANONYMOUS:x b y;"),
      (+"{} {}", +"a b c", +"P_ANONYMOUS:a b;P_ANONYMOUS:c;"),
      (+"x{}y{}z", +"xAyByCz", +"P_ANONYMOUS:AyB;P_ANONYMOUS:C;"),
      (+"{int}{int}", +"123", +"P_INT:12;P_INT:3;"),
      (+"{word} {word}", +"a b c", +No_Match),
      (+"{word}(s)", +"cats", +"P_WORD:cats;"),
      (+"{} {} {} x", +"a b c d e f g h i j k", +No_Match),
      (+"{int} x", +"5 y", +No_Match)];

   --  A word, an anonymous parameter and a quoted string may each
   --  capture nothing; an integer may not.
   Empty_Cases : constant Case_Array :=
     [(+"a {word} b", +"a  b", +"P_WORD:;"),
      (+"a {} b", +"a  b", +"P_ANONYMOUS:;"),
      (+"x{}", +"x", +"P_ANONYMOUS:;"),
      (+"s {string}", +"s """"", +"P_STRING:;"),
      (+"{word}", +"", +"P_WORD:;"),
      (+"{}", +"", +"P_ANONYMOUS:;"),
      (+"{int}", +"", +No_Match)];

   --  Real numbers: an optional sign, optional digits, an optional
   --  point, then at least one digit.
   Real_Cases : constant Case_Array :=
     [(+"v {float}", +"v .5", +"P_FLOAT:.5;"),
      (+"v {float}", +"v -.5", +"P_FLOAT:-.5;"),
      (+"v {double}", +"v -0.25", +"P_DOUBLE:-0.25;"),
      (+"v {float}", +"v 7", +"P_FLOAT:7;"),
      (+"v {float}", +"v 5.", +No_Match),
      (+"v {float}", +"v -", +No_Match),
      (+"v {int}", +"v -", +No_Match),
      (+"v {double}", +"v 1.2.3", +No_Match),
      (+"v {float}.", +"v 5.", +"P_FLOAT:5;"),
      (+"{float}.5", +"1.5.5", +"P_FLOAT:1.5;"),
      (+"{float}.5", +"1.5", +"P_FLOAT:1;"),
      (+"{float}", +".", +No_Match),
      --  A point must be followed by a digit, so 1. is never a number,
      --  even when the pattern could use the digit after the point.
      (+"{float}5", +"1.5", +No_Match),
      (+"{float}5", +"1.55", +"P_FLOAT:1.5;"),
      (+"{double}5", +"-1.5", +No_Match),
      (+"{int}", +"--5", +No_Match),
      (+"v {int}", +"v 1.5", +No_Match),
      (+"{byte} {short} {long} {double}",
       +"1 -2 3 4.5",
       +"P_BYTE:1;P_SHORT:-2;P_LONG:3;P_DOUBLE:4.5;")];

   --  A backslash makes the next parenthesis or brace literal; before
   --  any other character it is itself a literal backslash.
   Escape_Cases : constant Case_Array :=
     [(+"\{int\}", +"{int}", +""),
      (+"\{int\}", +"5", +No_Match),
      (+"item\(s\)", +"item(s)", +""),
      (+"item\(s\)", +"items", +No_Match),
      (+"\{{int}\}", +"{5}", +"P_INT:5;"),
      (+"a\b", +"a\b", +""),
      (+"a\/b", +"a\/b", +""),
      (+"a\", +"a\", +""),
      (+"\(a/b\)", +"(b)", +"")];

   --  word/word is a two-way choice.  A slash right after a choice is
   --  literal, so a/b/c is a choice of a or b followed by /c.
   Alternation_Cases : constant Case_Array :=
     [(+"a/b/c", +"a/c", +""),
      (+"a/b/c", +"b/c", +""),
      (+"a/b/c", +"c", +No_Match),
      (+"a/b/c", +"a/b/c", +No_Match),
      (+"a/b/c/d", +"b/d", +""),
      (+"ratio 1/2", +"ratio 1", +""),
      (+"ratio 1/2", +"ratio 1/2", +No_Match),
      (+"a/ab", +"ab", +""),
      (+"(x)yz/w", +"xw", +""),
      (+"a_b/c", +"a_b", +""),
      (+"x/(y)", +"x/", +""),
      (+"a /b", +"a /b", +""),
      (+"{int}s/x", +"5x", +"P_INT:5;"),
      (+"item(s)/things", +"item/things", +"")];

   --  Braces around digits with at most one comma are literal text, and
   --  so are a lone brace and an escaped one.  Every other character is
   --  literal too.  The reference interpreter reads | as a regex choice
   --  and throws on some lone or escaped braces; fabula keeps them
   --  literal.
   Literal_Cases : constant Case_Array :=
     [(+"x {56} y", +"x {56} y", +""),
      (+"x {2,} y", +"x {2,} y", +""),
      (+"x {1,3} y", +"x {1,3} y", +""),
      (+"x {,5} y", +"x {,5} y", +""),
      (+"}x{", +"}x{", +""),
      (+"{foo", +"{foo", +""),
      (+"\{foo}", +"{foo}", +""),
      (+"{foo\}", +"{foo}", +""),
      (+"a|b", +"a|b", +""),
      (+"a|b", +"a", +No_Match),
      (+"a.b", +"axb", +No_Match),
      (+"cost $5?", +"cost $5?", +"")];

   --  The whole step text must match, not a part of it.
   Anchor_Cases : constant Case_Array :=
     [(+"box", +"a box", +No_Match),
      (+"box", +"box ", +No_Match),
      (+"box", +"box", +""),
      (+"", +"", +""),
      (+"", +"x", +No_Match)];

   --  A group may hold any pattern, parameters included.  A parameter
   --  in a group that is skipped reports no capture.
   Optional_Cases : constant Case_Array :=
     [(+"I have( {int}) apples", +"I have 3 apples", +"P_INT:3;"),
      (+"I have( {int}) apples", +"I have apples", +""),
      (+"a( {int}) {int}", +"a 1 2", +"P_INT:1;P_INT:2;"),
      (+"a( {int}) {int}", +"a 1", +"P_INT:1;"),
      (+"x({word})", +"x", +"P_WORD:;"),
      (+"(is/are )x", +"are x", +""),
      (+"(is/are )x", +"x", +""),
      (+"((a)b)c", +"bc", +""),
      (+"((a)b)c", +"ac", +No_Match),
      (+"()x", +"x", +""),
      (+"(s)s", +"s", +"")];

   --  A word stops at any of the six whitespace characters; an
   --  anonymous parameter stops only at a line break; a quoted string
   --  stops at the first closing quote.
   Class_Cases : constant Case_Array :=
     [(+"w {word}", +("w a" & HT & "b"), +No_Match),
      (+"w {word}", +("w a" & VT & "b"), +No_Match),
      (+"w {word}", +("w a" & FF & "b"), +No_Match),
      (+"w {word}", +("w a" & CR & "b"), +No_Match),
      (+"w {word}", +("w a" & LF & "b"), +No_Match),
      (+"{} end", +("x" & CR & "z end"), +No_Match),
      (+"{} end", +("x" & LF & "z end"), +No_Match),
      (+"{}", +("a" & HT & "b"), +("P_ANONYMOUS:a" & HT & "b;")),
      (+"{string}", +"""a""b""", +No_Match),
      (+"{string}""", +"""a""""", +"P_STRING:a;"),
      (+"{string} and {string}",
       +"""a b"" and ""c""",
       +"P_STRING:a b;P_STRING:c;"),
      (+"{string}", +"""open", +No_Match)];

   function Render (Text : String; Captures : Capture_List) return String is
      Result : Unbounded_String;
   begin
      for I in 1 .. Captures.Count loop
         declare
            Item : constant Capture := Captures.Items (I);
         begin
            Append
              (Result,
               Item.Kind'Image & ":" & Text (Item.First .. Item.Last) & ";");
         end;
      end loop;
      return To_String (Result);
   end Render;

   procedure Check (Pattern : String; Text : String; Expect : String) is
      Where    : constant String :=
        "pattern """ & Pattern & """, text """ & Text & """";
      P        : Compiled;
      Ok       : Boolean;
      Captures : Capture_List;
      Matched  : Boolean;
   begin
      Compile (Pattern, P, Ok);
      Assert (Ok, Where & ": the pattern must compile");
      Match (P, Text, Captures, Matched);
      if Expect = No_Match then
         Assert (not Matched, Where & ": expected no match");
         Assert
           (Captures.Count = 0,
            Where & ": a failed match must report no captures");
      else
         Assert (Matched, Where & ": expected a match");
         Assert
           (Render (Text, Captures) = Expect,
            Where
            & ": expected captures """
            & Expect
            & """, got """
            & Render (Text, Captures)
            & """");
      end if;
   end Check;

   procedure Run_Cases (Cases : Case_Array) is
   begin
      for C of Cases loop
         Check
           (To_String (C.Pattern), To_String (C.Text), To_String (C.Expect));
      end loop;
   end Run_Cases;

   --  A refused pattern reports Ok = False and then matches nothing.
   procedure Check_Refused (Pattern : String) is
      Text     : constant String (1 .. Pattern'Length) := Pattern;
      P        : Compiled;
      Ok       : Boolean;
      Captures : Capture_List;
      Matched  : Boolean;
   begin
      Compile (Pattern, P, Ok);
      Assert (not Ok, "pattern """ & Pattern & """ must be refused");
      Match (P, Text, Captures, Matched);
      Assert
        (not Matched and then Captures.Count = 0,
         "refused pattern """ & Pattern & """ must match nothing");
   end Check_Refused;

   procedure Test_Seeds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Seed_Cases);
   end Test_Seeds;

   procedure Test_Doc_Examples (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Doc_Cases);
   end Test_Doc_Examples;

   procedure Test_Greedy (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Greedy_Cases);
   end Test_Greedy;

   procedure Test_Empty_Captures (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run_Cases (Empty_Cases);
   end Test_Empty_Captures;

   procedure Test_Reals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Real_Cases);
   end Test_Reals;

   procedure Test_Escapes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Escape_Cases);
   end Test_Escapes;

   procedure Test_Alternation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Alternation_Cases);
   end Test_Alternation;

   procedure Test_Literals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Literal_Cases);
   end Test_Literals;

   procedure Test_Anchoring (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Anchor_Cases);
   end Test_Anchoring;

   procedure Test_Optionals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Optional_Cases);
   end Test_Optionals;

   procedure Test_Char_Classes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Class_Cases);
   end Test_Char_Classes;

   procedure Test_Refusals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Args : constant Positive := Fabula.Limits.Max_Args_Per_Step;
   begin
      --  One parameter more than a step can pass is refused; exactly
      --  the capacity compiles and captures every one.
      Check_Refused (To_String ((Args + 1) * "{int}"));
      Check
        (To_String (Args * "{int} ") & "x",
         To_String (Args * "7 ") & "x",
         To_String (Args * "P_INT:7;"));
      --  Each (s) costs two tokens, a group and its literal, so half the
      --  token capacity of them compiles and one more is refused.
      Check
        (To_String ((Fabula.Limits.Max_Pattern_Tokens / 2) * "(s)"), "", "");
      Check_Refused
        (To_String ((Fabula.Limits.Max_Pattern_Tokens / 2 + 1) * "(s)"));
      --  Unbalanced parentheses cannot compile.
      Check_Refused ("(a");
      Check_Refused ("a)");
      Check_Refused ("a\\(b)");
   end Test_Refusals;

   --  A brace group, from an unescaped { to the first } that closes it,
   --  must be one of the nine keys or digits with at most one comma.
   --  Anything else is refused, so a mistyped key fails at compile time
   --  instead of never matching.  Keys are case-sensitive.
   procedure Test_Unknown_Keys (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Refused ("{foo}");
      Check_Refused ("I have {foo} items");
      Check_Refused ("{Int}");
      Check_Refused ("{ int}");
      Check_Refused ("a {in(t)} b");
      Check_Refused ("{,}");
      Check_Refused ("{5,,}");
      Check_Refused ("{{int}}");
   end Test_Unknown_Keys;

   procedure Test_Uncompiled (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      P        : Compiled;
      Captures : Capture_List;
      Matched  : Boolean;
   begin
      Match (P, "", Captures, Matched);
      Assert
        (not Matched and then Captures.Count = 0,
         "a pattern that was never compiled must match nothing");
   end Test_Uncompiled;

   --  An empty step text may carry bounds 1 .. -1.  The captures it
   --  yields are still empty slices of it.
   procedure Test_Null_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Null_Text : constant String (1 .. -1) := "";
   begin
      Check ("{}", Null_Text, "P_ANONYMOUS:;");
      Check ("{word}", Null_Text, "P_WORD:;");
      Check ("{int}", Null_Text, No_Match);
      Check ("", Null_Text, "");
   end Test_Null_Text;

   procedure Test_Capacity (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Longest_Pattern :
        constant String (1 .. Fabula.Limits.Max_Pattern_Length) :=
          [others => 'x'];
      Longest_Text    : constant String (1 .. Fabula.Limits.Max_Line_Length) :=
        [others => 'y'];
      Filler_Words    : constant := 500;
   begin
      Check (Longest_Pattern, Longest_Pattern, "");
      Check ("{}", Longest_Text, "P_ANONYMOUS:" & Longest_Text & ";");
      --  Eight greedy parameters over a long text that cannot match: a
      --  search that retried failed states would not finish.
      Check
        (To_String (8 * "{} ") & "x",
         To_String (Filler_Words * "a "),
         No_Match);
   end Test_Capacity;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Seeds'Access, "reference fuzz seeds");
      Register_Routine (T, Test_Doc_Examples'Access, "documented examples");
      Register_Routine (T, Test_Greedy'Access, "greedy with backtracking");
      Register_Routine (T, Test_Empty_Captures'Access, "empty captures");
      Register_Routine (T, Test_Reals'Access, "float and double text");
      Register_Routine (T, Test_Escapes'Access, "backslash escapes");
      Register_Routine (T, Test_Alternation'Access, "word/word choices");
      Register_Routine (T, Test_Literals'Access, "literal braces and marks");
      Register_Routine (T, Test_Anchoring'Access, "anchored at both ends");
      Register_Routine (T, Test_Optionals'Access, "optional groups");
      Register_Routine (T, Test_Char_Classes'Access, "character classes");
      Register_Routine (T, Test_Refusals'Access, "patterns Compile refuses");
      Register_Routine (T, Test_Unknown_Keys'Access, "unknown keys refused");
      Register_Routine (T, Test_Uncompiled'Access, "an uncompiled pattern");
      Register_Routine (T, Test_Null_Text'Access, "empty text, bounds 1..-1");
      Register_Routine (T, Test_Capacity'Access, "shipped capacities");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Expressions (step pattern matcher)"));

end Fabula_Expressions_Tests;
