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

end Fabula.Limits;
