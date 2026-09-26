--  Splits one feature-file line into the parts the parser stores: tag
--  tokens, table cells, doc-string fence runs, and trimmed text.  Each
--  rule follows the reference interpreter's lexer; the parser's guards
--  and its commands both read lines only through here.
with Fabula.Limits;

private package Fabula.Line_Parts
  with Pure, SPARK_Mode
is

   --  A span of one line; Last < First is the empty span.
   type Span is record
      First : Positive := 1;
      Last  : Natural := 0;
   end record;

   function Is_Line (Line : String) return Boolean
   is (Line'First = 1 and then Line'Length <= Limits.Max_Line_Length);

   --  S reads safely from Line: it is empty, or inside Line's range.
   function Within (Line : String; S : Span) return Boolean
   is (S.Last < S.First
       or else (S.First >= Line'First and then S.Last <= Line'Last));

   function Is_Space (Ch : Character) return Boolean
   is (Ch = ' ' or else Ch = ASCII.HT);
   --  What separates tokens on one line.

   function Is_Blank (Ch : Character) return Boolean
   is (Is_Space (Ch)
       or else Ch = ASCII.CR
       or else Ch = ASCII.LF
       or else Ch = ASCII.VT
       or else Ch = ASCII.FF);
   --  What trimming removes: C's isspace set.

   --  Line (From .. To) without its leading and trailing blanks.
   function Trimmed (Line : String; From : Positive; To : Natural) return Span
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post =>
       Trimmed'Result.First >= From
       and then Trimmed'Result.Last <= To
       and then Trimmed'Result.Last >= Trimmed'Result.First - 1;

   function Only_Blank
     (Line : String; From : Positive; To : Natural) return Boolean
   is (for all I in From .. To => Is_Blank (Line (I)))
   with Pre => Is_Line (Line) and then To <= Line'Last;

   ---------------------------------------------------------------------
   --  Doc-string fences.
   ---------------------------------------------------------------------

   --  Three equal quote or backtick characters start at I.
   function Fence_At (Line : String; I : Positive) return Boolean
   is (Line'Length >= 3
       and then I <= Line'Last - 2
       and then (Line (I) = '"' or else Line (I) = '`')
       and then Line (I + 1) = Line (I)
       and then Line (I + 2) = Line (I))
   with Pre => Is_Line (Line);

   --  The first fence run inside Line (From .. To), or 0.  The
   --  reference lexer ends a doc string at the first such run anywhere
   --  on a line, not only at one that leads it.
   function Fence_Run
     (Line : String; From : Positive; To : Natural) return Natural
   with
     Pre  => Is_Line (Line) and then To <= Line'Length,
     Post =>
       Fence_Run'Result = 0
       or else (Fence_Run'Result >= From
                and then Fence_Run'Result + 2 <= To
                and then Fence_At (Line, Fence_Run'Result));

   ---------------------------------------------------------------------
   --  Tags.
   ---------------------------------------------------------------------

   function Is_Tag_Char (Ch : Character) return Boolean
   is (Ch in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
       or else Ch in '_' | '-' | '.' | '#' | '/' | ':' | '$' | '*' | '<' | '>'
       or else Ch in ''' | '|' | '%' | '^' | '&' | '!' | '?');
   --  The characters a tag may hold after its '@'.

   --  Line (From .. To) is a run of tags: every token starts with '@'
   --  and holds only tag characters.  Tags may abut (@a@b is two).
   function Tags_Well_Formed
     (Line : String; From : Positive; To : Natural) return Boolean
   is (for all I in From .. To =>
         (Line (I) = '@'
          or else Is_Tag_Char (Line (I))
          or else Is_Space (Line (I)))
         and then (if (I = From or else Is_Space (Line (I - 1)))
                     and then not Is_Space (Line (I))
                   then Line (I) = '@'))
   with Pre => Is_Line (Line) and then From >= 1 and then To <= Line'Last;

   --  The first tag at or after From within Line (From .. To): an '@'
   --  and the tag characters after it.  Empty when none starts there.
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

   --  One cell's trimmed text and the '|' that closes it (0 when the
   --  line ends first).  A '|' after an odd run of backslashes is
   --  text; the backslashes stay in the cell as written.
   type Cell is record
      Text : Span;
      Stop : Natural := 0;
   end record;

   function Next_Cell
     (Line : String; From : Positive; To : Natural) return Cell
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post =>
       Next_Cell'Result.Text.First >= From
       and then Next_Cell'Result.Text.Last <= To
       and then (Next_Cell'Result.Stop = 0
                 or else Next_Cell'Result.Stop in From .. To);

   type Row_Shape is record
      Terminated : Boolean := False;   --  ends with an unescaped '|'
      Cells      : Natural := 0;
   end record;

   --  Line (First .. Last) is a row whose opening '|' is at First.
   function Measure_Row
     (Line : String; First : Positive; Last : Natural) return Row_Shape
   with
     Pre  => Is_Line (Line) and then Last <= Line'Last and then First <= Last,
     Post => Measure_Row'Result.Cells <= Limits.Max_Line_Length;

   --  S without one pair of surrounding double quotes, when it has
   --  them; a lone '"' becomes empty.
   function Unquoted (Line : String; S : Span) return Span
   is (if S.Last >= S.First
         and then Line (S.First) = '"'
         and then Line (S.Last) = '"'
       then (First => S.First + 1, Last => S.Last - 1)
       else S)
   with Pre => Is_Line (Line) and then Within (Line, S);

   ---------------------------------------------------------------------
   --  Header keywords.
   ---------------------------------------------------------------------

   --  Line (From .. To) up to, not including, its first ':'.
   function Keyword_Of
     (Line : String; From : Positive; To : Natural) return Span
   with
     Pre  => Is_Line (Line) and then To <= Line'Last and then From <= To + 1,
     Post =>
       Keyword_Of'Result.First = From
       and then Keyword_Of'Result.Last <= To
       and then Keyword_Of'Result.Last >= From - 1;

end Fabula.Line_Parts;
