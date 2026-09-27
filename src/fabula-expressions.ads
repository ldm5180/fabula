--  Compiles step-definition patterns and matches step text against
--  them.  Matching is greedy with bounded backtracking, equivalent to
--  the anchored regular expressions the reference interpreter builds;
--  captures come back as slices of the step text plus a parameter kind
--  each.
with Fabula.Limits;
with Fabula.Scan;

package Fabula.Expressions
  with Pure, SPARK_Mode
is

   type Param_Kind is
     (P_Byte,
      P_Short,
      P_Int,
      P_Long,
      P_Float,
      P_Double,
      P_String,
      P_Word,
      P_Anonymous);

   type Capture is record
      First : Scan.Column := Scan.Empty_First;
      Last  : Scan.Line_Length :=
        Scan.Empty_Last;   --  slice of the MATCHED step text
      Kind  : Param_Kind := P_Anonymous;
   end record;

   subtype Capture_Count is Natural range 0 .. Limits.Max_Args_Per_Step;
   type Capture_Items is array (1 .. Limits.Max_Args_Per_Step) of Capture;
   type Capture_List is record
      Count : Capture_Count := Capture_Count'First;
      Items : Capture_Items;
   end record;

   --  A bounded copy of one pattern's literal text plus its token table.
   --  The type is definite, so a table of them needs no allocation.  A
   --  default value, like a pattern Compile refused, matches nothing.
   type Compiled is private with Preelaborable_Initialization;

   function Compile (Pattern : String) return Compiled
   with Pre => Pattern'Length <= Limits.Max_Pattern_Length;
   --  Valid (Result) is False on a pattern that cannot compile: more
   --  parameters than a step can pass, more tokens than the table
   --  holds, unbalanced parentheses, or a brace group that is neither a
   --  parameter key nor digits with at most one comma.  Never raises.

   function Valid (P : Compiled) return Boolean;
   --  False for a refused pattern and for a default value.

   --  One step text against one pattern: Found when the whole text
   --  matched, and then the captures of the parameters on the matched
   --  path, in order.
   type Step_Match is record
      Found    : Boolean := False;
      Captures : Capture_List;
   end record;

   function Match (P : Compiled; Text : String) return Step_Match
   with
     Pre  =>
       Text'Length <= Limits.Max_Line_Length
       and then Text'First = First_Column,
     Post =>
       (if not Match'Result.Found then Match'Result.Captures.Count = 0)
       and then (for all I in 1 .. Match'Result.Captures.Count =>
                   Match'Result.Captures.Items (I).First <= Text'Length + 1
                   and then Match'Result.Captures.Items (I).Last <= Text'Length
                   and then Match'Result.Captures.Items (I).Last
                            >= Match'Result.Captures.Items (I).First - 1);
   --  Full-text anchored match.  A failed match carries no captures.
   --  Every capture is a slice of Text, possibly empty.  The bounds are
   --  stated by length because an empty Text may have Last = -1.

private

   ---------------------------------------------------------------------
   --  The cucumber-expression grammar's tokens.
   ---------------------------------------------------------------------

   Escape_Mark : constant Character := '\';
   --  Makes the Escapable character after it literal text.

   Group_Opener : constant Character := '(';
   Group_Closer : constant Character := ')';
   --  Enclose an optional group: `item(s)`.

   Key_Opener : constant Character := '{';
   Key_Closer : constant Character := '}';
   --  Enclose a parameter key, `{int}`, or a literal count, `{1,3}`.

   Count_Separator : constant Character := ',';
   --  Separates the two counts of a literal brace group.

   Choice_Mark : constant Character := '/';
   --  Separates the two words of a choice: `is/are`.

   Quote_Mark : constant Character := '"';
   --  Encloses the text a {string} parameter captures.

   Minus_Sign    : constant Character := '-';
   Decimal_Point : constant Character := '.';
   --  The sign and the point of an {int}, {float} or {double} capture.

   subtype Escapable is Character
   with
     Static_Predicate =>
       Escapable in Group_Opener | Group_Closer | Key_Opener | Key_Closer;

   Escape_Length : constant := 2;
   --  An Escape_Mark and the Escapable character it makes literal.

   --  The characters of the words a choice joins.
   subtype Word_Char is Character
   with Static_Predicate => Word_Char in Latin_Letter | Decimal_Digit | '_';

   subtype Char_Count is Natural range 0 .. Limits.Max_Pattern_Length;
   subtype Char_Index is Positive range 1 .. Limits.Max_Pattern_Length + 1;
   subtype Token_Count is Natural range 0 .. Limits.Max_Pattern_Tokens;
   subtype Token_Index is Positive range 1 .. Limits.Max_Pattern_Tokens;
   subtype Token_Position is Positive range 1 .. Limits.Max_Pattern_Tokens + 1;

   type Token_Kind is (Literal, Parameter, Optional, Alternation);

   --  One element of a compiled pattern.  A Literal is Text (First ..
   --  Last).  An Alternation is Text (First .. Middle) or Text (Middle
   --  + 1 .. Last), tried in that order.  A Parameter captures one
   --  Param.  An Optional group's body is the tokens after it, up to
   --  but not including Skip_To.  The defaults are an empty literal.
   type Token is record
      Kind    : Token_Kind := Literal;
      First   : Char_Index := Char_Index'First;
      Middle  : Char_Count := Char_Count'First;
      Last    : Char_Count := Char_Count'First;
      Param   : Param_Kind := P_Anonymous;
      Skip_To : Token_Position := Token_Position'First;
   end record
   with Pack;

   --  Packed, because a step registry holds one table per definition.
   type Token_Table is array (Token_Index) of Token with Pack;

   --  Text holds the pattern's literal characters with escapes removed;
   --  Tokens (1 .. Count) name slices of it.
   type Compiled is record
      Valid  : Boolean := False;
      Text   : String (1 .. Limits.Max_Pattern_Length) := [others => ' '];
      Count  : Token_Count := Token_Count'First;
      Tokens : Token_Table;
   end record;

   function Valid (P : Compiled) return Boolean
   is (P.Valid);

end Fabula.Expressions;
