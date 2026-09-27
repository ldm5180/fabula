--  Splits one feature-file line into the parts the parser stores: tag
--  tokens, table cells, doc-string fence runs, and trimmed text.  Each
--  rule follows the reference interpreter's lexer; the parser's guards
--  and its commands both read lines only through here.
with Fabula.Limits;
with Fabula.Scan;
with Fabula.Searches;

private package Fabula.Line_Parts
  with Pure, SPARK_Mode
is

   subtype Column is Scan.Column;
   subtype Line_Length is Scan.Line_Length;

   --  The position Fence_Run and a cell's Stop hold when the line has
   --  none; positions in a line are numbered from 1.
   No_Position : constant Natural := Searches.Not_Found;

   --  A span of one line; Last < First is the empty span.
   type Span is record
      First : Column := Scan.Empty_First;
      Last  : Line_Length := Scan.Empty_Last;
   end record;

   Empty_Span : constant Span := (others => <>);

   function Is_Line (Line : String) return Boolean
   is (Line'First = First_Column
       and then Line'Length <= Limits.Max_Line_Length);

   --  S reads safely from Line: it is empty, or inside Line's range.
   function Within (Line : String; S : Span) return Boolean
   is (S.Last < S.First
       or else (S.First >= Line'First and then S.Last <= Line'Last));

   --  Line (From .. To) without its leading and trailing White_Space.
   function Trimmed (Line : String; From : Positive; To : Natural) return Span
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post =>
       Trimmed'Result.First >= From
       and then Trimmed'Result.Last <= To
       and then Trimmed'Result.Last >= Trimmed'Result.First - 1;

   function Only_Blank
     (Line : String; From : Positive; To : Natural) return Boolean
   is (for all I in From .. To => Line (I) in White_Space)
   with Pre => Is_Line (Line) and then To <= Line'Last;

   ---------------------------------------------------------------------
   --  Doc-string fences.
   ---------------------------------------------------------------------

   --  A doc-string fence starts at I: Scan.Fence_Length equal quote or
   --  backtick characters.  The one place this rule is written.
   function Fence_At (Line : String; I : Positive) return Boolean
   is (Line'Length >= Scan.Fence_Length
       and then I <= Line'Last - (Scan.Fence_Length - 1)
       and then (Line (I) = Scan.Quote_Fence
                 or else Line (I) = Scan.Backtick_Fence)
       and then (for all K in I + 1 .. I + (Scan.Fence_Length - 1) =>
                   Line (K) = Line (I)))
   with Pre => Is_Line (Line);

   --  The first fence run inside Line (From .. To), or No_Position.
   --  The reference lexer ends a doc string at the first such run
   --  anywhere on a line, not only at one that leads it.
   function Fence_Run
     (Line : String; From : Positive; To : Natural) return Natural
   with
     Pre  => Is_Line (Line) and then To <= Line'Length,
     Post =>
       Fence_Run'Result = No_Position
       or else (Fence_Run'Result >= From
                and then Fence_Run'Result + (Scan.Fence_Length - 1) <= To
                and then Fence_At (Line, Fence_Run'Result));

   ---------------------------------------------------------------------
   --  Tags.
   ---------------------------------------------------------------------

   --  The characters a tag may hold after its Scan.Tag_Mark.
   subtype Tag_Char is Character
   with
     Static_Predicate =>
       Tag_Char
       in Latin_Letter
        | Decimal_Digit
        | '_'
        | '-'
        | '.'
        | '#'
        | '/'
        | ':'
        | '$'
        | '*'
        | '<'
        | '>'
        | '''
        | '|'
        | '%'
        | '^'
        | '&'
        | '!'
        | '?';

   --  Line (From .. To) is a run of tags: every token starts with a
   --  Scan.Tag_Mark and holds only tag characters.  Tags may abut
   --  (@a@b is two), and Space_Or_Tab separates them.
   function Tags_Well_Formed
     (Line : String; From : Positive; To : Natural) return Boolean
   is (for all I in From .. To =>
         (Line (I) = Scan.Tag_Mark
          or else Line (I) in Tag_Char
          or else Line (I) in Space_Or_Tab)
         and then (if (I = From or else Line (I - 1) in Space_Or_Tab)
                     and then Line (I) not in Space_Or_Tab
                   then Line (I) = Scan.Tag_Mark))
   with
     Pre =>
       Is_Line (Line) and then From >= First_Column and then To <= Line'Last;

   --  The first tag at or after From within Line (From .. To): a
   --  Scan.Tag_Mark and the tag characters after it.  Empty when none
   --  starts there.
   function Next_Tag (Line : String; From : Positive; To : Natural) return Span
   with
     Pre  => Is_Line (Line) and then To <= Line'Last,
     Post =>
       (if Next_Tag'Result.Last >= Next_Tag'Result.First
        then
          Next_Tag'Result.First >= From and then Next_Tag'Result.Last <= To);

   ---------------------------------------------------------------------
   --  Table cells.
   ---------------------------------------------------------------------

   --  One cell's trimmed text and the Scan.Cell_Separator that closes it
   --  (No_Position when the line ends first).  A separator after an odd
   --  run of Scan.Escape_Mark is text; the escape marks stay in the cell
   --  as written.
   type Cell is record
      Text : Span;
      Stop : Line_Length := No_Position;
   end record;

   function Next_Cell
     (Line : String; From : Positive; To : Natural) return Cell
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post =>
       Next_Cell'Result.Text.First >= From
       and then Next_Cell'Result.Text.Last <= To
       and then (Next_Cell'Result.Stop = No_Position
                 or else Next_Cell'Result.Stop in From .. To);

   --  A table's cell count before its first cell is read.
   No_Cells : constant Line_Length := 0;

   type Row_Shape is record
      Terminated : Boolean := False;   --  ends with an unescaped separator
      Cells      : Line_Length := No_Cells;
   end record;

   --  Line (First .. Last) is a row whose opening separator is at First.
   function Measure_Row
     (Line : String; First : Positive; Last : Natural) return Row_Shape
   with
     Pre => Is_Line (Line) and then Last <= Line'Last and then First <= Last;

   --  S without one pair of surrounding Scan.Cell_Quote, when it has
   --  them; a lone quote becomes empty.
   function Unquoted (Line : String; S : Span) return Span
   is (if S.Last >= S.First
         and then Line (S.First) = Scan.Cell_Quote
         and then Line (S.Last) = Scan.Cell_Quote
       then (First => S.First + 1, Last => S.Last - 1)
       else S)
   with Pre => Is_Line (Line) and then Within (Line, S);

   ---------------------------------------------------------------------
   --  Header keywords.
   ---------------------------------------------------------------------

   --  Line (From .. To) up to, not including, its first
   --  Scan.Header_Colon.
   function Keyword_Of
     (Line : String; From : Positive; To : Natural) return Span
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post =>
       Keyword_Of'Result.First = From
       and then Keyword_Of'Result.Last <= To
       and then Keyword_Of'Result.Last >= From - 1;

end Fabula.Line_Parts;
