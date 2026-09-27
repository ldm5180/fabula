--  fabula parses Gherkin feature files and runs them against step
--  definitions written in Ada.  The name is Latin for "story".

package Fabula
  with Pure, SPARK_Mode
is

   --  The characters that spell a decimal numeral, for every grammar
   --  that reads one: tags, step patterns, captures and line numbers.
   subtype Decimal_Digit is Character range '0' .. '9';

   --  A feature file's lines are numbered from 1, so line 0 names none:
   --  the line of an event or a refusal before any line was read.
   No_Line : constant := 0;

   --  The index of a line's first character, in every line the scanner,
   --  the parser and the runner read.
   First_Column : constant := 1;

end Fabula;
