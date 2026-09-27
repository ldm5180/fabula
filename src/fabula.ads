--  fabula parses Gherkin feature files and runs them against step
--  definitions written in Ada.  The name is Latin for "story".

package Fabula
  with Pure, SPARK_Mode
is

   --  The characters that spell a decimal numeral, for every grammar
   --  that reads one: tags, step patterns, captures and line numbers.
   subtype Decimal_Digit is Character range '0' .. '9';

   --  The unaccented Latin letters, both cases.
   subtype Latin_Letter is Character
   with Static_Predicate => Latin_Letter in 'a' .. 'z' | 'A' .. 'Z';

   ---------------------------------------------------------------------
   --  Blank characters.  The grammars read three sets, each the one its
   --  reference lexer uses, so they differ on purpose: a Gherkin line
   --  separates its tokens with Space_Or_Tab; the line scanner trims
   --  Space_Tab_Or_Return from a line's two ends, so a CRLF file reads
   --  as its LF copy; everything that trims a cell, a description or a
   --  doc-string line, splits a tag expression, or ends a {word}
   --  capture uses the full White_Space set.
   ---------------------------------------------------------------------

   subtype Space_Or_Tab is Character
   with Static_Predicate => Space_Or_Tab in ' ' | ASCII.HT;

   subtype Space_Tab_Or_Return is Character
   with Static_Predicate => Space_Tab_Or_Return in Space_Or_Tab | ASCII.CR;

   --  Space, horizontal tab, line feed, vertical tab, form feed and
   --  carriage return.
   subtype White_Space is Character
   with
     Static_Predicate =>
       White_Space in Space_Tab_Or_Return | ASCII.LF | ASCII.VT | ASCII.FF;

   --  A feature file's lines are numbered from 1, so line 0 names none:
   --  the line of an event or a refusal before any line was read.
   No_Line : constant := 0;

   --  The index of a line's first character, in every line the scanner,
   --  the parser and the runner read.
   First_Column : constant := 1;

end Fabula;
