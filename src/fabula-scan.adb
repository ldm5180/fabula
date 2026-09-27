with Fabula.Line_Parts;
with Fabula.Searches;

package body Fabula.Scan
  with SPARK_Mode
is

   Max_Keyword_Length : constant := 18;
   --  Longest fixed spelling: "Scenario Template:".

   function Spelling (K : Step_Keyword) return String is
   begin
      case K is
         when K_Given =>
            return "Given";

         when K_When  =>
            return "When";

         when K_Then  =>
            return "Then";

         when K_And   =>
            return "And";

         when K_But   =>
            return "But";

         when K_Star  =>
            return "*";
      end case;
   end Spelling;

   subtype Header_Class is Line_Class range Feature_Header .. Examples_Header;
   --  The six header classes are contiguous in Line_Class, so a value
   --  of this subtype always fits the one Classification variant they
   --  share; that lets Make_Header build the aggregate from a value
   --  the table only fixes at run time.

   subtype Header_Or_Step is Line_Class range Feature_Header .. Step_Line;
   --  Every Keyword_Table row is a header keyword or a step keyword,
   --  and Step_Line is the literal right after Examples_Header, so
   --  this contiguous range is exactly that set.  Typing the table's
   --  Class field with it, instead of the full Line_Class, is what
   --  lets a row that is not Step_Line prove it is a Header_Class.

   subtype Body_Class is Line_Class
   with Static_Predicate => Body_Class in Tag_Line | Table_Row | Description;
   --  The classes a line's first character decides, whose payload is
   --  the whole trimmed body.  They share one Classification variant,
   --  so Body_Line builds the aggregate from a value fixed at run time.

   function Make_Header
     (Class  : Header_Class;
      Indent : Line_Length;
      First  : Column;
      Last   : Line_Length) return Classification
   is (Class       => Class,
       Indent      => Indent,
       Title_First => First,
       Title_Last  => Last);

   type Keyword_Row is record
      Text        : String (1 .. Max_Keyword_Length);
      Text_Length : Positive range 1 .. Max_Keyword_Length;
      Class       : Header_Or_Step;
      Keyword     : Step_Keyword;
      --  Keyword matters only when Class = Step_Line; a header row
      --  carries K_Star as a don't-care filler.
   end record;

   --  Oracle keyword spellings (cwt-cucumber), matched by prefix in
   --  this order.  Every text is padded to one fixed width so the
   --  rows form one array; Text_Length is the real spelling length.
   --!format off
   Keyword_Table : constant array (Positive range <>) of Keyword_Row :=
      [(Text => "Feature:" & [1 .. 10 => ' '],
        Text_Length =>  8, Class => Feature_Header,    Keyword => K_Star),
       (Text => "Scenario:" & [1 ..  9 => ' '],
        Text_Length =>  9, Class => Scenario_Header,   Keyword => K_Star),
       (Text => "Example:" & [1 .. 10 => ' '],
        Text_Length =>  8, Class => Scenario_Header,   Keyword => K_Star),
       (Text => "Scenario Outline:" & [1 ..  1 => ' '],
        Text_Length => 17, Class => Outline_Header,    Keyword => K_Star),
       (Text => "Scenario Template:",
        Text_Length => 18, Class => Outline_Header,    Keyword => K_Star),
       (Text => "Rule:" & [1 .. 13 => ' '],
        Text_Length =>  5, Class => Rule_Header,       Keyword => K_Star),
       (Text => "Background:" & [1 ..  7 => ' '],
        Text_Length => 11, Class => Background_Header, Keyword => K_Star),
       (Text => "Examples:" & [1 ..  9 => ' '],
        Text_Length =>  9, Class => Examples_Header,   Keyword => K_Star),
       (Text => "Scenarios:" & [1 ..  8 => ' '],
        Text_Length => 10, Class => Examples_Header,   Keyword => K_Star),
       (Text => "Given" & [1 .. 13 => ' '],
        Text_Length =>  5, Class => Step_Line,         Keyword => K_Given),
       (Text => "When" & [1 .. 14 => ' '],
        Text_Length =>  4, Class => Step_Line,         Keyword => K_When),
       (Text => "Then" & [1 .. 14 => ' '],
        Text_Length =>  4, Class => Step_Line,         Keyword => K_Then),
       (Text => "And" & [1 .. 15 => ' '],
        Text_Length =>  3, Class => Step_Line,         Keyword => K_And),
       (Text => "But" & [1 .. 15 => ' '],
        Text_Length =>  3, Class => Step_Line,         Keyword => K_But)];
   --!format on

   --  The scanner trims Space_Tab_Or_Return, not the full White_Space
   --  set: a trailing carriage return counts, so CRLF input trims the
   --  same as LF input, as the reference lexer does.

   --  Line is a line the scanner may read.
   function Is_Line (Line : String) return Boolean
   is (Line'First = First_Column
       and then Line'Length <= Limits.Max_Line_Length);

   function Starts_With
     (Line : String; From : Positive; Prefix : String) return Boolean
   is (From + Prefix'Length - 1 <= Line'Last
       and then Line (From .. From + Prefix'Length - 1) = Prefix)
   with
     Pre =>
       Is_Line (Line)
       and then From >= Line'First
       and then From <= Line'Last + 1
       and then Prefix'Length <= Max_Keyword_Length;
   --  cwt matches by `starts_with`, not by a word boundary, so a
   --  keyword run straight into the following text (`Givenx`) still
   --  matches; the oracle-cited test covers the resulting slice.

   function Skip_Leading_Whitespace
     (Line : String; From : Positive; Upto : Natural) return Positive
   with
     Pre  =>
       Is_Line (Line)
       and then From >= Line'First
       and then Upto <= Line'Last
       and then From <= Upto + 1,
     Post =>
       Skip_Leading_Whitespace'Result >= From
       and then Skip_Leading_Whitespace'Result <= Upto + 1
   is
      I : Positive := From;
   begin
      while I <= Upto and then Line (I) in Space_Tab_Or_Return loop
         pragma Loop_Invariant (I in From .. Upto + 1);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I;
   end Skip_Leading_Whitespace;

   function Find_First_Non_Whitespace (Line : String) return Natural
   with
     Post =>
       Find_First_Non_Whitespace'Result = Line_Parts.No_Position
       or else Find_First_Non_Whitespace'Result in Line'Range
   is
      function Is_Content (I : Positive) return Boolean
      is (I in Line'Range and then Line (I) not in Space_Tab_Or_Return);

      function First_Content is new Searches.Find_First (Is_Content);
   begin
      if Line'Length = 0 then
         return Line_Parts.No_Position;
      end if;
      return First_Content (Line'First, Line'Last);
   end Find_First_Non_Whitespace;

   function Find_Content_End
     (Line : String; First_Non_WS : Positive) return Natural
   with
     Pre  => First_Non_WS in Line'Range,
     Post =>
       Find_Content_End'Result in First_Non_WS .. Line'Last
       and then (for all J in Line'Range =>
                   (if J > Find_Content_End'Result
                    then Line (J) in Space_Tab_Or_Return))
   is
      Last : Natural := Line'Last;
   begin
      while Last >= First_Non_WS and then Line (Last) in Space_Tab_Or_Return
      loop
         pragma Loop_Invariant (Last in First_Non_WS - 1 .. Line'Last);
         pragma
           Loop_Invariant
             (for all J in Last .. Line'Last =>
                Line (J) in Space_Tab_Or_Return);
         pragma Loop_Variant (Decreases => Last);
         Last := Last - 1;
      end loop;
      --  Last can walk down to First_Non_WS - 1 only when every
      --  character back to First_Non_WS is whitespace; clamping keeps
      --  every downstream slice end no earlier than its own start
      --  without reasoning about which characters were found.
      return Natural'Max (Last, First_Non_WS);
   end Find_Content_End;

   --  Holds one line's first non-whitespace column, its indent (the
   --  count of blanks before that column) and its trimmed content end,
   --  the values every matcher below needs.
   type Scan_Context is record
      First_Non_WS : Column;
      Indent       : Line_Length;
      Content_End  : Line_Length;
   end record;

   --  Only whitespace follows Content_End, so any character that is not
   --  whitespace sits at or before it.
   function Context_Valid (Line : String; Ctx : Scan_Context) return Boolean
   is (Is_Line (Line)
       and then Ctx.First_Non_WS in Line'Range
       and then Ctx.Indent = Ctx.First_Non_WS - Line'First
       and then Ctx.Content_End in Ctx.First_Non_WS .. Line'Last
       and then (for all J in Ctx.Content_End + 1 .. Line'Last =>
                   Line (J) in Space_Tab_Or_Return));

   function Context_Of
     (Line : String; First_Non_WS : Positive) return Scan_Context
   is ((First_Non_WS => First_Non_WS,
        Indent       => First_Non_WS - Line'First,
        Content_End  => Find_Content_End (Line, First_Non_WS)))
   with
     Pre  => Is_Line (Line) and then First_Non_WS in Line'Range,
     Post => Context_Valid (Line, Context_Of'Result);

   --  C fits the classified Line, and a table row starts at its '|'.
   function Fits_Line (Line : String; C : Classification) return Boolean
   is (Slices_Fit (C, Line'Length)
       and then (if C.Class = Table_Row
                 then Line (C.Body_First) = Cell_Separator))
   with Pre => Is_Line (Line);

   --  A matcher's answer: the line's classification when its rule takes
   --  the line, nothing when it does not.
   type Rule_Match (Found : Boolean := False) is record
      case Found is
         when True =>
            Class : Classification;

         when False =>
            null;
      end case;
   end record;

   No_Match : constant Rule_Match := (Found => False);

   --  The first of two answers that found something: Match's class, or
   --  Otherwise.
   function Found_Or
     (Match : Rule_Match; Otherwise : Classification) return Classification
   is (if Match.Found then Match.Class else Otherwise);

   --  A keyword row's classification: a step that carries the row's
   --  keyword, or the row's header, with payload First .. Last.
   function Row_Classification
     (Row    : Keyword_Row;
      Indent : Line_Length;
      First  : Column;
      Last   : Line_Length) return Classification
   is (if Row.Class = Step_Line
       then
         (Class      => Step_Line,
          Indent     => Indent,
          Keyword    => Row.Keyword,
          Text_First => First,
          Text_Last  => Last)
       else Make_Header (Row.Class, Indent, First, Last));

   function Try_Keyword_Row
     (Line : String; Ctx : Scan_Context; Row : Keyword_Row) return Rule_Match
   with
     Pre  => Context_Valid (Line, Ctx),
     Post =>
       (if Try_Keyword_Row'Result.Found
        then Fits_Line (Line, Try_Keyword_Row'Result.Class))
   is
      Match_End  : constant Positive := Ctx.First_Non_WS + Row.Text_Length - 1;
      Slice_Last : constant Natural :=
        Natural'Max (Ctx.Content_End, Match_End);
   begin
      if not Starts_With
               (Line, Ctx.First_Non_WS, Row.Text (1 .. Row.Text_Length))
      then
         return No_Match;
      end if;
      return
        (Found => True,
         Class =>
           Row_Classification
             (Row    => Row,
              Indent => Ctx.Indent,
              First  =>
                Skip_Leading_Whitespace (Line, Match_End + 1, Slice_Last),
              Last   => Slice_Last));
   end Try_Keyword_Row;

   function Match_Keyword_Table
     (Line : String; Ctx : Scan_Context) return Rule_Match
   with
     Pre  => Context_Valid (Line, Ctx),
     Post =>
       (if Match_Keyword_Table'Result.Found
        then Fits_Line (Line, Match_Keyword_Table'Result.Class))
   is
   begin
      for Row of Keyword_Table loop
         declare
            Match : constant Rule_Match := Try_Keyword_Row (Line, Ctx, Row);
         begin
            if Match.Found then
               return Match;
            end if;
         end;
      end loop;
      return No_Match;
   end Match_Keyword_Table;

   --  A Step_Bullet is a step by prefix alone, like the word keywords:
   --  `*bare` with no gap is a step whose text is `bare`, matching the
   --  oracle's starts_with rule.
   function Match_Star_Step
     (Line : String; Ctx : Scan_Context) return Rule_Match
   is (if Line (Ctx.First_Non_WS) = Step_Bullet
       then
         (Found => True,
          Class =>
            (Class      => Step_Line,
             Indent     => Ctx.Indent,
             Keyword    => K_Star,
             Text_First =>
               Skip_Leading_Whitespace
                 (Line, Ctx.First_Non_WS + 1, Ctx.Content_End),
             Text_Last  => Ctx.Content_End))
       else No_Match)
   with
     Pre  => Context_Valid (Line, Ctx),
     Post =>
       (if Match_Star_Step'Result.Found
        then Fits_Line (Line, Match_Star_Step'Result.Class));

   function Fence_Of (Mark : Character) return Fence_Kind
   is (if Mark = Quote_Fence then Quotes else Backticks);

   --  cwt's doc_string_type_from_token right-trims the whole line, then
   --  takes substr(3): the content type keeps any leading whitespace
   --  after the fence and loses only the trailing (`""" json` gives
   --  ` json`, not `json`).
   function Try_Doc_Fence (Line : String; Ctx : Scan_Context) return Rule_Match
   is (if Line_Parts.Fence_At (Line, Ctx.First_Non_WS)
       then
         (Found => True,
          Class =>
            (Class      => Doc_Fence,
             Indent     => Ctx.Indent,
             Fence      => Fence_Of (Line (Ctx.First_Non_WS)),
             Type_First => Ctx.First_Non_WS + Fence_Length,
             Type_Last  => Ctx.Content_End))
       else No_Match)
   with
     Pre  => Context_Valid (Line, Ctx),
     Post =>
       (if Try_Doc_Fence'Result.Found
        then Fits_Line (Line, Try_Doc_Fence'Result.Class));

   --  A line its first character classes: the payload is its whole
   --  trimmed body.
   function Body_Line
     (Class : Body_Class; Ctx : Scan_Context) return Classification
   is (Class      => Class,
       Indent     => Ctx.Indent,
       Body_First => Ctx.First_Non_WS,
       Body_Last  => Ctx.Content_End);

   function Classify_By_First_Char
     (Line : String; Ctx : Scan_Context) return Classification
   with
     Pre  => Context_Valid (Line, Ctx),
     Post => Fits_Line (Line, Classify_By_First_Char'Result)
   is
   begin
      case Line (Ctx.First_Non_WS) is
         when Tag_Mark                     =>
            return Body_Line (Tag_Line, Ctx);

         when Cell_Separator               =>
            return Body_Line (Table_Row, Ctx);

         when Comment_Mark                 =>
            return (Class => Comment, Indent => Ctx.Indent);

         when Quote_Fence | Backtick_Fence =>
            return
              Found_Or
                (Try_Doc_Fence (Line, Ctx), Body_Line (Description, Ctx));

         when others                       =>
            return Body_Line (Description, Ctx);
      end case;
   end Classify_By_First_Char;

   --  First match wins: a keyword row, then a step bullet, then the
   --  line's first character.
   function Classify_Text
     (Line : String; Ctx : Scan_Context) return Classification
   is (Found_Or
         (Match_Keyword_Table (Line, Ctx),
          Found_Or
            (Match_Star_Step (Line, Ctx), Classify_By_First_Char (Line, Ctx))))
   with
     Pre  => Context_Valid (Line, Ctx),
     Post => Fits_Line (Line, Classify_Text'Result);

   function Classify (Line : String) return Classification is
      First_Non_WS : constant Natural := Find_First_Non_Whitespace (Line);
   begin
      if First_Non_WS = Line_Parts.No_Position then
         return (Class => Blank, Indent => Flush_Left);
      end if;
      return Classify_Text (Line, Context_Of (Line, First_Non_WS));
   end Classify;

end Fabula.Scan;
