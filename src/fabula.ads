--  fabula parses Gherkin feature files and runs them against step
--  definitions written in Ada.  The name is Latin for "story".

package Fabula
  with Pure, SPARK_Mode
is

   --  The characters that spell a decimal numeral, for every grammar
   --  that reads one: tags, step patterns, captures and line numbers.
   subtype Decimal_Digit is Character range '0' .. '9';

end Fabula;
