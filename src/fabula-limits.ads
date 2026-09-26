--  The shipped capacities.  Every bounded structure in the crate
--  sizes itself from these constants; the proof covers exactly
--  these values.  Overflow at run time is a typed refusal, never
--  an exception.

package Fabula.Limits
  with Pure, SPARK_Mode
is

   Max_Line_Length : constant := 2_048;
   --  Longest feature-file line the scanner accepts.

   Text_Arena_Bytes : constant := 1_048_576;
   --  One document's pooled text: names, steps, cells, doc strings.

   Max_Steps         : constant := 4_096;
   Max_Scenarios     : constant := 1_024;
   Max_Rules         : constant := 128;
   Max_Table_Rows    : constant := 4_096;
   Max_Table_Cells   : constant := 32_768;
   Max_Tags          : constant := 1_024;
   Max_Examples_Rows : constant := 1_024;
   Max_Doc_Lines     : constant := 4_096;
   --  Pool capacities for one parsed document.

   Max_Examples_Blocks : constant := 1_024;
   --  Examples blocks in one document.  A block may hold no rows, so
   --  Max_Examples_Rows does not bound it.

   Max_Features_Per_Run : constant := 256;
   Max_Step_Defs        : constant := 512;
   Max_Hooks            : constant := 64;
   Max_Pattern_Length   : constant := 256;
   Max_Args_Per_Step    : constant := 16;

   Max_Pattern_Tokens : constant := 64;
   Max_Match_Choices  : constant := 128;
   --  One compiled step pattern's token table, and the depth of the
   --  choice stack its matcher backtracks through.

   Max_Tag_Expr_Length : constant := 256;
   Max_Tag_Expr_Tokens : constant := 64;
   --  One tag expression's source length, and its compiled postfix
   --  token table (also the bound of the shunting-yard operator stack).

   Max_Message_Length   : constant := 512;
   --  One check's failure text.
   Max_Name_Length      : constant := 256;
   --  A feature or scenario name.
   Max_Path_Length      : constant := 512;
   --  A feature-file path.
   Max_Step_Text_Length : constant := Max_Line_Length;
   --  A step's own text, the same bound as a scanned line.

   Max_Name_Filter_Length : constant := 1_024;
   --  The -n option's pattern list, its ':' separators included.
   Max_Line_Selections    : constant := 64;
   --  The line numbers one file:line:line argument selects.

   Max_Search_Depth : constant := 32;
   --  Directory levels a search for feature files descends, so a
   --  symbolic-link loop ends in a refusal.

   Max_Report_Line_Length : constant := 3_072;
   --  One console report line (a header or a step, with its trailing
   --  file:line): comfortably above Max_Step_Text_Length plus a path,
   --  a name and a bracket label.

   Max_Escaped_Text_Length : constant := 6 * Max_Line_Length;
   --  A JSON-escaped text field. Six times Max_Line_Length covers the
   --  worst case where every source character expands to "\u00XX";
   --  every text Format escapes is first bounded to one line.

   Max_Table_Columns : constant := 64;
   --  Columns a rendered table's column-width pass tracks.

   Max_Failed_Scenarios : constant := 256;
   --  The failed-scenarios trailer's store. A run with more failures
   --  than this still renders the ones it kept -- saturation, not a
   --  refusal.

   Max_Cli_Positionals : constant := 256;
   --  Raw positional argv tokens (paths, each with optional line
   --  suffixes) Fabula.Cli collects from one command line.

   Max_Cli_Excludes : constant := 64;
   --  --exclude-file suffixes Fabula.Cli collects from one command line.

end Fabula.Limits;
