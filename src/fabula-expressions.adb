package body Fabula.Expressions
  with SPARK_Mode
is

   pragma
     Compile_Time_Error
       (Limits.Max_Match_Choices <= Limits.Max_Pattern_Tokens,
        "the choice stack must hold one choice per pattern token");

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

   No_Token : constant Token :=
     (Kind    => Literal,
      First   => 1,
      Middle  => 0,
      Last    => 0,
      Param   => P_Anonymous,
      Skip_To => 1);

   Refused_Pattern : constant Compiled :=
     (Valid  => False,
      Text   => [others => ' '],
      Count  => 0,
      Tokens =>
        [others =>
           (Kind    => Literal,
            First   => 1,
            Middle  => 0,
            Last    => 0,
            Param   => P_Anonymous,
            Skip_To => 1)]);

   type Group_Stack is array (Token_Index) of Token_Index;

   --  The state of one Compile run.  Result.Text (1 .. Used) holds the
   --  literal characters so far; Result.Text (Run_First .. Used) is the
   --  literal run no token covers yet.  Groups (1 .. Depth) are the open
   --  groups' Optional tokens, innermost last.
   type Builder is record
      Result    : Compiled;
      Used      : Char_Count := 0;
      Run_First : Char_Index := 1;
      Params    : Capture_Count := 0;
      Depth     : Token_Count := 0;
      Groups    : Group_Stack := [others => 1];
      Refused   : Boolean := False;
   end record;

   function Builder_OK (B : Builder) return Boolean
   is (B.Depth <= B.Result.Count);
   --  Open groups never outnumber tokens, so a group push always fits.

   function Is_Word_Char (C : Character) return Boolean
   is (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');

   function Literal_Token (First : Char_Index; Last : Char_Count) return Token
   is ((No_Token with delta First => First, Last => Last));

   --  The Keys row whose spelling starts at Source (From), or 0.  Keys
   --  are case-sensitive and must match exactly.
   function Key_At (Source : String; From : Positive) return Natural
   with
     Pre  =>
       Source'First = 1
       and then Source'Length <= Limits.Max_Pattern_Length
       and then From in Source'Range,
     Post =>
       Key_At'Result <= Keys'Last
       and then (if Key_At'Result > 0
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
      return 0;
   end Key_At;

   --  True when Source (From) opens a brace group that no key spells and
   --  that is not digits with at most one comma, like {56} or {1,3}.
   --  The group ends at the first } no backslash escapes; with no such
   --  }, the { is a lone brace and literal text.
   function Unknown_Key_At (Source : String; From : Positive) return Boolean
   with
     Pre =>
       Source'First = 1
       and then Source'Length <= Limits.Max_Pattern_Length
       and then From in Source'Range
   is
      Has_Digit : Boolean := False;
      Has_Comma : Boolean := False;
      Other     : Boolean := False;
   begin
      for J in From + 1 .. Source'Last loop
         if Source (J) = '}' and then Source (J - 1) /= '\' then
            return Other or else not Has_Digit;
         elsif Source (J) in '0' .. '9' then
            Has_Digit := True;
         elsif Source (J) = ',' and then not Has_Comma then
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
       and then B.Depth = B.Depth'Old
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
         B.Depth := B.Depth + 1;
         B.Groups (B.Depth) := B.Result.Count;
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
      if B.Depth = 0 then
         B.Refused := True;
         return;
      end if;
      Flush_Run (B);
      B.Result.Tokens (B.Groups (B.Depth)).Skip_To := B.Result.Count + 1;
      B.Depth := B.Depth - 1;
   end Close_Group;

   --  A slash starts a choice when a word character follows it and the
   --  literal run ends in one.  A word that an earlier choice consumed
   --  is not part of the run, so a/b/c chooses a or b, then reads /c.
   function Starts_Choice
     (B : Builder; Source : String; I : Positive) return Boolean
   is (I < Source'Last
       and then Is_Word_Char (Source (I + 1))
       and then B.Run_First <= B.Used
       and then Is_Word_Char (B.Result.Text (B.Used)))
   with Pre => Source'First = 1 and then I in Source'Range;

   --  Emits the choice whose slash is Source (I): the left word is the
   --  word the literal run ends in, the right word the longest word
   --  after the slash.  I moves past the right word.
   procedure Add_Alternation
     (B : in out Builder; Source : String; I : in out Positive)
   with
     Pre  =>
       Source'First = 1
       and then Source'Length <= Limits.Max_Pattern_Length
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
      Word_First : Char_Index := B.Used;
      Word_Last  : Positive := I + 1;
   begin
      while Word_First > B.Run_First
        and then Is_Word_Char (B.Result.Text (Word_First - 1))
      loop
         pragma Loop_Invariant (Word_First in B.Run_First .. B.Used);
         pragma Loop_Variant (Decreases => Word_First);
         Word_First := Word_First - 1;
      end loop;
      while Word_Last < Source'Last
        and then Is_Word_Char (Source (Word_Last + 1))
      loop
         pragma Loop_Invariant (Word_Last in I + 1 .. Source'Last - 1);
         pragma Loop_Variant (Increases => Word_Last);
         Word_Last := Word_Last + 1;
      end loop;
      if B.Run_First < Word_First then
         Add_Token
           (B.Result, B.Refused, Literal_Token (B.Run_First, Word_First - 1));
      end if;
      declare
         Middle : constant Char_Count := B.Used;
         Added  : constant Positive := Word_Last - I;
      begin
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
      end;
      B.Run_First := B.Used + 1;
      I := Word_Last + 1;
   end Add_Alternation;

   --  Reads one construct at Source (I) and moves I past it.  A
   --  backslash makes the next parenthesis or brace literal; before any
   --  other character it is a literal backslash itself.
   procedure Consume (B : in out Builder; Source : String; I : in out Positive)
   with
     Pre  =>
       Source'First = 1
       and then Source'Length <= Limits.Max_Pattern_Length
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
      Key : constant Natural := (if C = '{' then Key_At (Source, I) else 0);
   begin
      if C = '\'
        and then I < Source'Last
        and then Source (I + 1) in '(' | ')' | '{' | '}'
      then
         Append_Char (B, Source (I + 1));
         I := I + 2;
      elsif C = '(' then
         Open_Group (B);
         I := I + 1;
      elsif C = ')' then
         Close_Group (B);
         I := I + 1;
      elsif Key > 0 then
         Add_Param (B, Keys (Key).Kind);
         I := I + Keys (Key).Length;
      elsif C = '{' and then Unknown_Key_At (Source, I) then
         B.Refused := True;
         I := I + 1;
      elsif C = '/' and then Starts_Choice (B, Source, I) then
         Add_Alternation (B, Source, I);
      else
         Append_Char (B, C);
         I := I + 1;
      end if;
   end Consume;

   procedure Compile
     (Pattern : String; Result : out Compiled; Ok : out Boolean)
   is
      Source : constant String (1 .. Pattern'Length) := Pattern;
      B      : Builder;
      I      : Positive := 1;
   begin
      while I <= Source'Last and then not B.Refused loop
         pragma Loop_Invariant (B.Used < I and then Builder_OK (B));
         pragma Loop_Variant (Increases => I);
         Consume (B, Source, I);
      end loop;
      Flush_Run (B);
      Ok := not B.Refused and then B.Depth = 0;
      Result := (if Ok then B.Result else Refused_Pattern);
      Result.Valid := Ok;
   end Compile;

   --  Match searches depth first over (token, text position) states.

   subtype Text_Position is Positive range 1 .. Limits.Max_Line_Length + 1;
   subtype Alt_Count is Natural range 0 .. Limits.Max_Line_Length + 2;
   subtype Choice_Depth is Positive range 1 .. Limits.Max_Match_Choices;
   subtype Text_Length is Natural range 0 .. Limits.Max_Line_Length;

   No_Captures : constant Capture_List :=
     (Count => 0,
      Items => [others => (First => 1, Last => 0, Kind => P_Anonymous)]);

   function Slice_OK (Cap : Capture; Length : Text_Length) return Boolean
   is (Cap.First <= Length + 1
       and then Cap.Last <= Length
       and then Cap.Last >= Cap.First - 1);

   function Empty_At (Pos : Positive) return Capture
   is ((First => Pos, Last => Pos - 1, Kind => P_Anonymous));

   --  One state on the current search path: token PC at text position
   --  Pos, and which of its alternatives to try next.  A Parameter's
   --  alternatives are the capture ends High, High - 1, and so on, but
   --  never Hole; Cap is the capture of the alternative last taken.
   type Choice is record
      PC       : Token_Index := 1;
      Pos      : Text_Position := 1;
      Next     : Alt_Count := 0;
      Limit    : Alt_Count := 0;
      High     : Text_Position := 1;
      Hole     : Natural := 0;
      Is_Param : Boolean := False;
      Cap      : Capture := (First => 1, Last => 0, Kind => P_Anonymous);
   end record;

   function Choice_OK (C : Choice; Length : Text_Length) return Boolean
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
      PC     : Token_Position := 1;
      Pos    : Text_Position := 1;
      Cap    : Capture := (First => 1, Last => 0, Kind => P_Anonymous);
   end record;

   --  Candidate capture ends for one parameter: High down through
   --  High - Count + 1, skipping Hole.
   type Span is record
      High  : Text_Position;
      Count : Alt_Count;
      Hole  : Natural;
   end record;

   type Char_Class is (Digit, Non_Space, Non_Break, Non_Quote);

   --  Non_Space excludes the six characters a regular expression's \s
   --  names; Non_Break excludes the two line breaks its dot refuses.
   function In_Class (C : Character; Class : Char_Class) return Boolean
   is (case Class is
         when Digit     => C in '0' .. '9',
         when Non_Space =>
           C not in ' ' | ASCII.HT | ASCII.LF | ASCII.VT | ASCII.FF | ASCII.CR,
         when Non_Break => C not in ASCII.LF | ASCII.CR,
         when Non_Quote => C /= '"');

   function Text_OK (Text : String) return Boolean
   is (Text'First = 1 and then Text'Length <= Limits.Max_Line_Length);

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
   is (if Pos <= Text'Length and then Text (Pos) = '-' then 1 else 0)
   with Pre => Text_OK (Text);

   function Span_OK (S : Span; Length : Text_Length) return Boolean
   is (S.High <= Length + 1);

   --  An optional minus sign, then one or more digits.
   function Integer_Span (Text : String; Pos : Text_Position) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Integer_Span'Result, Text'Length)
   is
      Sign  : constant Natural := Sign_Width (Text, Pos);
      Whole : constant Natural := Run_Length (Text, Pos + Sign, Digit);
   begin
      return (High => Pos + Sign + Whole, Count => Whole, Hole => 0);
   end Integer_Span;

   --  An optional minus sign, optional digits, an optional point, then
   --  one or more digits.  The end just after a point with no digits
   --  following it is the Hole: "5." is not a real number.
   function Real_Span (Text : String; Pos : Text_Position) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Real_Span'Result, Text'Length)
   is
      Sign     : constant Natural := Sign_Width (Text, Pos);
      Whole    : constant Natural := Run_Length (Text, Pos + Sign, Digit);
      Point    : constant Positive := Pos + Sign + Whole;
      Fraction : constant Natural :=
        (if Point <= Text'Length and then Text (Point) = '.'
         then Run_Length (Text, Point + 1, Digit)
         else 0);
   begin
      if Fraction = 0 then
         return (High => Point, Count => Whole, Hole => 0);
      elsif Whole = 0 then
         return (High => Point + 1 + Fraction, Count => Fraction, Hole => 0);
      end if;
      return
        (High  => Point + 1 + Fraction,
         Count => Fraction + 1 + Whole,
         Hole  => Point + 1);
   end Real_Span;

   --  Any run of Class characters, the empty run included.
   function Run_Span
     (Text : String; Pos : Text_Position; Class : Char_Class) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Run_Span'Result, Text'Length)
   is
      Run : constant Natural := Run_Length (Text, Pos, Class);
   begin
      return (High => Pos + Run, Count => Run + 1, Hole => 0);
   end Run_Span;

   --  A double quote, anything but a double quote, then a double quote.
   function Quoted_Span (Text : String; Pos : Text_Position) return Span
   with
     Pre  => Text_OK (Text) and then Pos <= Text'Length + 1,
     Post => Span_OK (Quoted_Span'Result, Text'Length)
   is
      None : constant Span := (High => Pos, Count => 0, Hole => 0);
   begin
      if Pos > Text'Length or else Text (Pos) /= '"' then
         return None;
      end if;
      declare
         Close : constant Positive :=
           Pos + 1 + Run_Length (Text, Pos + 1, Non_Quote);
      begin
         if Close > Text'Length then
            return None;
         end if;
         return (High => Close + 1, Count => 1, Hole => 0);
      end;
   end Quoted_Span;

   function Param_Span
     (Kind : Param_Kind; Text : String; Pos : Text_Position) return Span
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
     (P : Compiled; Text : String; PC : Token_Index; Pos : Text_Position)
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
         Next     => 0,
         Limit    => 1,
         High     => Pos,
         Hole     => 0,
         Is_Param => False,
         Cap      => Empty_At (Pos));
   begin
      case Tok.Kind is
         when Literal                =>
            null;

         when Optional | Alternation =>
            Result.Limit := 2;

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
        (if Last >= First then Last - First + 1 else 0);
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

   --  Alternative K of an Optional group: 0 enters the body, 1 skips it.
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
      if K > 0 then
         Result.Viable := Skip_To > C.PC and then Skip_To <= P.Count + 1;
         Result.PC := Skip_To;
      end if;
      return Result;
   end Optional_Move;

   --  Alternative K of a Parameter: the capture that ends K places
   --  before the longest.  A quoted string's capture leaves out its
   --  quotes, so its alternatives never end before C.Pos + 2.
   function Param_Move
     (C : Choice; K : Alt_Count; Kind : Param_Kind; Length : Text_Length)
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
      Quote  : constant Natural := (if Kind = P_String then 1 else 0);
      Result : Move :=
        (Viable => False,
         PC     => C.PC + 1,
         Pos    => C.Pos,
         Cap    => Empty_At (C.Pos));
   begin
      if K <= C.High - C.Pos - 2 * Quote and then C.High - K /= C.Hole then
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
            if K = 0 then
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
     (P : Compiled; Failed : Failed_Table; Length : Text_Length) return Boolean
   is (Failed'First (1) = 1
       and then Failed'Last (1) = P.Count
       and then Failed'First (2) = 1
       and then Failed'Last (2) = Length + 1);

   --  A move is open when it completes the match, or leads to a state
   --  not yet shown to fail.
   function Open
     (P : Compiled; Failed : Failed_Table; M : Move; Length : Text_Length)
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
      M := (Viable => False, PC => 1, Pos => 1, Cap => Empty_At (1));
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
      Length   : Text_Length;
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
      Matched  : out Boolean)
   with
     Pre  => Text_OK (Text) and then P.Count >= 1,
     Post =>
       (if not Matched then Captures.Count = 0)
       and then (for all I in 1 .. Captures.Count =>
                   Slice_OK (Captures.Items (I), Text'Length))
   is
      Length : constant Text_Length := Text'Length;
      Failed : Failed_Table (1 .. P.Count, 1 .. Length + 1) :=
        [others => [others => False]];
      Stack  : Choice_Stack;
      Depth  : Choice_Depth := 1;
      Budget : Natural := P.Count * (Length + 1);
      M      : Move;
   begin
      Captures := No_Captures;
      Matched := False;
      Stack (1) := Enter (P, Text, 1, 1);
      --  Termination measure, lexicographic: (Budget, Depth).  A push
      --  keeps Budget and deepens the path, which the token count
      --  bounds.  A failure marks one fresh state and spends one unit of
      --  Budget, which starts at the number of states, so the Budget = 0
      --  exit is never taken: it only lets the prover see the bound.
      loop
         pragma
           Loop_Invariant
             (for all D in 1 .. Depth =>
                Stack (D).PC >= D
                and then Stack (D).PC <= P.Count
                and then Choice_OK (Stack (D), Length));
         pragma Loop_Invariant (not Matched and then Captures.Count = 0);
         pragma Loop_Variant (Decreases => Budget, Increases => Depth);
         Next_Viable (P, Text, Failed, Stack (Depth), M);
         if not M.Viable then
            Failed (Stack (Depth).PC, Stack (Depth).Pos) := True;
            exit when Depth = 1 or else Budget = 0;
            Budget := Budget - 1;
            Depth := Depth - 1;
         elsif M.PC > P.Count then
            Collect (Stack, Depth, Length, Captures);
            Matched := True;
            exit;
         else
            Depth := Depth + 1;
            Stack (Depth) := Enter (P, Text, M.PC, M.Pos);
         end if;
      end loop;
   end Search;

   procedure Match
     (P        : Compiled;
      Text     : String;
      Captures : out Capture_List;
      Matched  : out Boolean) is
   begin
      Captures := No_Captures;
      Matched := False;
      if not P.Valid then
         return;
      elsif P.Count = 0 then
         Matched := Text'Length = 0;
         return;
      end if;
      Search (P, Text, Captures, Matched);
   end Match;

end Fabula.Expressions;
