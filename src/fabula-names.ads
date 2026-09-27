--  The -n option's scenario-name patterns.  A pattern matches the whole
--  name: Any_Run stands for any run of characters, empty included, and
--  Any_Char for exactly one; every other character matches only itself,
--  case included.  A pattern list separates its alternatives with
--  Pattern_Separator.

package Fabula.Names
  with SPARK_Mode
is

   --  The glob grammar's tokens.
   Any_Run           : constant Character := '*';
   Any_Char          : constant Character := '?';
   Pattern_Separator : constant Character := ':';

   function Matches (Name, Pattern : String) return Boolean;

   --  True when any alternative matches.  An empty list selects every
   --  name; an empty alternative selects only the empty name.
   function Matches_Any (Name, Patterns : String) return Boolean;

end Fabula.Names;
