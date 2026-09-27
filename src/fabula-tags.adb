with Fabula.Scan;
with Sml.Machines.Operators;
with Sml.Request_Block;

package body Fabula.Tags
  with SPARK_Mode
is

   --  Compile reads Expr once, left to right, as a textbook
   --  shunting-yard: an explicit bounded operator stack (Builder.Stack)
   --  and the postfix output array (Builder.Result.Tokens) it feeds.
   --  A small machine decides what each lexeme may be: an operand, a
   --  "not" or a "(" where the grammar wants an operand; a binary
   --  operator, a ")" or the end where it wants an operator.  The stack
   --  work runs in the commands its rows request.

   ---------------------------------------------------------------------
   --  The tag-expression grammar's tokens.  A tag starts with
   --  Gherkin's own Scan.Tag_Mark.
   ---------------------------------------------------------------------

   Group_Opener : constant Character := '(';
   Group_Closer : constant Character := ')';
   --  Group one expression.  A lexeme ends at either one, so neither
   --  needs white space around it.

   Not_Word : constant String := "not";
   And_Word : constant String := "and";
   Or_Word  : constant String := "or";
   Xor_Word : constant String := "xor";

   function Word (Op : Operator) return String
   is (case Op is
         when Op_Not => Not_Word,
         when Op_And => And_Word,
         when Op_Or  => Or_Word,
         when Op_Xor => Xor_Word);

   --  A lexeme runs up to white space or a parenthesis.
   subtype Delimiter is Character
   with
     Static_Predicate =>
       Delimiter in White_Space | Group_Opener | Group_Closer;

   --  Tightest first: not, then and, then or and xor together.
   subtype Precedence_Level is Positive range 1 .. 3;

   Precedence : constant array (Operator) of Precedence_Level :=
     [Op_Not => 3, Op_And => 2, Op_Or | Op_Xor => 1];

   Loosest : constant Precedence_Level := Precedence_Level'First;

   Binary_Arity : constant := 2;
   --  The values a binary operator takes off the evaluation stack.

   Blank_Error : constant Char_Index := Char_Index'First;
   --  Where a Blank expression refuses, whether or not it has a first
   --  character.

   --  Every helper below reads Expr under this same bound, which is
   --  what keeps From + 1 and Last + 1 provably free of overflow: a
   --  256-character Expr can never push an index near Integer'Last.
   function Expr_OK (Expr : String) return Boolean
   is (Expr'First = First_Position
       and then Expr'Length <= Limits.Max_Tag_Expr_Length);

   function Skip_White_Space (Expr : String; From : Positive) return Positive
   with
     Pre  => Expr_OK (Expr) and then From <= Expr'Last + 1,
     Post =>
       Skip_White_Space'Result in From .. Expr'Last + 1
       and then (if Skip_White_Space'Result <= Expr'Last
                 then Expr (Skip_White_Space'Result) not in White_Space)
   is
      I : Positive := From;
   begin
      while I <= Expr'Last and then Expr (I) in White_Space loop
         pragma Loop_Invariant (I in From .. Expr'Last + 1);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I;
   end Skip_White_Space;

   --  The last index of the delimiter-free run starting at From.
   function Run_End (Expr : String; From : Positive) return Positive
   with
     Pre  =>
       Expr_OK (Expr)
       and then From <= Expr'Last
       and then Expr (From) not in Delimiter,
     Post => Run_End'Result in From .. Expr'Last
   is
      I : Positive := From;
   begin
      while I < Expr'Last and then Expr (I + 1) not in Delimiter loop
         pragma Loop_Invariant (I in From .. Expr'Last);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I;
   end Run_End;

   ---------------------------------------------------------------------
   --  The machine's vocabulary.
   ---------------------------------------------------------------------

   --  Want_Operand: at the start, and after "(", "not" or a binary
   --  operator.  Want_Operator: after a tag or a ")".
   type State is (Want_Operand, Want_Operator, Done, Refused);

   --  One event per lexeme, and Finish at the end of the expression.  A
   --  delimiter-free run is a Tag_Name when it is '@' and at least one
   --  more character, a Prefix or a Binary when it is exactly an
   --  operator's Word ("android" is neither), and a Bad_Word otherwise.
   type Event_Kind is
     (E_Tag_Name, E_Prefix, E_Binary, E_Open, E_Close, E_Bad_Word, E_Finish);

   --  A lexeme: its kind, the operator a Binary spells, and its first and
   --  last index in Expr.  First is where a refusal of it points.  Only a
   --  Binary reads Op: a Prefix is always "not".  The Finish event reads
   --  only its Kind.
   type Event is record
      Kind  : Event_Kind := E_Finish;
      Op    : Binary_Operator := Binary_Operator'First;
      First : Char_Index := Char_Index'First;
      Last  : Char_Count := Char_Count'First;
   end record;

   type Guard_Kind is
     (Always, In_Group);   --  a '(' is still open on the stack

   --  Each command is one step of the shunting-yard.  The Refuse_*
   --  commands record where the expression failed; so do the pushes
   --  and emits that find their table full.
   type Command is
     (Nothing,
      Emit_Tag,            --  the tag goes straight to the output
      Push_Not,            --  "not" waits on the stack
      Open_Group,          --  "(" waits on the stack
      Push_Binary,         --  tighter-or-equal operators pop first
      Close_Group,         --  pop to the matching "(", then drop it
      Unwind,              --  pop every operator left
      Refuse_Dangling,     --  at the operator still waiting for its operand
      Refuse_Unclosed,     --  at the outermost "(" still open
      Refuse_Stray_Close); --  at a ")" with no "(", after unwinding

   package Req is new Sml.Request_Block (Command => Command, None => Nothing);

   --  An operator stack entry: what was pushed, and where in Expr.
   type Pending is record
      Kind : Stacked := Left_Paren;
      Pos  : Char_Index := Char_Index'First;
   end record;

   type Pending_Stack is array (Token_Index) of Pending;

   --  The machine's context: the output being built, the operator stack
   --  (1 .. Stack_Count), and Wait_Pos, the position of the last push, so
   --  a trailing dangling operator can name itself.  Error is the first
   --  refusal's position, No_Error while there is none.
   type Builder is record
      Requests    : Req.Block;
      Result      : Compiled;
      Stack_Count : Token_Count := Token_Count'First;
      Stack       : Pending_Stack;
      Wait_Pos    : Char_Index := Char_Index'First;
      Error       : Char_Count := No_Error;
   end record;

   function Kind_Of (Evt : Event) return Event_Kind
   is (Evt.Kind);

   function Evaluate (G : Guard_Kind; B : Builder; Evt : Event) return Boolean;

   --  Records A as the pending command; the machine does nothing else.
   procedure Execute (A : Command; B : in out Builder; Evt : Event);

   package SM is new
     Sml.Machines
       (State       => State,
        Event_Kind  => Event_Kind,
        Event       => Event,
        Context     => Builder,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Command,
        Kind_Of     => Kind_Of,
        Evaluate    => Evaluate,
        Execute     => Execute);

   package Row_Ops is new SM.Operators (Always => Always, Nothing => Nothing);
   use type Row_Ops.Ev, Row_Ops.Ev_Guard, Row_Ops.Ev_Built, Row_Ops.Source;

   subtype Ev is Row_Ops.Ev;

   Tag_Name : constant Ev := (Kind => E_Tag_Name);
   Prefix   : constant Ev := (Kind => E_Prefix);
   Binary   : constant Ev := (Kind => E_Binary);
   Open     : constant Ev := (Kind => E_Open);
   Close    : constant Ev := (Kind => E_Close);
   Finish   : constant Ev := (Kind => E_Finish);

   Rows : constant := 9;

   --  Each row reads:  From + Event (Guard) / Command >= To.  Rows for
   --  one state are tried top to bottom.  A lexeme no row takes -- a
   --  tag, "not" or "(" where an operator is wanted, a binary operator
   --  or ")" where an operand is wanted, and every Bad_Word -- refuses
   --  at its own position.
   --!format off
   Table : constant SM.Transition_Table (1 .. Rows) :=
     [
      --  An operand is wanted.
      Want_Operand  + Tag_Name          / Emit_Tag           >= Want_Operator,
      Want_Operand  + Prefix            / Push_Not           >= Want_Operand,
      Want_Operand  + Open              / Open_Group         >= Want_Operand,
      Want_Operand  + Finish            / Refuse_Dangling    >= Refused,

      --  An operator, a ")" or the end is wanted.
      Want_Operator + Binary            / Push_Binary        >= Want_Operand,
      Want_Operator + Close (In_Group)  / Close_Group        >= Want_Operator,
      Want_Operator + Close             / Refuse_Stray_Close >= Refused,
      Want_Operator + Finish (In_Group) / Refuse_Unclosed    >= Refused,
      Want_Operator + Finish            / Unwind             >= Done];
   --!format on

   ---------------------------------------------------------------------
   --  The stack work.
   ---------------------------------------------------------------------

   function Has_Error (B : Builder) return Boolean
   is (B.Error /= No_Error);

   --  The first refusal sticks; later ones are dropped.
   procedure Refuse (B : in out Builder; Pos : Char_Count) is
   begin
      if B.Error = No_Error then
         B.Error := Pos;
      end if;
   end Refuse;

   --  Pushes Kind, which Pos pushed, or refuses at Pos when the stack is
   --  full.  Pos is the new wait position either way.
   procedure Push (B : in out Builder; Kind : Stacked; Pos : Char_Index) is
   begin
      B.Wait_Pos := Pos;
      if B.Stack_Count = Limits.Max_Tag_Expr_Tokens then
         Refuse (B, Pos);
      else
         B.Stack_Count := B.Stack_Count + 1;
         B.Stack (B.Stack_Count) := (Kind => Kind, Pos => Pos);
      end if;
   end Push;

   --  Appends Tok to the output, or refuses at Pos when it is full.
   procedure Emit (B : in out Builder; Tok : Token; Pos : Char_Index) is
   begin
      if B.Result.Count = Limits.Max_Tag_Expr_Tokens then
         Refuse (B, Pos);
      else
         B.Result.Count := B.Result.Count + 1;
         B.Result.Tokens (B.Result.Count) := Tok;
      end if;
   end Emit;

   procedure Pop_One (B : in out Builder)
   with
     Pre  =>
       B.Stack_Count > 0 and then B.Stack (B.Stack_Count).Kind in Operator,
     Post =>
       B.Stack_Count = B.Stack_Count'Old - 1 and then B.Stack = B.Stack'Old
   is
      Top : constant Pending := B.Stack (B.Stack_Count);
   begin
      B.Stack_Count := B.Stack_Count - 1;
      Emit (B, (Kind => Top.Kind, others => <>), Top.Pos);
   end Pop_One;

   --  Pops every pending operator at least as tight as Down_To, left
   --  associativity's rule (equal precedence pops too), and stops at a
   --  "(".  A "not" left pending from a prefix chain is tighter than
   --  every binary operator, so it always pops ahead of one.  With
   --  Down_To = Loosest this pops back to the innermost "(", or empties
   --  the stack.
   procedure Pop_Operators (B : in out Builder; Down_To : Precedence_Level) is
   begin
      while B.Stack_Count > 0
        and then B.Stack (B.Stack_Count).Kind in Operator
        and then Precedence (B.Stack (B.Stack_Count).Kind) >= Down_To
        and then not Has_Error (B)
      loop
         pragma Loop_Variant (Decreases => B.Stack_Count);
         Pop_One (B);
      end loop;
   end Pop_Operators;

   --  What First_Open_Paren answers when no "(" is open.
   No_Open_Paren : constant Char_Count := 0;

   --  The position of the outermost "(" still open, or No_Open_Paren
   --  when none is.
   function First_Open_Paren (B : Builder) return Char_Count is
   begin
      for K in 1 .. B.Stack_Count loop
         if B.Stack (K).Kind = Left_Paren then
            return B.Stack (K).Pos;
         end if;
      end loop;
      return No_Open_Paren;
   end First_Open_Paren;

   --  Pops back to the innermost "(" and drops it.
   procedure Close_Paren (B : in out Builder) is
   begin
      Pop_Operators (B, Loosest);
      if B.Stack_Count > 0 then
         B.Stack_Count := B.Stack_Count - 1;
      end if;
   end Close_Paren;

   --  Performs the command the transition just requested.
   procedure Perform (B : in out Builder; Evt : Event) is
      Cmd : constant Command := B.Requests.Pending;
   begin
      B.Requests.Pending := Nothing;
      case Cmd is
         when Nothing            =>
            null;

         when Emit_Tag           =>
            Emit
              (B,
               (Kind => Tag, First => Evt.First, Last => Evt.Last),
               Evt.First);

         when Push_Not           =>
            Push (B, Op_Not, Evt.First);

         when Open_Group         =>
            Push (B, Left_Paren, Evt.First);

         when Push_Binary        =>
            Pop_Operators (B, Precedence (Evt.Op));
            Push (B, Evt.Op, Evt.First);

         when Close_Group        =>
            Close_Paren (B);

         when Unwind             =>
            Pop_Operators (B, Loosest);

         when Refuse_Dangling    =>
            Refuse (B, B.Wait_Pos);

         when Refuse_Unclosed    =>
            Refuse (B, First_Open_Paren (B));

         when Refuse_Stray_Close =>
            --  Unwind first: when the output overflows while unwinding,
            --  the refusal names the operator that overflowed it, not
            --  this ")".
            Pop_Operators (B, Loosest);
            Refuse (B, Evt.First);
      end case;
   end Perform;

   ---------------------------------------------------------------------
   --  Guards and actions.
   ---------------------------------------------------------------------

   function Evaluate (G : Guard_Kind; B : Builder; Evt : Event) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      case G is
         when Always   =>
            return True;

         when In_Group =>
            return First_Open_Paren (B) /= No_Open_Paren;
      end case;
   end Evaluate;

   procedure Execute (A : Command; B : in out Builder; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      B.Requests.Pending := A;
   end Execute;

   ---------------------------------------------------------------------
   --  The lexer and the driver.
   ---------------------------------------------------------------------

   --  The event of an operator word at First .. Last: "not" is a
   --  Prefix, and a binary operator is a Binary that carries it.
   function Operator_Event
     (Op : Operator; First : Char_Index; Last : Char_Count) return Event
   is (case Op is
         when Op_Not          =>
           (Kind => E_Prefix, First => First, Last => Last, others => <>),
         when Binary_Operator =>
           (Kind => E_Binary, Op => Op, First => First, Last => Last));

   --  The event of the delimiter-free run Expr (First .. Last).
   function Word_Event
     (Expr : String; First : Positive; Last : Positive) return Event
   with
     Pre  => Expr_OK (Expr) and then First <= Last and then Last <= Expr'Last,
     Post =>
       Word_Event'Result.First = First and then Word_Event'Result.Last = Last
   is
   begin
      for Op in Operator loop
         if Expr (First .. Last) = Word (Op) then
            return Operator_Event (Op, First, Last);
         end if;
      end loop;
      return
        (Kind   =>
           (if Expr (First) = Scan.Tag_Mark and then Last > First
            then E_Tag_Name
            else E_Bad_Word),
         First  => First,
         Last   => Last,
         others => <>);
   end Word_Event;

   --  The lexeme that starts at Expr (I), which is not white space.
   function Lexeme_At (Expr : String; I : Positive) return Event
   is (case Expr (I) is
         when Group_Opener =>
           (Kind => E_Open, First => I, Last => I, others => <>),
         when Group_Closer =>
           (Kind => E_Close, First => I, Last => I, others => <>),
         when others       => Word_Event (Expr, I, Run_End (Expr, I)))
   with
     Pre  =>
       Expr_OK (Expr)
       and then I in Expr'Range
       and then Expr (I) not in White_Space,
     Post =>
       Lexeme_At'Result.First = I
       and then Lexeme_At'Result.Last in I .. Expr'Last;

   --  One lexeme through the machine: a lexeme no row takes refuses at
   --  its own position; a taken one runs its command.
   procedure Step (M : in out SM.Machine; B : in out Builder; Evt : Event) is
      Handled : Boolean;
   begin
      B.Requests.Pending := Nothing;
      SM.Process_Event (M, B, Evt, Handled);
      if Handled then
         Perform (B, Evt);
      else
         Refuse (B, Evt.First);
      end if;
   end Step;

   --  Every lexeme of Expr, until one refuses.  Compile has already
   --  refused a Blank Expr, so Expr holds at least one character.
   procedure Read_Lexemes
     (Expr : String; M : in out SM.Machine; B : in out Builder)
   with Pre => Expr_OK (Expr) and then Expr'Length > 0
   is
      I : Positive := Skip_White_Space (Expr, Expr'First);
   begin
      while I <= Expr'Last and then not Has_Error (B) loop
         pragma Loop_Invariant (Expr (I) not in White_Space);
         pragma Loop_Variant (Increases => I);
         declare
            Evt : constant Event := Lexeme_At (Expr, I);
         begin
            Step (M, B, Evt);
            I := Skip_White_Space (Expr, Evt.Last + 1);
         end;
      end loop;
   end Read_Lexemes;

   --  A refused Compiled naming the position Compile refused at.  A
   --  Compiled value never touched by Compile at all -- its bare
   --  default -- reports the same Valid = False through its own
   --  field defaults, with no call here.
   function Refused_At (Pos : Char_Count) return Compiled
   is ((Valid => False, Error_Pos => Pos, others => <>));

   --  The machine reached Done with no refusal: the output is the
   --  postfix program.
   function Result_Of (M : SM.Machine; B : Builder) return Compiled
   is (if SM.State_Of (M) = Done and then not Has_Error (B)
       then (B.Result with delta Valid => True, Error_Pos => No_Error)
       else Refused_At (B.Error));

   function Valid (E : Compiled) return Boolean
   is (E.Valid);

   function Error (E : Compiled) return Natural
   is (if E.Valid then No_Error else E.Error_Pos);

   function Compile (Expr : String) return Compiled is
      M : SM.Machine := SM.Make (Table, Initial => Want_Operand);
      B : Builder;
   begin
      if Blank (Expr) then
         return Refused_At (Blank_Error);
      end if;
      B.Result.Text (1 .. Expr'Length) := Expr;
      Read_Lexemes (Expr, M, B);
      if not Has_Error (B) then
         Step (M, B, (Kind => E_Finish, others => <>));
      end if;
      return Result_Of (M, B);
   end Compile;

   ---------------------------------------------------------------------
   --  Evaluation.
   ---------------------------------------------------------------------

   type Value_Array is array (Token_Index) of Boolean;

   --  Items (1 .. Used) holds the values produced so far.
   type Value_Stack is record
      Items : Value_Array := [others => False];
      Used  : Token_Count := Token_Count'First;
   end record;

   --  L Op R, its operands in the order they were written.
   function Combine
     (L : Boolean; Op : Binary_Operator; R : Boolean) return Boolean
   is (case Op is
         when Op_And => L and then R,
         when Op_Or  => L or else R,
         when Op_Xor => L xor R);

   procedure Push_Value (V : in out Value_Stack; Value : Boolean)
   with Post => V.Used <= V.Used'Old + 1
   is
   begin
      if V.Used < Limits.Max_Tag_Expr_Tokens then
         V.Used := V.Used + 1;
         V.Items (V.Used) := Value;
      end if;
   end Push_Value;

   procedure Negate_Top (V : in out Value_Stack)
   with Post => V.Used = V.Used'Old
   is
   begin
      if V.Used > 0 then
         V.Items (V.Used) := not V.Items (V.Used);
      end if;
   end Negate_Top;

   procedure Combine_Top (V : in out Value_Stack; Op : Binary_Operator)
   with Post => V.Used <= V.Used'Old
   is
   begin
      if V.Used >= Binary_Arity then
         V.Used := V.Used - 1;
         V.Items (V.Used) :=
           Combine (V.Items (V.Used), Op, V.Items (V.Used + 1));
      end if;
   end Combine_Top;

   --  A bounded stack machine, no recursion.  Every access is guarded
   --  by Used itself, so a Compiled value that (should never, but) does
   --  not balance still evaluates safely instead of raising --
   --  functional correctness for a well-formed Compiled is the test
   --  suite's job, not this loop's.  E.Count = 0 (never compiled, or
   --  refused) falls out of the same guards as the empty, always-false
   --  expression.
   function Eval (E : Compiled) return Boolean is
      Values : Value_Stack;
   begin
      for I in 1 .. E.Count loop
         pragma Loop_Invariant (Values.Used <= I - 1);
         case E.Tokens (I).Kind is
            when Tag             =>
               Push_Value
                 (Values,
                  Has_Tag (E.Text (E.Tokens (I).First .. E.Tokens (I).Last)));

            when Op_Not          =>
               Negate_Top (Values);

            when Binary_Operator =>
               Combine_Top (Values, E.Tokens (I).Kind);
         end case;
      end loop;
      return Values.Used > 0 and then Values.Items (Token_Index'First);
   end Eval;

end Fabula.Tags;
