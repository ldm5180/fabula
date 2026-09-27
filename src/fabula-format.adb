with Ada.Characters.Handling;

with Fabula.Check;
with Fabula.Expand;
with Fabula.Scan;
with Fabula.Searches;

package body Fabula.Format
  with SPARK_Mode
is

   use type Ast.Cell_Handle;
   use type Ast.Doc_Handle;
   use type Ast.Doc_Line_Handle;
   use type Ast.Row_Handle;
   use type Ast.Scenario_Handle;
   use type Ast.Step_Handle;

   Quote : constant Character := '"';
   Blank : constant Character := ' ';

   --  A bounded text accumulator: Put appends what fits; once one piece
   --  does not, Ok drops and every later piece is dropped too, so a
   --  caller building a torture-case fragment never raises and never
   --  splices text around a gap. Sized for the largest piece Format
   --  ever builds (an escaped JSON field); every smaller use leaves
   --  the rest unused.
   type Builder is record
      Ok   : Boolean := True;
      Text : Texts.Bounded_Text (Limits.Max_Escaped_Text_Length);
   end record;

   procedure Put (B : in out Builder; Piece : String) is
   begin
      Texts.Append (B.Text, Piece, B.Ok);
   end Put;

   procedure Put (B : in out Builder; Ch : Character) is
   begin
      Put (B, [Ch]);
   end Put;

   function Text_Of (B : Builder) return String
   is (Texts.Value (B.Text))
   with Post => Text_Of'Result'Length <= Limits.Max_Escaped_Text_Length;

   procedure Put (J : in out Joined_Text; Piece : String) is
   begin
      Texts.Append (J.Text, Piece, J.Ok);
   end Put;

   ---------------------------------------------------------------------
   --  Status words and the bracket label.
   ---------------------------------------------------------------------

   function Status_Word (S : Results.Status) return String is
   begin
      case S is
         when Results.Passed    =>
            return "PASSED";

         when Results.Failed    =>
            return "FAILED";

         when Results.Skipped   =>
            return "SKIPPED";

         when Results.Undefined =>
            return "UNDEFINED";
      end case;
   end Status_Word;

   function Status_Name (S : Results.Status) return String
   is (Ada.Characters.Handling.To_Lower (Status_Word (S)));

   Label_Open  : constant String := "[   ";
   Label_Close : constant String := "] ";

   --  The room a status word has inside the label, padding included.
   Label_Word_Width : constant Natural :=
     Bracket_Label_Length - Label_Open'Length - Label_Close'Length;

   function Bracket_Label (S : Results.Status) return String is
      Word : constant String := Status_Word (S);
   begin
      return
        Label_Open
        & Word
        & [1 .. Label_Word_Width - Word'Length => Blank]
        & Label_Close;
   end Bracket_Label;

   ---------------------------------------------------------------------
   --  Header, step and location text.
   ---------------------------------------------------------------------

   function Header_Text (Keyword, Name : String) return String is
      B : Builder;
   begin
      Put (B, Keyword);
      Put (B, Header_Separator);
      Put (B, Name);
      return Text_Of (B);
   end Header_Text;

   function Step_Text (Keyword, Text : String) return String is
      B : Builder;
   begin
      Put (B, Keyword);
      Put (B, Step_Separator);
      Put (B, Text);
      return Text_Of (B);
   end Step_Text;

   --  A line number as the reference interpreter prints it.
   function Line_Image (Line_No : Line_Number) return String
   is (Check.Integer_Image (Integer (Line_No)));

   Location_Lead : constant String := "  ";
   Line_Mark     : constant Character := ':';

   function Location_Text (File : String; Line_No : Line_Number) return String
   is
      B : Builder;
   begin
      Put (B, Location_Lead);
      Put (B, File);
      Put (B, Line_Mark);
      Put (B, Line_Image (Line_No));
      return Text_Of (B);
   end Location_Text;

   ---------------------------------------------------------------------
   --  The document queries both reporters make.
   ---------------------------------------------------------------------

   function Scenario_Keyword
     (Doc : Ast.Document; S : Ast.Scenario_Handle) return String
   is (if S in 1 .. Ast.Scenario_Count (Doc)
       then Ast.Text (Doc, Ast.Scenario (Doc, S).Head.Keyword)
       else "");

   function Step_Keyword
     (Doc : Ast.Document; Step : Ast.Step_Handle) return String
   is (if Step in 1 .. Ast.Step_Count (Doc)
       then Scan.Spelling (Ast.Step (Doc, Step).Keyword)
       else "");

   function Header_Row_For
     (Doc      : Ast.Document;
      S        : Ast.Scenario_Handle;
      Data_Row : Ast.Examples_Row_Handle) return Ast.Examples_Row_Handle
   is (Expand.Header_Row_Of (Expand.Locate_Row (Doc, S, Data_Row)));

   ---------------------------------------------------------------------
   --  Tables.
   ---------------------------------------------------------------------

   --  A column's width before any cell widens it.
   No_Width : constant Natural := 0;

   --  The two Examples-row handles a resolution needs; both
   --  No_Examples_Row for a plain scenario's step. Bundled so a helper
   --  stays within R5's five-parameter limit once it also carries a cell
   --  or a widths array.
   type Substitution is record
      Header_Row : Ast.Examples_Row_Handle := Ast.No_Examples_Row;
      Data_Row   : Ast.Examples_Row_Handle := Ast.No_Examples_Row;
   end record;

   --  C's resolved text; "" for a stale cell (past the Document's
   --  current pool), which is never read.
   function Cell_Text
     (Doc : Ast.Document; C : Ast.Cell_Handle; Sub : Substitution)
      return String
   is (if C in 1 .. Ast.Cell_Count (Doc)
       then
         Expand.Value
           (Expand.Resolved
              (Doc, Ast.Cell (Doc, C), Sub.Header_Row, Sub.Data_Row))
       else "");

   --  Widens Widths by one cell.
   procedure Widen_Column
     (Doc    : Ast.Document;
      C      : Ast.Cell_Handle;
      Col    : Positive;
      Sub    : Substitution;
      Widths : in out Column_Widths) is
   begin
      if Col <= Limits.Max_Table_Columns then
         Widths (Col) :=
           Natural'Max (Widths (Col), Cell_Text (Doc, C, Sub)'Length);
      end if;
   end Widen_Column;

   --  Widens Widths by one row's cells; a stale Row (past the
   --  Document's current pool) is skipped, never read.
   procedure Widen_Row
     (Doc    : Ast.Document;
      Row    : Ast.Row_Handle;
      Sub    : Substitution;
      Widths : in out Column_Widths) is
   begin
      if Row not in 1 .. Ast.Table_Row_Count (Doc) then
         return;
      end if;
      declare
         Cells : constant Ast.Cell_Range := Ast.Table_Row (Doc, Row).Cells;
      begin
         for C in Cells.First .. Cells.Last loop
            Widen_Column (Doc, C, Natural (C - Cells.First) + 1, Sub, Widths);
         end loop;
      end;
   end Widen_Row;

   function Table_Widths
     (Doc        : Ast.Document;
      T          : Ast.Table_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Column_Widths
   is
      Result : Column_Widths := [others => No_Width];
   begin
      if T not in 1 .. Ast.Table_Count (Doc) then
         return Result;
      end if;
      declare
         Rows : constant Ast.Row_Range := Ast.Table (Doc, T).Rows;
         Sub  : constant Substitution := (Header_Row, Data_Row);
      begin
         for R in Rows.First .. Rows.Last loop
            Widen_Row (Doc, R, Sub, Result);
         end loop;
      end;
      return Result;
   end Table_Widths;

   --  What a cell needs to resolve and pad itself: the row it belongs
   --  to plays no part once the caller has already sliced its cells,
   --  so this bundles only the substitution row pair and the widths.
   type Cell_Context is record
      Sub    : Substitution;
      Widths : Column_Widths := [others => No_Width];
   end record;

   Row_Open   : constant String := "  |";
   Cell_Lead  : constant String := " ";
   Cell_Close : constant String := " |";

   procedure Put_Cell
     (Doc : Ast.Document;
      C   : Ast.Cell_Handle;
      Col : Positive;
      Ctx : Cell_Context;
      B   : in out Builder)
   is
      Text  : constant String := Cell_Text (Doc, C, Ctx.Sub);
      Width : constant Natural :=
        (if Col <= Limits.Max_Table_Columns
         then Ctx.Widths (Col)
         else Text'Length);
   begin
      Put (B, Cell_Lead);
      Put (B, Text);
      for I in Text'Length + 1 .. Width loop
         Put (B, Blank);
      end loop;
      Put (B, Cell_Close);
   end Put_Cell;

   procedure Put_Cells
     (Doc   : Ast.Document;
      Cells : Ast.Cell_Range;
      Ctx   : Cell_Context;
      B     : in out Builder) is
   begin
      for C in Cells.First .. Cells.Last loop
         Put_Cell (Doc, C, Natural (C - Cells.First) + 1, Ctx, B);
      end loop;
   end Put_Cells;

   function Table_Row_Text
     (Doc        : Ast.Document;
      Row        : Ast.Row_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle;
      Widths     : Column_Widths) return String
   is
      B : Builder;
   begin
      Put (B, Row_Open);
      if Row in 1 .. Ast.Table_Row_Count (Doc) then
         Put_Cells
           (Doc,
            Ast.Table_Row (Doc, Row).Cells,
            ((Header_Row, Data_Row), Widths),
            B);
      end if;
      return Text_Of (B);
   end Table_Row_Text;

   ---------------------------------------------------------------------
   --  Doc strings.
   ---------------------------------------------------------------------

   function Doc_Content_Text
     (Doc        : Ast.Document;
      L          : Ast.Doc_Line_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return String
   is (if L in 1 .. Ast.Doc_Line_Count (Doc)
       then
         Expand.Value
           (Expand.Resolved (Doc, Ast.Doc_Line (Doc, L), Header_Row, Data_Row))
       else "");

   --  What the reference interpreter joins lines with: one space.
   Join_Separator : constant String := " ";

   --  Space-joins D's resolved lines into J; a stale line (past the
   --  Document's current pool) stops the join and refuses it.
   procedure Join_Lines
     (Doc        : Ast.Document;
      Lines      : Ast.Doc_Line_Range;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle;
      J          : in out Joined_Text) is
   begin
      for L in Lines.First .. Lines.Last loop
         if L > Ast.Doc_Line_Count (Doc) then
            J.Ok := False;
            return;
         end if;
         Put (J, (if L = Lines.First then "" else Join_Separator));
         Put
           (J,
            Expand.Value
              (Expand.Resolved
                 (Doc, Ast.Doc_Line (Doc, L), Header_Row, Data_Row)));
      end loop;
   end Join_Lines;

   function Doc_String_Content
     (Doc        : Ast.Document;
      D          : Ast.Doc_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Joined_Text
   is
      Result : Joined_Text := (Ok => True, others => <>);
   begin
      if D not in 1 .. Ast.Doc_String_Count (Doc) then
         return (Ok => False, others => <>);
      end if;
      Join_Lines
        (Doc, Ast.Doc_String (Doc, D).Lines, Header_Row, Data_Row, Result);
      return Result;
   end Doc_String_Content;

   function Description_Content
     (Doc : Ast.Document; S : Ast.Slice) return Joined_Text
   is
      Raw    : constant String := Ast.Text (Doc, S);
      Result : Joined_Text := (Ok => True, others => <>);
      Start  : Natural := Raw'First;
   begin
      for I in Raw'Range loop
         pragma Loop_Invariant (Start in Raw'First .. I + 1);
         if Raw (I) = ASCII.LF then
            Put (Result, Raw (Start .. I - 1));
            Put (Result, Join_Separator);
            Start := I + 1;
         end if;
      end loop;
      Put (Result, Raw (Start .. Raw'Last));
      return Result;
   end Description_Content;

   ---------------------------------------------------------------------
   --  Count summaries.
   ---------------------------------------------------------------------

   --  The categories each summary prints, in the reference interpreter's
   --  order.
   type Status_Order is array (Positive range <>) of Results.Status;

   Scenario_Categories : constant Status_Order :=
     [Results.Failed, Results.Skipped, Results.Passed];
   Step_Categories     : constant Status_Order :=
     [Results.Failed, Results.Undefined, Results.Skipped, Results.Passed];

   --  One thing counted takes the singular noun; any other count the
   --  plural.
   Singular_Count : constant Natural := 1;

   Scenario_Noun      : constant String := " Scenario";
   Scenarios_Noun     : constant String := " Scenarios";
   Step_Noun          : constant String := " Step";
   Steps_Noun         : constant String := " Steps";
   Categories_Open    : constant String := " (";
   Categories_Close   : constant String := ")";
   Category_Separator : constant String := ", ";
   Count_Separator    : constant String := " ";

   --  Appends "<n> <label>" to B, with a leading ", " once a prior
   --  category has already printed; Count = 0 prints nothing. Seen
   --  reports forward to the next category in the same summary.
   procedure Put_Category
     (Count : Natural;
      Label : String;
      Seen  : in out Boolean;
      B     : in out Builder) is
   begin
      if Results.Counted (Count) then
         Put (B, (if Seen then Category_Separator else ""));
         Put (B, Check.Integer_Image (Count));
         Put (B, Count_Separator);
         Put (B, Label);
         Seen := True;
      end if;
   end Put_Category;

   --  "<total><noun> (<category>, ...)", the noun Singular for a total
   --  of one and Plural otherwise.
   function Summary
     (Counts   : Results.Status_Counts;
      Singular : String;
      Plural   : String;
      Order    : Status_Order) return String
   is
      Total : constant Natural := Results.Total (Counts);
      B     : Builder;
      Seen  : Boolean := False;
   begin
      Put (B, Check.Integer_Image (Total));
      Put (B, (if Total > Singular_Count then Plural else Singular));
      Put (B, Categories_Open);
      for S of Order loop
         Put_Category (Counts (S), Status_Name (S), Seen, B);
      end loop;
      Put (B, Categories_Close);
      return Text_Of (B);
   end Summary;

   function Scenarios_Summary (C : Results.Counts) return String
   is (Summary
         (C.Scenarios, Scenario_Noun, Scenarios_Noun, Scenario_Categories));

   function Steps_Summary (C : Results.Counts) return String
   is (Summary (C.Steps, Step_Noun, Steps_Noun, Step_Categories));

   ---------------------------------------------------------------------
   --  The failed-scenarios store.
   ---------------------------------------------------------------------

   procedure Add_Failed
     (Store   : in out Failed_Store;
      Name    : String;
      File    : String;
      Line_No : Line_Number) is
   begin
      if Store.Count = Limits.Max_Failed_Scenarios then
         return;
      end if;
      Store.Count := Store.Count + 1;
      Store.Items (Store.Count) :=
        (Name => Texts.Truncated (Name, Limits.Max_Name_Length),
         File => Texts.Truncated (File, Limits.Max_Path_Length),
         Line => Line_No);
   end Add_Failed;

   function Failed_Name (Store : Failed_Store; I : Positive) return String
   is (Texts.Value (Store.Items (I).Name));

   function Failed_File (Store : Failed_Store; I : Positive) return String
   is (Texts.Value (Store.Items (I).File));

   function Failed_Line (Store : Failed_Store; I : Positive) return Line_Number
   is (Store.Items (I).Line);

   ---------------------------------------------------------------------
   --  -v's non-hook lines.
   ---------------------------------------------------------------------

   Scenario_Start_Lead : constant String := "[   VERBOSE   ] Scenario Start '";
   Scenario_File_Lead  : constant String := "' - File: ";

   function Verbose_Scenario_Start
     (Name : String; File : String; Line_No : Line_Number) return String
   is
      B : Builder;
   begin
      Put (B, Scenario_Start_Lead);
      Put (B, Name);
      Put (B, Scenario_File_Lead);
      Put (B, File);
      Put (B, Line_Mark);
      Put (B, Line_Image (Line_No));
      return Text_Of (B);
   end Verbose_Scenario_Start;

   Tags_Lead        : constant String := "[   VERBOSE   ] Scenario tags '";
   Tags_Close       : constant String := "'";
   Expression_Lead  : constant String :=
     "                checked against tag expression '";
   Expression_Close : constant String := "' -> ";
   Tags_Passed      : constant String := "'True', continuing with scenario";
   Tags_Failed      : constant String := "'False', stopping scenario";

   function Verbose_Tag_Check
     (Tags : String; Expression : String; Passed : Boolean) return String
   is
      B : Builder;
   begin
      Put (B, Tags_Lead);
      Put (B, Tags);
      Put (B, Tags_Close);
      Put (B, ASCII.LF);
      Put (B, Expression_Lead);
      Put (B, Expression);
      Put (B, Expression_Close);
      Put (B, (if Passed then Tags_Passed else Tags_Failed));
      return Text_Of (B);
   end Verbose_Tag_Check;

   ---------------------------------------------------------------------
   --  Parse errors.
   ---------------------------------------------------------------------

   function Parse_Message (Kind : Parse.Error_Kind) return String is
   begin
      case Kind is
         when Parse.None                    =>
            return "";

         when Parse.Expected_Feature        =>
            return "Expect FeatureLine";

         when Parse.Expected_Scenario       =>
            return "Expect Tags, Scenario or Scenario Outline";

         when Parse.Expected_Examples_Table =>
            return "Expect an Examples table";

         when Parse.Unterminated_Doc_String =>
            return "Unterminated doc string.";

         when Parse.Ragged_Table            =>
            return "Different row lengths in data table";

         when Parse.Unterminated_Table_Row  =>
            return "Expect '|' after value in data table";

         when Parse.Tag_Line_Malformed      =>
            return "Expect Tags, Scenario or Scenario Outline";

         when Parse.Pool_Exhausted          =>
            return "Capacity exhausted";
      end case;
   end Parse_Message;

   function First_Token (Text : String) return String is
      function Is_Word_Char (I : Positive) return Boolean
      is (I in Text'Range and then Text (I) not in Space_Or_Tab);

      function Is_Blank_Char (I : Positive) return Boolean
      is (I in Text'Range and then Text (I) in Space_Or_Tab);

      function First_Word_Char is new Searches.Find_First (Is_Word_Char);
      function First_Blank_Char is new Searches.Find_First (Is_Blank_Char);

      --  An empty Text may have any bounds; a search from Positive'First
      --  finds nothing in it all the same.
      Start : constant Natural :=
        First_Word_Char (Integer'Max (Text'First, Positive'First), Text'Last);
   begin
      if Start = Searches.Not_Found then
         return "";
      end if;
      return
        (declare
           Stop : constant Natural := First_Blank_Char (Start, Text'Last);
         begin
           Text
             (Start
              .. (if Stop = Searches.Not_Found then Text'Last else Stop - 1)));
   end First_Token;

   --  One pass, one flag: In_Tag is True while stepping through a "@..."
   --  run already seen to start with '@'. A blank always clears it (a
   --  tag token cannot contain one); the first character that starts
   --  neither a blank run nor a tag is the answer.
   function First_Bad_Tag_Token (Text : String) return String is
      In_Tag : Boolean := False;
   begin
      for I in Text'Range loop
         if Text (I) in Space_Or_Tab then
            In_Tag := False;
         elsif In_Tag then
            null;
         elsif Text (I) = Scan.Tag_Mark then
            In_Tag := True;
         else
            return First_Token (Text (I .. Text'Last));
         end if;
      end loop;
      return "";
   end First_Bad_Tag_Token;

   --  True for the two kinds the oracle's scanner (not its parser)
   --  raises: no offending token, the "Error : <message>" shape.
   function No_Token_Kind (Kind : Parse.Error_Kind) return Boolean
   is (Kind = Parse.Unterminated_Doc_String
       or else Kind = Parse.Pool_Exhausted);

   Error_Word    : constant String := ": Error";
   No_Token_Lead : constant String := " : ";
   At_End_Lead   : constant String := " at end: ";
   Token_Lead    : constant String := " at '";
   Token_Close   : constant String := "': ";

   --  The part of a parse-error line between "Error" and the message.
   procedure Put_Error_Place
     (B      : in out Builder;
      Kind   : Parse.Error_Kind;
      At_End : Boolean;
      Token  : String)
   with Pre => Token'Length <= Limits.Max_Line_Length
   is
   begin
      if No_Token_Kind (Kind) then
         Put (B, No_Token_Lead);
      elsif At_End then
         Put (B, At_End_Lead);
      else
         Put (B, Token_Lead);
         Put
           (B,
            (if Kind = Parse.Tag_Line_Malformed
             then First_Bad_Tag_Token (Token)
             else First_Token (Token)));
         Put (B, Token_Close);
      end if;
   end Put_Error_Place;

   function Parse_Error_Text
     (File    : String;
      Line_No : Line_Number;
      Kind    : Parse.Error_Kind;
      At_End  : Boolean;
      Token   : String) return String
   is
      B : Builder;
   begin
      Put (B, File);
      Put (B, Line_Mark);
      Put (B, Line_Image (Line_No));
      Put (B, Error_Word);
      Put_Error_Place (B, Kind, At_End, Token);
      Put (B, Parse_Message (Kind));
      return Text_Of (B);
   end Parse_Error_Text;

   ---------------------------------------------------------------------
   --  JSON.
   ---------------------------------------------------------------------

   --  The escape of each character JSON names by a letter, and the
   --  mark that opens every escape; No_Escape for every other one.
   Escape_Mark : constant Character := '\';
   No_Escape   : constant Character := ASCII.NUL;

   Named_Escapes : constant array (Character) of Character :=
     [Quote       => Quote,
      Escape_Mark => Escape_Mark,
      ASCII.LF    => 'n',
      ASCII.CR    => 'r',
      ASCII.HT    => 't',
      ASCII.BS    => 'b',
      ASCII.FF    => 'f',
      others      => No_Escape];

   --  The characters below the blank, which JSON writes as "\u00XX".
   subtype Control_Character is Character range ASCII.NUL .. ASCII.US;

   Unicode_Lead : constant String := "\u00";
   Hex_Digits   : constant String := "0123456789abcdef";
   Hex_Radix    : constant := 16;

   subtype Hex_Value is Natural range 0 .. Hex_Radix - 1;

   function Hex_Digit (N : Hex_Value) return Character
   is (Hex_Digits (Hex_Digits'First + N));

   function Unicode_Escape (Ch : Control_Character) return String
   is (Unicode_Lead
       & Hex_Digit (Character'Pos (Ch) / Hex_Radix)
       & Hex_Digit (Character'Pos (Ch) mod Hex_Radix));

   procedure Escape_Char (Ch : Character; B : in out Builder) is
   begin
      if Named_Escapes (Ch) /= No_Escape then
         Put (B, [Escape_Mark, Named_Escapes (Ch)]);
      elsif Ch in Control_Character then
         Put (B, Unicode_Escape (Ch));
      else
         Put (B, Ch);
      end if;
   end Escape_Char;

   function Escape_Json (Source : String) return String is
      B : Builder;
   begin
      for Ch of Source loop
         Escape_Char (Ch, B);
      end loop;
      return Text_Of (B);
   end Escape_Json;

   Occurrence_Open  : constant Character := '(';
   Occurrence_Close : constant String := ") ";
   Id_Separator     : constant Character := ';';

   --  "(N) " for an outline's concrete scenario; nothing for a plain one.
   procedure Put_Occurrence (B : in out Builder; Occurrence : Natural) is
   begin
      if Occurrence /= No_Occurrence then
         Put (B, Occurrence_Open);
         Put (B, Check.Integer_Image (Occurrence));
         Put (B, Occurrence_Close);
      end if;
   end Put_Occurrence;

   --  "<Rule_Name>;" under a Rule; nothing outside one.
   procedure Put_Rule (B : in out Builder; Rule_Name : String) is
   begin
      if Rule_Name'Length /= 0 then
         Put (B, Rule_Name);
         Put (B, Id_Separator);
      end if;
   end Put_Rule;

   function Scenario_Id
     (Feature_Name  : String;
      Rule_Name     : String;
      Scenario_Name : String;
      Occurrence    : Natural) return String
   is
      B : Builder;
   begin
      Put_Occurrence (B, Occurrence);
      Put (B, Feature_Name);
      Put (B, Id_Separator);
      Put_Rule (B, Rule_Name);
      Put (B, Scenario_Name);
      return Text_Of (B);
   end Scenario_Id;

   Key_Close        : constant String := ": ";
   Named_Array_Open : constant String := ": [";
   Named_Open       : constant String := ": {";
   Empty_Array      : constant String := ": []";

   function Indent (Depth : Depth_Value) return String
   is ([1 .. Indent_Per_Depth * Depth => Blank])
   with Post => Indent'Result'Length = Indent_Per_Depth * Depth;

   --  The comma a field or an item ends with when a sibling follows.
   function Comma (More : Boolean) return String
   is (if More then Element_Separator else "");

   function Open_Object (Depth : Depth_Value) return String
   is (Indent (Depth) & Object_Open);

   function Open_Named_Object (Key : String; Depth : Depth_Value) return String
   is (Indent (Depth) & Quote & Key & Quote & Named_Open);

   function Close_Object (Depth : Depth_Value; More : Boolean) return String
   is (Indent (Depth) & (if More then Object_Close_More else Object_Close));

   function Open_Array (Key : String; Depth : Depth_Value) return String
   is (Indent (Depth) & Quote & Key & Quote & Named_Array_Open);

   function Close_Array (Depth : Depth_Value; More : Boolean) return String
   is (Indent (Depth) & (if More then Array_Close_More else Array_Close));

   function Empty_Array_Field
     (Key : String; Depth : Depth_Value; More : Boolean) return String
   is (Indent (Depth) & Quote & Key & Quote & Empty_Array & Comma (More));

   function String_Field
     (Key, Escaped_Value : String; Depth : Depth_Value; More : Boolean)
      return String
   is (Indent (Depth)
       & Quote
       & Key
       & Quote
       & Key_Close
       & Quote
       & Escaped_Value
       & Quote
       & Comma (More));

   function String_Item
     (Escaped_Value : String; Depth : Depth_Value; More : Boolean)
      return String
   is (Indent (Depth) & Quote & Escaped_Value & Quote & Comma (More));

   function Number_Field
     (Key : String; Value : Natural; Depth : Depth_Value; More : Boolean)
      return String
   is
      B : Builder;
   begin
      Put (B, Indent (Depth));
      Put (B, Quote);
      Put (B, Key);
      Put (B, Quote);
      Put (B, Key_Close);
      Put (B, Check.Integer_Image (Value));
      Put (B, Comma (More));
      return Text_Of (B);
   end Number_Field;

end Fabula.Format;
