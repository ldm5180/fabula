--  Feeds a test document through the parser: inline lines, or one
--  file of the parser corpus.  The suite runs from the crate root.
with Ada.Strings.Unbounded;

with Fabula.Ast;
with Fabula.Parse;

package Fabula_Fixtures is

   type Lines is
     array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   function "+" (Source : String) return Ada.Strings.Unbounded.Unbounded_String
   renames Ada.Strings.Unbounded.To_Unbounded_String;

   procedure Parse_Lines
     (Source : Lines;
      P      : out Fabula.Parse.Parser;
      Doc    : in out Fabula.Ast.Document);

   --  Name is a file in tests/data/cwt/parser/.
   procedure Parse_Corpus
     (Name : String;
      P    : out Fabula.Parse.Parser;
      Doc  : in out Fabula.Ast.Document);

end Fabula_Fixtures;
