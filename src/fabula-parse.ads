--  Folds classified lines into a Document.  One Feed per input
--  line, then Finish once; any refusal names its line and cause.
with Fabula.Ast;
with Fabula.Limits;
private with Fabula.Grammar;

package Fabula.Parse
  with SPARK_Mode
is

   type Error_Kind is
     (None,
      Expected_Feature,          --  content before, or without, Feature:
      Expected_Scenario,         --  a line the grammar has no place for
      Expected_Examples_Table,   --  reserved: an Examples block with
      --                             no table is accepted
      Unterminated_Doc_String,
      Ragged_Table,              --  wrong cell count vs the block
      Unterminated_Table_Row,    --  a row with no closing '|'
      Tag_Line_Malformed,        --  a token that is not a tag
      Pool_Exhausted);           --  any arena or pool overflow

   type Refusal is record
      Kind : Error_Kind := None;
      Line : Line_Number := No_Line;
   end record;

   type Parser is private;   --  the sml machine plus its working state

   function Failed (P : Parser) return Boolean;
   function Error (P : Parser) return Refusal
   with Post => (Error'Result.Kind = None) = not Failed (P);

   --  Readies P and empties Doc for one feature file.
   procedure Start (P : out Parser; Doc : in out Fabula.Ast.Document)
   with Post => not Failed (P) and then Fabula.Ast.Is_Empty (Doc);

   procedure Feed
     (P      : in out Parser;
      Doc    : in out Fabula.Ast.Document;
      Line   : String;
      Number : Source_Line)
   with
     Pre =>
       Line'First = First_Column
       and then Line'Length <= Limits.Max_Line_Length;
   --  After a refusal, or after Finish, further Feeds are no-ops.

   procedure Finish (P : in out Parser; Doc : in out Fabula.Ast.Document);
   --  Closes the document at end of input.  An open doc string refuses
   --  at its opening fence's line.  A missing Feature, a tag line with
   --  nothing after it, or a Rule with no scenario after it refuses at
   --  the last line fed.

private

   type Parser is record
      Machine   : Grammar.SM.Machine (Grammar.Rows);
      Work      : Grammar.Work;
      Error     : Refusal;
      Last_Line : Line_Number := No_Line;
   end record;

   function Failed (P : Parser) return Boolean
   is (P.Error.Kind /= None);

   function Error (P : Parser) return Refusal
   is (P.Error);

end Fabula.Parse;
