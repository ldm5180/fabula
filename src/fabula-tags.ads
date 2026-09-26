--  Tag expressions: standard Cucumber precedence (not > and >
--  or/xor), compiled to postfix and evaluated as a stack machine
--  against a scenario's tag set.  `xor` is a compatibility extension;
--  the official Cucumber tag-expression grammar has no such operator.
with Fabula.Limits;

package Fabula.Tags
  with SPARK_Mode
is

   type Compiled is private;   --  definite; registry rows store it

   function Compile (Expr : String) return Compiled
   with
     Pre => Expr'Length <= Limits.Max_Tag_Expr_Length and then Expr'First = 1;
   --  An invalid expression yields a Compiled with Valid = False: a
   --  dangling operator, an unbalanced parenthesis, an empty or
   --  all-whitespace Expr, a bare word with no leading '@', two
   --  adjacent tags, or more tokens than the table holds, are each
   --  refused this way.  Never raises.  An empty or all-whitespace
   --  Expr is "no expression" in the caller's convention -- select
   --  everything -- so Compile refuses it and the runner never calls
   --  Compile on it.

   function Valid (E : Compiled) return Boolean;

   function Error (E : Compiled) return Natural
   with Post => (if Valid (E) then Error'Result = 0);
   --  Index into Expr of the failing token; 0 when Valid.

   generic
      with function Has_Tag (Name : String) return Boolean;
   function Eval (E : Compiled) return Boolean
   with Pre => Valid (E);   --  callers check Valid first
   --  Has_Tag receives the tag WITH its leading '@'.  The runner
   --  instantiates this over the arena's tag set; tests instantiate
   --  it over a fixture array.

private

   subtype Char_Count is Natural range 0 .. Limits.Max_Tag_Expr_Length;
   subtype Char_Index is Positive range 1 .. Limits.Max_Tag_Expr_Length;
   subtype Token_Count is Natural range 0 .. Limits.Max_Tag_Expr_Tokens;
   subtype Token_Index is Positive range 1 .. Limits.Max_Tag_Expr_Tokens;

   --  A postfix element.  Tag names a slice of the Compiled value's own
   --  copy of the source text, leading '@' included.  Every other kind
   --  is a stack-machine operator and carries no slice (First and Last
   --  stay at their defaults).
   type Token_Kind is (Tag, Op_Not, Op_And, Op_Or, Op_Xor);

   type Token is record
      Kind  : Token_Kind := Tag;
      First : Char_Index := 1;
      Last  : Char_Count := 0;
   end record;

   type Token_Table is array (Token_Index) of Token;

   --  Text holds a bounded copy of the source expression; Tokens
   --  (1 .. Count) is its compiled postfix form when Valid.  The
   --  default value -- Valid False, Error_Pos 0 -- reads as "no
   --  expression, invalid": the same shape a genuine refusal leaves,
   --  except Error_Pos names no real failing token because none was
   --  ever compiled.
   type Compiled is record
      Valid     : Boolean := False;
      Error_Pos : Natural := 0;
      Text      : String (1 .. Limits.Max_Tag_Expr_Length) := [others => ' '];
      Count     : Token_Count := 0;
      Tokens    : Token_Table;
   end record;

end Fabula.Tags;
