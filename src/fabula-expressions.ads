--  Compiles step-definition patterns and matches step text against
--  them.  Matching is greedy with bounded backtracking, equivalent to
--  the anchored regular expressions the reference interpreter builds;
--  captures come back as slices of the step text plus a parameter kind
--  each.
with Fabula.Limits;

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
      First : Positive := 1;
      Last  : Natural := 0;   --  slice of the MATCHED step text
      Kind  : Param_Kind := P_Anonymous;
   end record;

   subtype Capture_Count is Natural range 0 .. Limits.Max_Args_Per_Step;
   type Capture_Items is array (1 .. Limits.Max_Args_Per_Step) of Capture;
   type Capture_List is record
      Count : Capture_Count := 0;
      Items : Capture_Items;
   end record;

   --  A bounded copy of one pattern's literal text plus its token table.
   --  The type is definite, so a table of them needs no allocation.  A
   --  default value, like a pattern Compile refused, matches nothing.
   type Compiled is private with Preelaborable_Initialization;

   procedure Compile
     (Pattern : String; Result : out Compiled; Ok : out Boolean)
   with Pre => Pattern'Length <= Limits.Max_Pattern_Length;
   --  Ok = False on a pattern that cannot compile: more parameters than
   --  a step can pass, more tokens than the table holds, unbalanced
   --  parentheses, or a brace group that is neither a parameter key nor
   --  digits with at most one comma.  Never raises.

   procedure Match
     (P        : Compiled;
      Text     : String;
      Captures : out Capture_List;
      Matched  : out Boolean)
   with
     Pre  => Text'Length <= Limits.Max_Line_Length and then Text'First = 1,
     Post =>
       (if not Matched then Captures.Count = 0)
       and then (for all I in 1 .. Captures.Count =>
                   Captures.Items (I).First <= Text'Length + 1
                   and then Captures.Items (I).Last <= Text'Length
                   and then Captures.Items (I).Last
                            >= Captures.Items (I).First - 1);
   --  Full-text anchored match.  On Matched = False, Captures.Count = 0.
   --  Every capture is a slice of Text, possibly empty.  The bounds are
   --  stated by length because an empty Text may have Last = -1.

private

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
   --  but not including Skip_To.
   type Token is record
      Kind    : Token_Kind := Literal;
      First   : Char_Index := 1;
      Middle  : Char_Count := 0;
      Last    : Char_Count := 0;
      Param   : Param_Kind := P_Anonymous;
      Skip_To : Token_Position := 1;
   end record
   with Pack;

   --  Packed, because a step registry holds one table per definition.
   type Token_Table is array (Token_Index) of Token with Pack;

   --  Text holds the pattern's literal characters with escapes removed;
   --  Tokens (1 .. Count) name slices of it.
   type Compiled is record
      Valid  : Boolean := False;
      Text   : String (1 .. Limits.Max_Pattern_Length) := [others => ' '];
      Count  : Token_Count := 0;
      Tokens : Token_Table;
   end record;

end Fabula.Expressions;
