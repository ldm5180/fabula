package body Fabula.Tags
  with SPARK_Mode
is

   --  Compile reads Expr once, left to right, running a textbook
   --  shunting-yard: an explicit bounded operator stack (Builder.Stack)
   --  and the postfix output array (Builder.Result.Tokens) it feeds.
   --  Validity (dangling operators, unbalanced parens, ...) is caught
   --  by one flag, Expect: True wherever the grammar wants an operand,
   --  a prefix "not", or an opening "(" next; False wherever it wants
   --  a binary operator, a closing ")", or the end of input.

   --  A refused Compiled naming the position Compile refused at.  A
   --  Compiled value never touched by Compile at all -- its bare
   --  default -- reports the same Valid = False through its own
   --  field defaults, with no call here.
   function Refused_At (Pos : Natural) return Compiled
   is (Valid     => False,
       Error_Pos => Pos,
       Text      => [others => ' '],
       Count     => 0,
       Tokens    => [others => (Kind => Tag, First => 1, Last => 0)]);

   function Is_Whitespace (Ch : Character) return Boolean
   is (Ch = ' '
       or else Ch = ASCII.HT
       or else Ch = ASCII.CR
       or else Ch = ASCII.LF
       or else Ch = ASCII.VT
       or else Ch = ASCII.FF);

   --  A run of tag or keyword characters stops at whitespace or a
   --  parenthesis; parentheses need no whitespace around them.
   function Is_Delimiter (Ch : Character) return Boolean
   is (Is_Whitespace (Ch) or else Ch = '(' or else Ch = ')');

   function Is_Blank (Expr : String) return Boolean
   is (for all Ch of Expr => Is_Whitespace (Ch));

   --  Every helper below reads Expr under this same bound, which is
   --  what keeps From + 1 and Last + 1 provably free of overflow: a
   --  256-character Expr can never push an index near Integer'Last.
   function Expr_OK (Expr : String) return Boolean
   is (Expr'First = 1 and then Expr'Length <= Limits.Max_Tag_Expr_Length);

   function Skip_Whitespace (Expr : String; From : Positive) return Positive
   with
     Pre  => Expr_OK (Expr) and then From <= Expr'Last + 1,
     Post =>
       Skip_Whitespace'Result in From .. Expr'Last + 1
       and then (if Skip_Whitespace'Result <= Expr'Last
                 then not Is_Whitespace (Expr (Skip_Whitespace'Result)))
   is
      I : Positive := From;
   begin
      while I <= Expr'Last and then Is_Whitespace (Expr (I)) loop
         pragma Loop_Invariant (I in From .. Expr'Last + 1);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I;
   end Skip_Whitespace;

   --  The last index of the delimiter-free run starting at From.
   function Run_End (Expr : String; From : Positive) return Positive
   with
     Pre  =>
       Expr_OK (Expr)
       and then From <= Expr'Last
       and then not Is_Delimiter (Expr (From)),
     Post => Run_End'Result in From .. Expr'Last
   is
      I : Positive := From;
   begin
      while I < Expr'Last and then not Is_Delimiter (Expr (I + 1)) loop
         pragma Loop_Invariant (I in From .. Expr'Last);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I;
   end Run_End;

   type Run_Kind is (Kw_Not, Kw_And, Kw_Or, Kw_Xor, Run_Tag, Run_Bad);

   --  A keyword matches the WHOLE run, not a prefix of it, so "android"
   --  is a bare word, never "and" followed by "roid".  A tag is '@'
   --  plus one or more characters; '@' alone, with nothing after it,
   --  is Run_Bad.
   function Classify_Run
     (Expr : String; First : Positive; Last : Positive) return Run_Kind
   with Pre => Expr_OK (Expr) and then First <= Last and then Last <= Expr'Last
   is
   begin
      if Expr (First .. Last) = "not" then
         return Kw_Not;
      elsif Expr (First .. Last) = "and" then
         return Kw_And;
      elsif Expr (First .. Last) = "or" then
         return Kw_Or;
      elsif Expr (First .. Last) = "xor" then
         return Kw_Xor;
      elsif Expr (First) = '@' and then Last > First then
         return Run_Tag;
      else
         return Run_Bad;
      end if;
   end Classify_Run;

   --  The shunting-yard operator stack.  Left_Paren is a marker: it
   --  carries no output token of its own, only the position of the
   --  '(' that pushed it, for an unbalanced-parenthesis refusal.
   type Op_Kind is (Left_Paren, K_Not, K_And, K_Or, K_Xor);

   type Op_Entry is record
      Kind : Op_Kind := Left_Paren;
      Pos  : Positive := 1;
   end record;

   type Op_Stack_Array is array (Token_Index) of Op_Entry;

   --  Expect is True wherever the grammar wants an operand next (at
   --  the start, after "(", "not", or a binary operator); False
   --  wherever it wants a binary operator, ")", or the end of input.
   --  Wait_Pos is the position of the last operator pushed while
   --  setting Expect, so a trailing dangling operator can name itself.
   type Builder is record
      Result   : Compiled;
      Depth    : Token_Count := 0;
      Stack    : Op_Stack_Array;
      Expect   : Boolean := True;
      Wait_Pos : Positive := 1;
      Refused  : Boolean := False;
      Error    : Natural := 0;
   end record;

   procedure Refuse (B : in out Builder; Pos : Positive) is
   begin
      if not B.Refused then
         B.Refused := True;
         B.Error := Pos;
      end if;
   end Refuse;

   procedure Push_Op (B : in out Builder; Kind : Op_Kind; Pos : Positive) is
   begin
      if B.Depth = Limits.Max_Tag_Expr_Tokens then
         Refuse (B, Pos);
         return;
      end if;
      B.Depth := B.Depth + 1;
      B.Stack (B.Depth) := (Kind => Kind, Pos => Pos);
   end Push_Op;

   procedure Emit (B : in out Builder; Tok : Token; Pos : Positive) is
   begin
      if B.Result.Count = Limits.Max_Tag_Expr_Tokens then
         Refuse (B, Pos);
         return;
      end if;
      B.Result.Count := B.Result.Count + 1;
      B.Result.Tokens (B.Result.Count) := Tok;
   end Emit;

   subtype Precedence_Level is Natural range 0 .. 3;

   --  Tightest first: not, then and, then or and xor together.
   function Precedence (Kind : Op_Kind) return Precedence_Level
   is (case Kind is
         when Left_Paren   => 0,
         when K_Or | K_Xor => 1,
         when K_And        => 2,
         when K_Not        => 3);

   function Op_Token (Kind : Op_Kind) return Token
   is (case Kind is
         when K_Not      => (Kind => Op_Not, First => 1, Last => 0),
         when K_And      => (Kind => Op_And, First => 1, Last => 0),
         when K_Or       => (Kind => Op_Or, First => 1, Last => 0),
         when K_Xor      => (Kind => Op_Xor, First => 1, Last => 0),
         when Left_Paren => (Kind => Tag, First => 1, Last => 0))
   with Pre => Kind /= Left_Paren;

   procedure Pop_One (B : in out Builder)
   with
     Pre  => B.Depth > 0 and then B.Stack (B.Depth).Kind /= Left_Paren,
     Post => B.Depth = B.Depth'Old - 1 and then B.Stack = B.Stack'Old
   is
      Top : constant Op_Entry := B.Stack (B.Depth);
   begin
      B.Depth := B.Depth - 1;
      Emit (B, Op_Token (Top.Kind), Top.Pos);
   end Pop_One;

   --  Pops every pending operator at least as tight as New_Prec, left
   --  associativity's rule (equal precedence pops too).  A "not" left
   --  pending from a prefix chain is tighter than every binary op, so
   --  it always pops here, ahead of the binary operator being pushed.
   procedure Reduce_For_Binary
     (B : in out Builder; New_Prec : Precedence_Level) is
   begin
      while B.Depth > 0
        and then B.Stack (B.Depth).Kind /= Left_Paren
        and then Precedence (B.Stack (B.Depth).Kind) >= New_Prec
        and then not B.Refused
      loop
         pragma Loop_Variant (Decreases => B.Depth);
         Pop_One (B);
      end loop;
   end Reduce_For_Binary;

   procedure Handle_Tag
     (B : in out Builder; First : Positive; Last : Positive; Pos : Positive)
   with Pre => First <= Last and then Last <= Limits.Max_Tag_Expr_Length
   is
   begin
      if not B.Expect then
         Refuse (B, Pos);
         return;
      end if;
      Emit (B, (Kind => Tag, First => First, Last => Last), Pos);
      B.Expect := False;
   end Handle_Tag;

   procedure Handle_LParen (B : in out Builder; Pos : Positive) is
   begin
      if not B.Expect then
         Refuse (B, Pos);
         return;
      end if;
      Push_Op (B, Left_Paren, Pos);
      B.Wait_Pos := Pos;
   end Handle_LParen;

   --  A ")" with Expect still True closes an empty or dangling group
   --  ("()" , "(not)", "(@a and)") -- the grammar's parentheses group
   --  one expression, never nothing.  Otherwise it pops back to the
   --  matching "(", or refuses when the stack has none left to find.
   procedure Handle_RParen (B : in out Builder; Pos : Positive) is
   begin
      if B.Expect then
         Refuse (B, Pos);
         return;
      end if;
      while B.Depth > 0
        and then B.Stack (B.Depth).Kind /= Left_Paren
        and then not B.Refused
      loop
         pragma Loop_Variant (Decreases => B.Depth);
         Pop_One (B);
      end loop;
      if B.Refused then
         return;
      end if;
      if B.Depth = 0 then
         Refuse (B, Pos);
         return;
      end if;
      B.Depth := B.Depth - 1;
      B.Expect := False;
   end Handle_RParen;

   procedure Handle_Not (B : in out Builder; Pos : Positive) is
   begin
      if not B.Expect then
         Refuse (B, Pos);
         return;
      end if;
      Push_Op (B, K_Not, Pos);
      B.Wait_Pos := Pos;
   end Handle_Not;

   procedure Handle_Binary (B : in out Builder; Kind : Op_Kind; Pos : Positive)
   is
   begin
      if B.Expect then
         Refuse (B, Pos);
         return;
      end if;
      Reduce_For_Binary (B, Precedence (Kind));
      if B.Refused then
         return;
      end if;
      Push_Op (B, Kind, Pos);
      B.Expect := True;
      B.Wait_Pos := Pos;
   end Handle_Binary;

   --  Everything but "(" and ")": a keyword or a tag, spanning the
   --  whole delimiter-free run at I.
   procedure Scan_Word (Expr : String; I : in out Positive; B : in out Builder)
   with
     Pre  =>
       Expr_OK (Expr)
       and then I in Expr'Range
       and then not Is_Delimiter (Expr (I)),
     Post => I > I'Old and then I <= Expr'Last + 1
   is
      Last : constant Positive := Run_End (Expr, I);
      Kind : constant Run_Kind := Classify_Run (Expr, I, Last);
   begin
      case Kind is
         when Kw_Not  =>
            Handle_Not (B, I);

         when Kw_And  =>
            Handle_Binary (B, K_And, I);

         when Kw_Or   =>
            Handle_Binary (B, K_Or, I);

         when Kw_Xor  =>
            Handle_Binary (B, K_Xor, I);

         when Run_Tag =>
            Handle_Tag (B, I, Last, I);

         when Run_Bad =>
            Refuse (B, I);
      end case;
      I := Last + 1;
   end Scan_Word;

   --  One token at I, which whitespace already precedes.  Leaves I at
   --  the next non-whitespace position, or past the end.
   procedure Scan_Token
     (Expr : String; I : in out Positive; B : in out Builder)
   with
     Pre  =>
       Expr_OK (Expr)
       and then I in Expr'Range
       and then not Is_Whitespace (Expr (I)),
     Post =>
       I > I'Old
       and then I <= Expr'Last + 1
       and then (if I <= Expr'Last then not Is_Whitespace (Expr (I)))
   is
   begin
      if Expr (I) = '(' then
         Handle_LParen (B, I);
         I := I + 1;
      elsif Expr (I) = ')' then
         Handle_RParen (B, I);
         I := I + 1;
      else
         Scan_Word (Expr, I, B);
      end if;
      I := Skip_Whitespace (Expr, I);
   end Scan_Token;

   --  End of input.  A pending operand (a trailing operator) refuses
   --  at the operator that is still waiting.  Otherwise every "("
   --  still on the stack is unmatched -- the outermost one refuses --
   --  and what remains is operators alone, unwound onto the output.
   procedure Finish (B : in out Builder) is
   begin
      if B.Expect then
         Refuse (B, B.Wait_Pos);
         return;
      end if;

      for J in 1 .. B.Depth loop
         pragma
           Loop_Invariant
             (for all K in 1 .. J - 1 => B.Stack (K).Kind /= Left_Paren);
         if B.Stack (J).Kind = Left_Paren then
            Refuse (B, B.Stack (J).Pos);
            return;
         end if;
      end loop;

      while B.Depth > 0 and then not B.Refused loop
         pragma
           Loop_Invariant
             (for all K in 1 .. B.Depth => B.Stack (K).Kind /= Left_Paren);
         pragma Loop_Variant (Decreases => B.Depth);
         Pop_One (B);
      end loop;
   end Finish;

   function Valid (E : Compiled) return Boolean
   is (E.Valid);

   function Error (E : Compiled) return Natural
   is (if E.Valid then 0 else E.Error_Pos);

   function Compile (Expr : String) return Compiled is
      B : Builder;
      I : Positive;
   begin
      if Is_Blank (Expr) then
         return Refused_At (1);
      end if;

      B.Result.Text (1 .. Expr'Length) := Expr;

      I := Skip_Whitespace (Expr, Expr'First);
      while I <= Expr'Last and then not B.Refused loop
         pragma Loop_Invariant (not Is_Whitespace (Expr (I)));
         pragma Loop_Variant (Increases => I);
         Scan_Token (Expr, I, B);
      end loop;

      if not B.Refused then
         Finish (B);
      end if;

      if B.Refused then
         return Refused_At (B.Error);
      end if;

      return
        (Valid     => True,
         Error_Pos => 0,
         Text      => B.Result.Text,
         Count     => B.Result.Count,
         Tokens    => B.Result.Tokens);
   end Compile;

   --  A bounded stack machine, no recursion: Stack (1 .. Top) holds
   --  the values produced so far.  Every access is guarded by Top
   --  itself, so a Compiled value that (should never, but) does not
   --  balance still evaluates safely instead of raising -- functional
   --  correctness for a well-formed Compiled is the test suite's job,
   --  not this loop's.  E.Count = 0 (never compiled, or refused) falls
   --  out of the same guards as the empty, always-false expression.
   function Eval (E : Compiled) return Boolean is
      type Value_Stack is array (Token_Index) of Boolean;

      Stack : Value_Stack := [others => False];
      Top   : Token_Count := 0;
   begin
      for I in 1 .. E.Count loop
         pragma Loop_Invariant (Top <= I - 1);
         case E.Tokens (I).Kind is
            when Tag    =>
               if Top < Limits.Max_Tag_Expr_Tokens then
                  Top := Top + 1;
                  Stack (Top) :=
                    Has_Tag (E.Text (E.Tokens (I).First .. E.Tokens (I).Last));
               end if;

            when Op_Not =>
               if Top >= 1 then
                  Stack (Top) := not Stack (Top);
               end if;

            when Op_And =>
               if Top >= 2 then
                  Top := Top - 1;
                  Stack (Top) := Stack (Top) and then Stack (Top + 1);
               end if;

            when Op_Or  =>
               if Top >= 2 then
                  Top := Top - 1;
                  Stack (Top) := Stack (Top) or else Stack (Top + 1);
               end if;

            when Op_Xor =>
               if Top >= 2 then
                  Top := Top - 1;
                  Stack (Top) := Stack (Top) xor Stack (Top + 1);
               end if;
         end case;
      end loop;

      return (if Top >= 1 then Stack (1) else False);
   end Eval;

end Fabula.Tags;
