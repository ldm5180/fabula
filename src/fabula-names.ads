--  The -n option's scenario-name patterns.  A pattern matches the whole
--  name: '*' stands for any run of characters, empty included, and '?'
--  for exactly one; every other character matches only itself, case
--  included.  A pattern list separates its alternatives with ':'.

package Fabula.Names
  with SPARK_Mode
is

   function Matches (Name, Pattern : String) return Boolean;

   --  True when any ':'-separated alternative matches.  An empty list
   --  selects every name; an empty alternative selects only the empty
   --  name.
   function Matches_Any (Name, Patterns : String) return Boolean;

end Fabula.Names;
