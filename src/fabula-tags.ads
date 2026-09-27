--  Tag expressions: standard Cucumber precedence (not > and >
--  or/xor), compiled to postfix and evaluated as a stack machine
--  against a scenario's tag set.  `xor` is a compatibility extension;
--  the official Cucumber tag-expression grammar has no such operator.
with Fabula.Limits;

package Fabula.Tags
  with SPARK_Mode
is

   type Compiled is private;   --  definite; registry rows store it

   --  Compile reads an expression indexed from this position, and
   --  Error counts positions from it.
   First_Position : constant := 1;

   --  Error's answer for a valid expression: no token failed.
   No_Error : constant := 0;

   --  Expr holds no expression: it is empty, or only White_Space.
   --  Compile refuses it; a caller reads it as "select everything".
   function Blank (Expr : String) return Boolean
   is (for all Ch of Expr => Ch in White_Space);

   function Compile (Expr : String) return Compiled
   with
     Pre =>
       Expr'Length <= Limits.Max_Tag_Expr_Length
       and then Expr'First = First_Position;
   --  An invalid expression yields a Compiled with Valid = False: a
   --  dangling operator, an unbalanced parenthesis, a Blank Expr, a
   --  bare word with no leading '@', two adjacent tags, or more tokens
   --  than the table holds, are each refused this way.  Never raises.
   --  A Blank Expr is "no expression" in the caller's convention --
   --  select everything -- so Compile refuses it and the runner never
   --  calls Compile on it.

   function Valid (E : Compiled) return Boolean;

   function Error (E : Compiled) return Natural
   with
     Post =>
       Error'Result <= Limits.Max_Tag_Expr_Length
       and then (if Valid (E) then Error'Result = No_Error);
   --  Index into Expr of the failing token; No_Error when Valid.

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

   --  The grammar's symbols, one enumeration for the postfix program and
   --  for the operator stack that builds it.  Left_Paren only ever sits
   --  on the stack, a marker for the '(' that pushed it; Tag only ever
   --  sits in the program.
   type Symbol is (Tag, Left_Paren, Op_Not, Op_And, Op_Or, Op_Xor);
   subtype Stacked is Symbol range Left_Paren .. Op_Xor;
   subtype Operator is Stacked range Op_Not .. Op_Xor;
   subtype Binary_Operator is Operator range Op_And .. Op_Xor;
   subtype Postfix is Symbol
   with Static_Predicate => Postfix in Tag | Operator;

   --  A postfix element.  Tag names a slice of the Compiled value's own
   --  copy of the source text, leading '@' included.  An operator
   --  carries no slice: First and Last stay at their defaults.
   type Token is record
      Kind  : Postfix := Tag;
      First : Char_Index := Char_Index'First;
      Last  : Char_Count := Char_Count'First;
   end record;

   type Token_Table is array (Token_Index) of Token;

   --  Text holds a bounded copy of the source expression; Tokens
   --  (1 .. Count) is its compiled postfix form when Valid.  The
   --  default value -- Valid False, Error_Pos No_Error -- reads as "no
   --  expression, invalid": the same shape a genuine refusal leaves,
   --  except Error_Pos names no real failing token because none was
   --  ever compiled.
   type Compiled is record
      Valid     : Boolean := False;
      Error_Pos : Char_Count := No_Error;
      Text      : String (1 .. Limits.Max_Tag_Expr_Length) := [others => ' '];
      Count     : Token_Count := Token_Count'First;
      Tokens    : Token_Table;
   end record;

end Fabula.Tags;
