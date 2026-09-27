with Fabula.Line_Parts;

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

   function Make_Header
     (Class : Header_Class; Indent : Length; First : Positive; Last : Natural)
      return Classification
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

   function Is_Whitespace (Ch : Character) return Boolean
   is (Ch = ' ' or else Ch = ASCII.HT or else Ch = ASCII.CR);
   --  A trailing carriage return counts as whitespace, so CRLF input
   --  trims the same as LF input.

   function Starts_With
     (Line : String; From : Positive; Prefix : String) return Boolean
   is (From + Prefix'Length - 1 <= Line'Last
       and then Line (From .. From + Prefix'Length - 1) = Prefix)
   with
     Pre =>
       Line'First = 1
       and then Line'Length <= Limits.Max_Line_Length
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
       Line'First = 1
       and then Line'Length <= Limits.Max_Line_Length
       and then From >= Line'First
       and then Upto <= Line'Last
       and then From <= Upto + 1,
     Post =>
       Skip_Leading_Whitespace'Result >= From
       and then Skip_Leading_Whitespace'Result <= Upto + 1
   is
      I : Positive := From;
   begin
      while I <= Upto and then Is_Whitespace (Line (I)) loop
         pragma Loop_Invariant (I in From .. Upto + 1);
         pragma Loop_Variant (Increases => I);
         I := I + 1;
      end loop;
      return I;
   end Skip_Leading_Whitespace;

   function Find_First_Non_Whitespace (Line : String) return Natural
   with
     Post =>
       Find_First_Non_Whitespace'Result = 0
       or else Find_First_Non_Whitespace'Result in Line'Range
   is
   begin
      for I in Line'Range loop
         pragma
           Loop_Invariant
             (for all J in Line'First .. I - 1 => Is_Whitespace (Line (J)));
         if not Is_Whitespace (Line (I)) then
            return I;
         end if;
      end loop;
      return 0;
   end Find_First_Non_Whitespace;

   function Find_Content_End
     (Line : String; First_Non_WS : Positive) return Natural
   with
     Pre  => First_Non_WS in Line'Range,
     Post =>
       Find_Content_End'Result in First_Non_WS .. Line'Last
       and then (for all J in Line'Range =>
                   (if J > Find_Content_End'Result
                    then Is_Whitespace (Line (J))))
   is
      Last : Natural := Line'Last;
   begin
      while Last >= First_Non_WS and then Is_Whitespace (Line (Last)) loop
         pragma Loop_Invariant (Last in First_Non_WS - 1 .. Line'Last);
         pragma
           Loop_Invariant
             (for all J in Last .. Line'Last => Is_Whitespace (Line (J)));
         pragma Loop_Variant (Decreases => Last);
         Last := Last - 1;
      end loop;
      --  Last can walk down to First_Non_WS - 1 only when every
      --  character back to First_Non_WS is whitespace; clamping keeps
      --  every downstream slice end no earlier than its own start
      --  without reasoning about which characters were found.
      return Natural'Max (Last, First_Non_WS);
   end Find_Content_End;

   --  Holds one line's first non-whitespace index and its trimmed
   --  content end, the two values every matcher below needs.
   type Scan_Context is record
      First_Non_WS : Positive;
      Content_End  : Natural;
   end record;

   --  Only whitespace follows Content_End, so any character that is not
   --  whitespace sits at or before it.
   function Context_Valid (Line : String; Ctx : Scan_Context) return Boolean
   is (Line'First = 1
       and then Line'Length <= Limits.Max_Line_Length
       and then Ctx.First_Non_WS in Line'Range
       and then Ctx.Content_End in Ctx.First_Non_WS .. Line'Last
       and then (for all J in Ctx.Content_End + 1 .. Line'Last =>
                   Is_Whitespace (Line (J))));

   function Header_Or_Step_Slice_OK
     (Line : String; Result : Classification) return Boolean
   is ((case Result.Class is
          when Feature_Header
             | Rule_Header
             | Background_Header
             | Scenario_Header
             | Outline_Header
             | Examples_Header =>
            Result.Title_First <= Line'Last + 1
            and then Result.Title_Last <= Line'Last
            and then Result.Title_Last >= Result.Title_First - 1,
          when Step_Line       =>
            Result.Text_First <= Line'Last + 1
            and then Result.Text_Last <= Line'Last
            and then Result.Text_Last >= Result.Text_First - 1,
          when others          => False)
       and then Result.Indent <= Line'Length)
   with Pre => Line'First = 1 and then Line'Length <= Limits.Max_Line_Length;
   --  Shared by every matcher that can only ever produce a header or a
   --  step, so Classify's own postcondition composes from one place.

   procedure Try_Keyword_Row
     (Line   : String;
      Ctx    : Scan_Context;
      Row    : Keyword_Row;
      Found  : out Boolean;
      Result : out Classification)
   with
     Pre  => Context_Valid (Line, Ctx) and then not Result'Constrained,
     Post => (if Found then Header_Or_Step_Slice_OK (Line, Result))
   is
      Indent : constant Length := Ctx.First_Non_WS - Line'First;
   begin
      Found := False;
      Result := (Class => Blank, Indent => 0);
      if not Starts_With
               (Line, Ctx.First_Non_WS, Row.Text (1 .. Row.Text_Length))
      then
         return;
      end if;

      declare
         Match_End   : constant Positive :=
           Ctx.First_Non_WS + Row.Text_Length - 1;
         Slice_Last  : constant Natural :=
           Natural'Max (Ctx.Content_End, Match_End);
         Slice_First : constant Positive :=
           Skip_Leading_Whitespace (Line, Match_End + 1, Slice_Last);
      begin
         if Row.Class = Step_Line then
            Result :=
              (Class      => Step_Line,
               Indent     => Indent,
               Keyword    => Row.Keyword,
               Text_First => Slice_First,
               Text_Last  => Slice_Last);
         else
            Result := Make_Header (Row.Class, Indent, Slice_First, Slice_Last);
         end if;
      end;
      Found := True;
   end Try_Keyword_Row;

   procedure Match_Keyword_Table
     (Line   : String;
      Ctx    : Scan_Context;
      Found  : out Boolean;
      Result : out Classification)
   with
     Pre  => Context_Valid (Line, Ctx) and then not Result'Constrained,
     Post => (if Found then Header_Or_Step_Slice_OK (Line, Result))
   is
   begin
      Found := False;
      Result := (Class => Blank, Indent => 0);
      for Row_Index in Keyword_Table'Range loop
         Try_Keyword_Row (Line, Ctx, Keyword_Table (Row_Index), Found, Result);
         if Found then
            return;
         end if;
      end loop;
   end Match_Keyword_Table;

   procedure Match_Star_Step
     (Line   : String;
      Ctx    : Scan_Context;
      Found  : out Boolean;
      Result : out Classification)
   with
     Pre  => Context_Valid (Line, Ctx) and then not Result'Constrained,
     Post =>
       (if Found
        then
          Result.Class = Step_Line
          and then Header_Or_Step_Slice_OK (Line, Result))
   is
      Indent : constant Length := Ctx.First_Non_WS - Line'First;
   begin
      Found := False;
      Result := (Class => Blank, Indent => 0);
      --  A `*` bullet is a step by prefix alone, like the word
      --  keywords: `*bare` with no gap is a step whose text is
      --  `bare`, matching the oracle's starts_with rule.
      if Line (Ctx.First_Non_WS) = '*' then
         declare
            Text_First : constant Positive :=
              Skip_Leading_Whitespace
                (Line, Ctx.First_Non_WS + 1, Ctx.Content_End);
         begin
            Result :=
              (Class      => Step_Line,
               Indent     => Indent,
               Keyword    => K_Star,
               Text_First => Text_First,
               Text_Last  => Ctx.Content_End);
         end;
         Found := True;
      end if;
   end Match_Star_Step;

   function Body_Slice_OK
     (Line : String; Result : Classification) return Boolean
   is ((case Result.Class is
          when Tag_Line | Description =>
            Result.Body_First <= Line'Last + 1
            and then Result.Body_Last <= Line'Last
            and then Result.Body_Last >= Result.Body_First
            and then Result.Body_First = Result.Indent + 1,
          when Table_Row              =>
            Result.Body_First <= Line'Last + 1
            and then Result.Body_Last <= Line'Last
            and then Result.Body_Last >= Result.Body_First
            and then Result.Body_First = Result.Indent + 1
            and then Line (Result.Body_First) = Cell_Separator,
          when Doc_Fence              =>
            Result.Type_First <= Line'Last + 1
            and then Result.Type_Last <= Line'Last
            and then Result.Type_Last >= Result.Type_First - 1,
          when Comment                => True,
          when others                 => False)
       and then Result.Indent <= Line'Length)
   with Pre => Line'First = 1 and then Line'Length <= Limits.Max_Line_Length;

   procedure Try_Doc_Fence
     (Line   : String;
      Ctx    : Scan_Context;
      Found  : out Boolean;
      Result : out Classification)
   with
     Pre  => Context_Valid (Line, Ctx) and then not Result'Constrained,
     Post =>
       (if Found
        then Result.Class = Doc_Fence and then Body_Slice_OK (Line, Result))
   is
      Indent : constant Length := Ctx.First_Non_WS - Line'First;
   begin
      Found := False;
      Result := (Class => Blank, Indent => 0);
      if Line_Parts.Fence_At (Line, Ctx.First_Non_WS) then
         declare
            Kind       : constant Fence_Kind :=
              (if Line (Ctx.First_Non_WS) = Quote_Fence
               then Quotes
               else Backticks);
            --  cwt's doc_string_type_from_token right-trims the whole
            --  line, then takes substr(3): the content type keeps any
            --  leading whitespace after the fence and loses only the
            --  trailing (`""" json` gives ` json`, not `json`).
            Type_First : constant Positive := Ctx.First_Non_WS + Fence_Length;
         begin
            Result :=
              (Class      => Doc_Fence,
               Indent     => Indent,
               Fence      => Kind,
               Type_First => Type_First,
               Type_Last  => Ctx.Content_End);
         end;
         Found := True;
      end if;
   end Try_Doc_Fence;

   function Classify_By_First_Char
     (Line : String; Ctx : Scan_Context) return Classification
   with
     Pre  => Context_Valid (Line, Ctx),
     Post => Body_Slice_OK (Line, Classify_By_First_Char'Result)
   is
      Indent       : constant Length := Ctx.First_Non_WS - Line'First;
      Fence_Found  : Boolean;
      Fence_Result : Classification;
   begin
      case Line (Ctx.First_Non_WS) is
         when Tag_Mark                     =>
            return
              (Class      => Tag_Line,
               Indent     => Indent,
               Body_First => Ctx.First_Non_WS,
               Body_Last  => Ctx.Content_End);

         when Cell_Separator               =>
            return
              (Class      => Table_Row,
               Indent     => Indent,
               Body_First => Ctx.First_Non_WS,
               Body_Last  => Ctx.Content_End);

         when Comment_Mark                 =>
            return (Class => Comment, Indent => Indent);

         when Quote_Fence | Backtick_Fence =>
            Try_Doc_Fence (Line, Ctx, Fence_Found, Fence_Result);
            if Fence_Found then
               return Fence_Result;
            end if;
            return
              (Class      => Description,
               Indent     => Indent,
               Body_First => Ctx.First_Non_WS,
               Body_Last  => Ctx.Content_End);

         when others                       =>
            return
              (Class      => Description,
               Indent     => Indent,
               Body_First => Ctx.First_Non_WS,
               Body_Last  => Ctx.Content_End);
      end case;
   end Classify_By_First_Char;

   function Classify (Line : String) return Classification is
      First_Non_WS : constant Natural := Find_First_Non_Whitespace (Line);
   begin
      if First_Non_WS = 0 then
         return (Class => Blank, Indent => 0);
      end if;

      declare
         Ctx    : constant Scan_Context :=
           (First_Non_WS => First_Non_WS,
            Content_End  => Find_Content_End (Line, First_Non_WS));
         Found  : Boolean;
         Result : Classification;
      begin
         Match_Keyword_Table (Line, Ctx, Found, Result);
         if Found then
            return Result;
         end if;

         Match_Star_Step (Line, Ctx, Found, Result);
         if Found then
            return Result;
         end if;

         return Classify_By_First_Char (Line, Ctx);
      end;
   end Classify;

end Fabula.Scan;
