package body Fabula.Expressions
  with SPARK_Mode
is

   pragma
     Compile_Time_Error
       (Limits.Max_Match_Choices <= Limits.Max_Pattern_Tokens,
        "the choice stack must hold one choice per pattern token");

   subtype Column is Scan.Column;
   subtype Line_Length is Scan.Line_Length;

   --  Compile reads the pattern once, left to right, filling a Builder.

   Key_Width : constant := 8;
   --  The longest parameter key spelling, "{string}" and "{double}".

   type Key_Row is record
      Text   : String (1 .. Key_Width);
      Length : Positive range 1 .. Key_Width;
      Kind   : Param_Kind;
   end record;

   --  The nine parameter keys.  Each spelling is padded to one width so
   --  the rows form one array; Length is the real spelling length.
   --!format off
   Keys : constant array (Positive range <>) of Key_Row :=
     [(Text => "{byte}  ", Length => 6, Kind => P_Byte),
      (Text => "{short} ", Length => 7, Kind => P_Short),
      (Text => "{int}   ", Length => 5, Kind => P_Int),
      (Text => "{long}  ", Length => 6, Kind => P_Long),
      (Text => "{float} ", Length => 7, Kind => P_Float),
      (Text => "{double}", Length => 8, Kind => P_Double),
      (Text => "{string}", Length => 8, Kind => P_String),
      (Text => "{word}  ", Length => 6, Kind => P_Word),
      (Text => "{}      ", Length => 2, Kind => P_Anonymous)];
   --!format on

   --  What Key_At answers when no key starts at the position.
   No_Key : constant := 0;

   No_Token : constant Token := (others => <>);

   Refused_Pattern : constant Compiled := (others => <>);

   type Group_Stack is array (Token_Index) of Token_Index;

   --  The state of one Compile run.  Result.Text (1 .. Used) holds the
   --  literal characters so far; Result.Text (Run_First .. Used) is the
   --  literal run no token covers yet.  Groups (1 .. Open_Count) are the
   --  open groups' Optional tokens, innermost last.
   type Builder is record
      Result     : Compiled;
      Used       : Char_Count := Char_Count'First;
      Run_First  : Char_Index := Char_Index'First;
      Params     : Capture_Count := Capture_Count'First;
      Open_Count : Token_Count := Token_Count'First;
      Groups     : Group_Stack := [others => Token_Index'First];
      Refused    : Boolean := False;
   end record;

   function Builder_OK (B : Builder) return Boolean
   is (B.Open_Count <= B.Result.Count);
   --  Open groups never outnumber tokens, so a group push always fits.

   --  Source is a pattern Compile may read.
   function Is_Source (Source : String) return Boolean
   is (Source'First = Char_Index'First
       and then Source'Length <= Limits.Max_Pattern_Length);

   function Literal_Token (First : Char_Index; Last : Char_Count) return Token
   is ((No_Token with delta First => First, Last => Last));

   --  The Keys row whose spelling starts at Source (From), or No_Key.
   --  Keys are case-sensitive and must match exactly.
   function Key_At (Source : String; From : Positive) return Natural
   with
     Pre  => Is_Source (Source) and then From in Source'Range,
     Post =>
       Key_At'Result <= Keys'Last
       and then (if Key_At'Result /= No_Key
                 then From + Keys (Key_At'Result).Length - 1 <= Source'Last)
   is
   begin
      for Row in Keys'Range loop
         if Keys (Row).Length - 1 <= Source'Last - From
           and then Source (From .. From + Keys (Row).Length - 1)
                    = Keys (Row).Text (1 .. Keys (Row).Length)
         then
            return Row;
         end if;
      end loop;
      return No_Key;
   end Key_At;

   --  True when Source (From) opens a brace group that no key spells and
   --  that is not digits with at most one Count_Separator, like {56} or
   --  {1,3}.  The group ends at the first Key_Closer no Escape_Mark
   --  escapes; with no such closer, the opener is a lone brace and
   --  literal text.
   function Unknown_Key_At (Source : String; From : Positive) return Boolean
   with Pre => Is_Source (Source) and then From in Source'Range
   is
      Has_Digit : Boolean := False;
      Has_Comma : Boolean := False;
      Other     : Boolean := False;
   begin
      for J in From + 1 .. Source'Last loop
         if Source (J) = Key_Closer and then Source (J - 1) /= Escape_Mark then
            return Other or else not Has_Digit;
         elsif Source (J) in Decimal_Digit then
            Has_Digit := True;
         elsif Source (J) = Count_Separator and then not Has_Comma then
            Has_Comma := True;
         else
            Other := True;
         end if;
      end loop;
      return False;
   end Unknown_Key_At;

   --  Appends New_Token, or marks the pattern refused when the token
   --  table is full.
   procedure Add_Token
     (Result : in out Compiled; Refused : in out Boolean; New_Token : Token)
   with
     Post =>
       (if Result.Count'Old < Limits.Max_Pattern_Tokens
        then Result.Count = Result.Count'Old + 1 and then Refused = Refused'Old
        else Result.Count = Result.Count'Old and then Refused)
   is
   begin
      if Result.Count = Limits.Max_Pattern_Tokens then
         Refused := True;
         return;
      end if;
      Result.Count := Result.Count + 1;
      Result.Tokens (Result.Count) := New_Token;
   end Add_Token;

   procedure Append_Char (B : in out Builder; C : Character)
   with
     Pre  => B.Used < Limits.Max_Pattern_Length and then Builder_OK (B),
     Post => B.Used = B.Used'Old + 1 and then Builder_OK (B)
   is
   begin
      B.Used := B.Used + 1;
      B.Result.Text (B.Used) := C;
   end Append_Char;

   --  Closes the literal run as a Literal token, if it holds anything.
   procedure Flush_Run (B : in out Builder)
   with
     Pre  => Builder_OK (B),
     Post =>
       Builder_OK (B)
       and then B.Used = B.Used'Old
       and then B.Open_Count = B.Open_Count'Old
       and then B.Params = B.Params'Old
   is
   begin
      if B.Run_First <= B.Used then
         Add_Token (B.Result, B.Refused, Literal_Token (B.Run_First, B.Used));
      end if;
      B.Run_First := B.Used + 1;
   end Flush_Run;

   procedure Add_Param (B : in out Builder; Kind : Param_Kind)
   with
     Pre  => Builder_OK (B),
     Post => Builder_OK (B) and then B.Used = B.Used'Old
   is
   begin
      if B.Params = Limits.Max_Args_Per_Step then
         B.Refused := True;
         return;
      end if;
      Flush_Run (B);
      Add_Token
        (B.Result,
         B.Refused,
         (No_Token with delta Kind => Parameter, Param => Kind));
      B.Params := B.Params + 1;
   end Add_Param;

   procedure Open_Group (B : in out Builder)
   with
     Pre  => Builder_OK (B),
     Post => Builder_OK (B) and then B.Used = B.Used'Old
   is
      Before : Token_Count;
   begin
      Flush_Run (B);
      Before := B.Result.Count;
      Add_Token (B.Result, B.Refused, (No_Token with delta Kind => Optional));
      if B.Result.Count > Before then
         B.Open_Count := B.Open_Count + 1;
         B.Groups (B.Open_Count) := B.Result.Count;
      end if;
   end Open_Group;

   --  Ends the innermost open group: its body stops before the next
   --  token.  A close with no group open refuses the pattern.
   procedure Close_Group (B : in out Builder)
   with
     Pre  => Builder_OK (B),
     Post => Builder_OK (B) and then B.Used = B.Used'Old
   is
   begin
      if B.Open_Count = 0 then
         B.Refused := True;
         return;
      end if;
      Flush_Run (B);
      B.Result.Tokens (B.Groups (B.Open_Count)).Skip_To := B.Result.Count + 1;
      B.Open_Count := B.Open_Count - 1;
   end Close_Group;

   --  A Choice_Mark starts a choice when a word character follows it and
   --  the literal run ends in one.  A word that an earlier choice
   --  consumed is not part of the run, so a/b/c chooses a or b, then
   --  reads /c.
   function Starts_Choice
     (B : Builder; Source : String; I : Positive) return Boolean
   is (I < Source'Last
       and then Source (I + 1) in Word_Char
       and then B.Run_First <= B.Used
       and then B.Result.Text (B.Used) in Word_Char)
   with Pre => Source'First = Char_Index'First and then I in Source'Range;

   --  The first index of the word the literal run ends in.
   function Word_Start (B : Builder) return Char_Index
   with
     Pre  => B.Run_First <= B.Used,
     Post => Word_Start'Result in B.Run_First .. B.Used
   is
      Word_First : Char_Index := B.Used;
   begin
      while Word_First > B.Run_First
        and then B.Result.Text (Word_First - 1) in Word_Char
      loop
         pragma Loop_Invariant (Word_First in B.Run_First .. B.Used);
         pragma Loop_Variant (Decreases => Word_First);
         Word_First := Word_First - 1;
      end loop;
      return Word_First;
   end Word_Start;

   --  The last index of the longest word after the Choice_Mark at
   --  Source (I).
   function Word_End (Source : String; I : Positive) return Positive
   with
     Pre  => Is_Source (Source) and then I < Source'Last,
     Post => Word_End'Result in I + 1 .. Source'Last
   is
      Word_Last : Positive := I + 1;
   begin
      while Word_Last < Source'Last
        and then Source (Word_Last + 1) in Word_Char
      loop
         pragma Loop_Invariant (Word_Last in I + 1 .. Source'Last - 1);
         pragma Loop_Variant (Increases => Word_Last);
         Word_Last := Word_Last + 1;
      end loop;
      return Word_Last;
   end Word_End;

   --  Closes the part of the literal run before Word_First as a Literal
   --  token, if that part holds anything.
   procedure Flush_Before (B : in out Builder; Word_First : Char_Index)
   with
     Pre  => Builder_OK (B) and then Word_First <= B.Used,
     Post =>
       Builder_OK (B)
       and then B.Used = B.Used'Old
       and then B.Run_First = B.Run_First'Old
       and then B.Open_Count = B.Open_Count'Old
   is
   begin
      if B.Run_First < Word_First then
         Add_Token
           (B.Result, B.Refused, Literal_Token (B.Run_First, Word_First - 1));
      end if;
   end Flush_Before;

   --  Emits the choice between the run's last word, Result.Text
   --  (Word_First .. Used), and Source (I + 1 .. Word_Last), which is
   --  copied after it.  The literal before the left word goes first.
   procedure Emit_Choice
     (B          : in out Builder;
      Source     : String;
      I          : Positive;
      Word_First : Char_Index;
      Word_Last  : Positive)
   with
     Pre  =>
       Is_Source (Source)
       and then Word_Last <= Source'Last
       and then I < Word_Last
       and then B.Used < I
       and then Word_First in B.Run_First .. B.Used
       and then Builder_OK (B),
     Post => B.Used = B.Used'Old + (Word_Last - I) and then Builder_OK (B)
   is
      Middle : constant Char_Count := B.Used;
      Added  : constant Positive := Word_Last - I;
   begin
      Flush_Before (B, Word_First);
      B.Result.Text (Middle + 1 .. Middle + Added) :=
        Source (I + 1 .. Word_Last);
      B.Used := Middle + Added;
      Add_Token
        (B.Result,
         B.Refused,
         (No_Token
          with delta
            Kind   => Alternation,
            First  => Word_First,
            Middle => Middle,
            Last   => B.Used));
      B.Run_First := B.Used + 1;
   end Emit_Choice;

   --  Emits the choice whose Choice_Mark is Source (I): the left word is
   --  the word the literal run ends in, the right word the longest word
   --  after the mark.  I moves past the right word.
   procedure Add_Alternation
     (B : in out Builder; Source : String; I : in out Positive)
   with
     Pre  =>
       Is_Source (Source)
       and then I < Source'Last
       and then B.Run_First <= B.Used
       and then B.Used < I
       and then Builder_OK (B),
     Post =>
       I > I'Old
       and then I <= Source'Last + 1
       and then B.Used < I
       and then Builder_OK (B)
   is
      Word_First : constant Char_Index := Word_Start (B);
      Word_Last  : constant Positive := Word_End (Source, I);
   begin
      Emit_Choice (B, Source, I, Word_First, Word_Last);
      I := Word_Last + 1;
   end Add_Alternation;

   --  Reads one construct at Source (I) and moves I past it.  An
   --  Escape_Mark makes the next Escapable character literal; before any
   --  other character it is a literal backslash itself.
   procedure Consume (B : in out Builder; Source : String; I : in out Positive)
   with
     Pre  =>
       Is_Source (Source)
       and then I in Source'Range
       and then B.Used < I
       and then Builder_OK (B),
     Post =>
       I > I'Old
       and then I <= Source'Last + 1
       and then B.Used < I
       and then Builder_OK (B)
   is
      C   : constant Character := Source (I);
      Key : constant Natural :=
        (if C = Key_Opener then Key_At (Source, I) else No_Key);
   begin
      if C = Escape_Mark
        and then I < Source'Last
        and then Source (I + 1) in Escapable
      then
         Append_Char (B, Source (I + 1));
         I := I + Escape_Length;
      elsif C = Group_Opener then
         Open_Group (B);
         I := I + 1;
      elsif C = Group_Closer then
         Close_Group (B);
         I := I + 1;
      elsif Key /= No_Key then
         Add_Param (B, Keys (Key).Kind);
         I := I + Keys (Key).Length;
      elsif C = Key_Opener and then Unknown_Key_At (Source, I) then
         B.Refused := True;
         I := I + 1;
      elsif C = Choice_Mark and then Starts_Choice (B, Source, I) then
         Add_Alternation (B, Source, I);
      else
         Append_Char (B, C);
         I := I + 1;
      end if;
   end Consume;

   function Compile (Pattern : String) return Compiled is
      Source : constant String (1 .. Pattern'Length) := Pattern;
      B      : Builder;
      I      : Positive := Source'First;
   begin
      while I <= Source'Last and then not B.Refused loop
         pragma Loop_Invariant (B.Used < I and then Builder_OK (B));
         pragma Loop_Variant (Increases => I);
         Consume (B, Source, I);
      end loop;
      Flush_Run (B);
      return
        (if not B.Refused and then B.Open_Count = 0
         then (B.Result with delta Valid => True)
         else Refused_Pattern);
   end Compile;

   --  Match searches depth first over (token, text position) states.

   subtype Alt_Count is Natural range 0 .. Limits.Max_Line_Length + 2;
   subtype Choice_Depth is Positive range 1 .. Limits.Max_Match_Choices;

   No_Captures : constant Capture_List := (others => <>);

   No_Match : constant Step_Match := (others => <>);

   --  The length of a run of no characters: an absent sign, fraction or
   --  quote.
   No_Run : constant := 0;

   Minus_Width : constant := 1;
   --  An {int}, {float} or {double} capture's optional Minus_Sign.

   Quote_Width : constant := 1;
   --  A {string} capture leaves out one Quote_Mark at each end.

   --  The number of ways a token can match: a literal and a quoted
   --  string one; an optional group (enter or skip it) and a choice
   --  (its left or its right word) two.
   Single_Alternative  : constant := 1;
   Choice_Alternatives : constant := 2;

   --  The alternative a choice tries first: an optional group's body,
   --  a choice's left word, a parameter's longest capture.
   First_Alternative : constant Alt_Count := 0;

   --  A Span's Hole when every candidate end in its range is one.
   No_Hole : constant := 0;

   function Slice_OK (Cap : Capture; Length : Line_Length) return Boolean
   is (Cap.First <= Length + 1
       and then Cap.Last <= Length
       and then Cap.Last >= Cap.First - 1);

   function Empty_At (Pos : Column) return Capture
   is ((First => Pos, Last => Pos - 1, Kind => P_Anonymous));

   --  One state on the current search path: token PC at text position
   --  Pos, and which of its alternatives to try next.  A Parameter's
   --  alternatives are the capture ends High, High - 1, and so on, but
   --  never Hole; Cap is the capture of the alternative last taken.
   type Choice is record
      PC       : Token_Index := Token_Index'First;
      Pos      : Column := Column'First;
      Next     : Alt_Count := First_Alternative;
      Limit    : Alt_Count := First_Alternative;
      High     : Column := Column'First;
      Hole     : Natural := No_Hole;
      Is_Param : Boolean := False;
      Cap      : Capture;
   end record;

   function Choice_OK (C : Choice; Length : Line_Length) return Boolean
   is (C.Pos <= Length + 1
       and then C.High <= Length + 1
       and then Slice_OK (C.Cap, Length));

   type Choice_Stack is array (Choice_Depth) of Choice;

   --  Failed (PC, Pos) is True once the search has shown that no match
   --  continues from token PC at text position Pos.
   type Failed_Table is array (Positive range <>, Positive range <>) of Boolean
   with Pack;

   --  Where one alternative leads: the next token and text position.
   type Move is record
      Viable : Boolean := False;
      PC     : Token_Position := Token_Position'First;
      Pos    : Column := Column'First;
      Cap    : Capture;
   end record;

   No_Move : constant Move := (others => <>);

   --  Candidate capture ends for one parameter: High down through
   --  High - Count + 1, skipping Hole.
   type Span is record
      High  : Column;
      Count : Alt_Count;
      Hole  : Natural;
   end record;

   type Char_Class is (Digit, Non_Space, Non_Break, Non_Quote);

   --  Non_Space excludes the six White_Space characters a regular
   --  expression's \s names; Non_Break excludes the two line breaks its
   --  dot refuses.
   function In_Class (C : Character; Class : Char_Class) return Boolean
   is (case Class is
         when Digit     => C in Decimal_Digit,
         when Non_Space => C not in White_Space,
         when Non_Break => C not in ASCII.LF | ASCII.CR,
         when Non_Quote => C /= Quote_Mark);

   function Text_OK (Text : String) return Boolean
   is (Text'First = First_Column
       and then Text'Length <= Limits.Max_Line_Length);

   --  How many characters from Text (From) on belong to Class.
   function Run_Length
     (Text : String; From : Positive; Class : Char_Class) return Natural
   with
     Pre  => Text_OK (Text) and then From <= Text'Length + 1,
     Post => Run_Length'Result <= Text'Length + 1 - From
   is
      I : Positive := From;
   begin
      while I <= Text'Length and then In_Class (Text (I), Class) loop
         pragma Loop_Invariant (I in From .. Text'Length);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I - From;
   end Run_Length;

   function Sign_Width (Text : String; Pos : Positive) return Natural
   is (if Pos <= Text'Length and then Text (Pos) = Minus_Sign
       then Minus_Width
       else No_Run)
   with Pre => Text_OK (Text);

   function Span_OK (S : Span; Length : Line_Length) return Boolean
   is (S.High <= Length + 1);

   --  An optional minus sign, then one or more digits.
   function Integer_Span (Text : String; Pos : Column) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Integer_Span'Result, Text'Length)
   is
      Sign  : constant Natural := Sign_Width (Text, Pos);
      Whole : constant Natural := Run_Length (Text, Pos + Sign, Digit);
   begin
      return (High => Pos + Sign + Whole, Count => Whole, Hole => No_Hole);
   end Integer_Span;

   --  An optional minus sign, optional digits, an optional point, then
   --  one or more digits.  The end just after a point with no digits
   --  following it is the Hole: "5." is not a real number.
   function Real_Span (Text : String; Pos : Column) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Real_Span'Result, Text'Length)
   is
      Sign            : constant Natural := Sign_Width (Text, Pos);
      Whole_Length    : constant Natural :=
        Run_Length (Text, Pos + Sign, Digit);
      Point           : constant Positive := Pos + Sign + Whole_Length;
      Fraction_Length : constant Natural :=
        (if Point <= Text'Length and then Text (Point) = Decimal_Point
         then Run_Length (Text, Point + 1, Digit)
         else No_Run);
   begin
      if Fraction_Length = 0 then
         return (High => Point, Count => Whole_Length, Hole => No_Hole);
      elsif Whole_Length = 0 then
         return
           (High  => Point + 1 + Fraction_Length,
            Count => Fraction_Length,
            Hole  => No_Hole);
      end if;
      return
        (High  => Point + 1 + Fraction_Length,
         Count => Fraction_Length + 1 + Whole_Length,
         Hole  => Point + 1);
   end Real_Span;

   --  Any run of Class characters, the empty run included.
   function Run_Span
     (Text : String; Pos : Column; Class : Char_Class) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Run_Span'Result, Text'Length)
   is
      Run : constant Natural := Run_Length (Text, Pos, Class);
   begin
      return (High => Pos + Run, Count => Run + 1, Hole => No_Hole);
   end Run_Span;

   --  A Quote_Mark, anything but a Quote_Mark, then a Quote_Mark.
   function Quoted_Span (Text : String; Pos : Column) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Quoted_Span'Result, Text'Length)
   is
      None : constant Span := (High => Pos, Count => 0, Hole => No_Hole);
   begin
      if Pos > Text'Length or else Text (Pos) /= Quote_Mark then
         return None;
      end if;
      declare
         Close : constant Positive :=
           Pos + 1 + Run_Length (Text, Pos + 1, Non_Quote);
      begin
         if Close > Text'Length then
            return None;
         end if;
         return
           (High => Close + 1, Count => Single_Alternative, Hole => No_Hole);
      end;
   end Quoted_Span;

   function Param_Span
     (Kind : Param_Kind; Text : String; Pos : Column) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Param_Span'Result, Text'Length)
   is
   begin
      case Kind is
         when P_Byte | P_Short | P_Int | P_Long =>
            return Integer_Span (Text, Pos);

         when P_Float | P_Double                =>
            return Real_Span (Text, Pos);

         when P_Word                            =>
            return Run_Span (Text, Pos, Non_Space);

         when P_Anonymous                       =>
            return Run_Span (Text, Pos, Non_Break);

         when P_String                          =>
            return Quoted_Span (Text, Pos);
      end case;
   end Param_Span;

   --  The choice for token PC at text position Pos, before any of its
   --  alternatives has been tried.
   function Enter
     (P : Compiled; Text : String; PC : Token_Index; Pos : Column)
      return Choice
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post =>
       Enter'Result.PC = PC
       and then Enter'Result.Pos = Pos
       and then Choice_OK (Enter'Result, Text'Length)
   is
      Tok    : constant Token := P.Tokens (PC);
      Result : Choice :=
        (PC       => PC,
         Pos      => Pos,
         Next     => First_Alternative,
         Limit    => Single_Alternative,
         High     => Pos,
         Hole     => No_Hole,
         Is_Param => False,
         Cap      => Empty_At (Pos));
   begin
      case Tok.Kind is
         when Literal                =>
            null;

         when Optional | Alternation =>
            Result.Limit := Choice_Alternatives;

         when Parameter              =>
            declare
               S : constant Span := Param_Span (Tok.Param, Text, Pos);
            begin
               Result.Limit := S.Count;
               Result.High := S.High;
               Result.Hole := S.Hole;
               Result.Is_Param := True;
            end;
      end case;
      return Result;
   end Enter;

   --  Matching Text at C.Pos against the pattern text First .. Last.
   function Literal_Move
     (P     : Compiled;
      Text  : String;
      C     : Choice;
      First : Char_Index;
      Last  : Char_Count) return Move
   with
     Pre  => Text_OK (Text) and then Choice_OK (C, Text'Length),
     Post =>
       (if Literal_Move'Result.Viable
        then
          Literal_Move'Result.PC = C.PC + 1
          and then Literal_Move'Result.Pos <= Text'Length + 1)
       and then Slice_OK (Literal_Move'Result.Cap, Text'Length)
   is
      Length : constant Natural :=
        (if Last >= First then Last - First + 1 else No_Run);
      Result : Move :=
        (Viable => False,
         PC     => C.PC + 1,
         Pos    => C.Pos,
         Cap    => Empty_At (C.Pos));
   begin
      if Length <= Text'Length + 1 - C.Pos
        and then Text (C.Pos .. C.Pos + Length - 1) = P.Text (First .. Last)
      then
         Result.Viable := True;
         Result.Pos := C.Pos + Length;
      end if;
      return Result;
   end Literal_Move;

   --  Alternative K of an Optional group: the first enters the body,
   --  the other skips it.
   function Optional_Move
     (P : Compiled; C : Choice; K : Alt_Count; Skip_To : Token_Position)
      return Move
   with
     Pre  => C.PC <= P.Count,
     Post =>
       (if Optional_Move'Result.Viable
        then
          Optional_Move'Result.PC > C.PC
          and then Optional_Move'Result.PC <= P.Count + 1
          and then Optional_Move'Result.Pos = C.Pos)
       and then Optional_Move'Result.Cap = Empty_At (C.Pos)
   is
      Result : Move :=
        (Viable => True,
         PC     => C.PC + 1,
         Pos    => C.Pos,
         Cap    => Empty_At (C.Pos));
   begin
      if K /= First_Alternative then
         Result.Viable := Skip_To > C.PC and then Skip_To <= P.Count + 1;
         Result.PC := Skip_To;
      end if;
      return Result;
   end Optional_Move;

   --  Alternative K of a Parameter: the capture that ends K places
   --  before the longest.  A quoted string's capture leaves out its
   --  quotes, so its alternatives never end before C.Pos + 2.
   function Param_Move
     (C : Choice; K : Alt_Count; Kind : Param_Kind; Length : Line_Length)
      return Move
   with
     Pre  => Choice_OK (C, Length),
     Post =>
       (if Param_Move'Result.Viable
        then
          Param_Move'Result.PC = C.PC + 1
          and then Param_Move'Result.Pos <= Length + 1)
       and then Slice_OK (Param_Move'Result.Cap, Length)
   is
      Quote  : constant Natural :=
        (if Kind = P_String then Quote_Width else No_Run);
      Result : Move :=
        (Viable => False,
         PC     => C.PC + 1,
         Pos    => C.Pos,
         Cap    => Empty_At (C.Pos));
   begin
      if K <= C.High - C.Pos - Quote - Quote and then C.High - K /= C.Hole then
         Result.Viable := True;
         Result.Pos := C.High - K;
         Result.Cap :=
           (First => C.Pos + Quote,
            Last  => Result.Pos - 1 - Quote,
            Kind  => Kind);
      end if;
      return Result;
   end Param_Move;

   --  Where alternative K of choice C leads.
   function Alternative
     (P : Compiled; Text : String; C : Choice; K : Alt_Count) return Move
   with
     Pre  =>
       Text_OK (Text)
       and then C.PC <= P.Count
       and then Choice_OK (C, Text'Length),
     Post =>
       (if Alternative'Result.Viable
        then
          Alternative'Result.PC > C.PC
          and then Alternative'Result.PC <= P.Count + 1
          and then Alternative'Result.Pos <= Text'Length + 1)
       and then Slice_OK (Alternative'Result.Cap, Text'Length)
   is
      Tok : constant Token := P.Tokens (C.PC);
   begin
      case Tok.Kind is
         when Literal     =>
            return Literal_Move (P, Text, C, Tok.First, Tok.Last);

         when Alternation =>
            if K = First_Alternative then
               return Literal_Move (P, Text, C, Tok.First, Tok.Middle);
            end if;
            return Literal_Move (P, Text, C, Tok.Middle + 1, Tok.Last);

         when Optional    =>
            return Optional_Move (P, C, K, Tok.Skip_To);

         when Parameter   =>
            return Param_Move (C, K, Tok.Param, Text'Length);
      end case;
   end Alternative;

   function Table_OK
     (P : Compiled; Failed : Failed_Table; Length : Line_Length) return Boolean
   is (Failed'First (1) = Token_Index'First
       and then Failed'Last (1) = P.Count
       and then Failed'First (2) = Column'First
       and then Failed'Last (2) = Length + 1);

   --  A move is open when it completes the match, or leads to a state
   --  not yet shown to fail.
   function Open
     (P : Compiled; Failed : Failed_Table; M : Move; Length : Line_Length)
      return Boolean
   is (if M.PC > P.Count then M.Pos = Length + 1 else not Failed (M.PC, M.Pos))
   with Pre => Table_OK (P, Failed, Length) and then M.Pos <= Length + 1;

   --  Tries Top's remaining alternatives in order and stops at the
   --  first open one, recording its capture in Top.
   procedure Next_Viable
     (P      : Compiled;
      Text   : String;
      Failed : Failed_Table;
      Top    : in out Choice;
      M      : out Move)
   with
     Pre  =>
       Text_OK (Text)
       and then Table_OK (P, Failed, Text'Length)
       and then Top.PC <= P.Count
       and then Choice_OK (Top, Text'Length),
     Post =>
       Top.PC = Top.PC'Old
       and then Top.Pos = Top.Pos'Old
       and then Choice_OK (Top, Text'Length)
       and then (if M.Viable
                 then
                   M.PC > Top.PC
                   and then M.PC <= P.Count + 1
                   and then M.Pos <= Text'Length + 1)
   is
   begin
      M := No_Move;
      while Top.Next < Top.Limit loop
         pragma Loop_Invariant (Top.PC = Top.PC'Loop_Entry);
         pragma Loop_Invariant (Top.Pos = Top.Pos'Loop_Entry);
         pragma Loop_Invariant (Choice_OK (Top, Text'Length));
         pragma Loop_Variant (Increases => Top.Next);
         M := Alternative (P, Text, Top, Top.Next);
         Top.Next := Top.Next + 1;
         if M.Viable and then Open (P, Failed, M, Text'Length) then
            Top.Cap := M.Cap;
            return;
         end if;
      end loop;
      M.Viable := False;
   end Next_Viable;

   --  The captures of the parameters on the matched path, in order.
   procedure Collect
     (Stack    : Choice_Stack;
      Depth    : Choice_Depth;
      Length   : Line_Length;
      Captures : out Capture_List)
   with
     Pre  => (for all D in 1 .. Depth => Choice_OK (Stack (D), Length)),
     Post =>
       (for all I in 1 .. Captures.Count =>
          Slice_OK (Captures.Items (I), Length))
   is
   begin
      Captures := No_Captures;
      for D in 1 .. Depth loop
         pragma
           Loop_Invariant
             (for all I in 1 .. Captures.Count =>
                Slice_OK (Captures.Items (I), Length));
         if Stack (D).Is_Param
           and then Captures.Count < Limits.Max_Args_Per_Step
         then
            Captures.Count := Captures.Count + 1;
            Captures.Items (Captures.Count) := Stack (D).Cap;
         end if;
      end loop;
   end Collect;

   --  A search budget with no unit left.
   Spent : constant := 0;

   --  Searches depth first, in the order a backtracking regular
   --  expression tries alternatives, so the first full match found is
   --  the one it reports.  Stack (1 .. Depth) is the current path; token
   --  numbers rise strictly along it, so it holds at most one choice per
   --  token.  A state that fails is marked in Failed and never entered
   --  again, which keeps the search polynomial.
   procedure Search
     (P        : Compiled;
      Text     : String;
      Captures : out Capture_List;
      Found    : out Boolean)
   with
     Pre  => Text_OK (Text) and then P.Count > 0,
     Post =>
       (if not Found then Captures.Count = 0)
       and then (for all I in 1 .. Captures.Count =>
                   Slice_OK (Captures.Items (I), Text'Length))
   is
      Length : constant Line_Length := Text'Length;
      Failed : Failed_Table (1 .. P.Count, 1 .. Length + 1) :=
        [others => [others => False]];
      Stack  : Choice_Stack;
      Depth  : Choice_Depth := Choice_Depth'First;
      Budget : Natural := P.Count * (Length + 1);
      M      : Move;
   begin
      Captures := No_Captures;
      Found := False;
      Stack (Choice_Depth'First) :=
        Enter (P, Text, Token_Index'First, Column'First);
      --  Termination measure, lexicographic: (Budget, Depth).  A push
      --  keeps Budget and deepens the path, which the token count
      --  bounds.  A failure marks one fresh state and spends one unit of
      --  Budget, which starts at the number of states, so the Spent
      --  exit is never taken: it only lets the prover see the bound.
      loop
         pragma
           Loop_Invariant
             (for all D in 1 .. Depth =>
                Stack (D).PC >= D
                and then Stack (D).PC <= P.Count
                and then Choice_OK (Stack (D), Length));
         pragma Loop_Invariant (not Found and then Captures.Count = 0);
         pragma Loop_Variant (Decreases => Budget, Increases => Depth);
         Next_Viable (P, Text, Failed, Stack (Depth), M);
         if not M.Viable then
            Failed (Stack (Depth).PC, Stack (Depth).Pos) := True;
            exit when Depth = Choice_Depth'First or else Budget = Spent;
            Budget := Budget - 1;
            Depth := Depth - 1;
         elsif M.PC > P.Count then
            Collect (Stack, Depth, Length, Captures);
            Found := True;
            exit;
         else
            Depth := Depth + 1;
            Stack (Depth) := Enter (P, Text, M.PC, M.Pos);
         end if;
      end loop;
   end Search;

   function Match (P : Compiled; Text : String) return Step_Match is
      Result : Step_Match;
   begin
      if not P.Valid then
         return No_Match;
      end if;
      if P.Count = 0 then
         return (Found => Text'Length = 0, Captures => No_Captures);
      end if;
      Search (P, Text, Result.Captures, Result.Found);
      return Result;
   end Match;

end Fabula.Expressions;
