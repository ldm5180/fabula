with Fabula.Check;
with Fabula.Expand;
with Fabula.Scan;

package body Fabula.Format
  with SPARK_Mode
is

   use type Ast.Cell_Handle;
   use type Ast.Doc_Handle;
   use type Ast.Doc_Line_Handle;
   use type Ast.Row_Handle;

   Quote : constant Character := '"';

   --  A bounded text accumulator: Put appends what fits; once one piece
   --  does not, Ok drops and every later piece is dropped too, so a
   --  caller building a torture-case fragment never raises and never
   --  splices text around a gap. Sized for the largest piece Format
   --  ever builds (an escaped JSON field); every smaller use leaves
   --  the rest unused.
   type Builder is record
      Ok  : Boolean := True;
      Buf : String (1 .. Limits.Max_Escaped_Text_Length) := [others => ' '];
      Len : Natural := 0;
   end record;

   procedure Put (B : in out Builder; Piece : String)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
   begin
      if not B.Ok then
         return;
      elsif Piece'Length <= B.Buf'Length - B.Len then
         B.Buf
           (B.Buf'First + B.Len .. B.Buf'First + B.Len + Piece'Length - 1) :=
           Piece;
         B.Len := B.Len + Piece'Length;
      else
         B.Ok := False;
      end if;
   end Put;

   procedure Put (B : in out Builder; Ch : Character)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
   begin
      Put (B, [1 => Ch]);
   end Put;

   function Text_Of (B : Builder) return String
   is (B.Buf (1 .. B.Len))
   with Pre => B.Len <= B.Buf'Length;

   --  J.Len's own subtype (0 .. Limits.Max_Line_Length, matching
   --  J.Val's length) already guarantees it never runs past J.Val, so
   --  this needs no Pre or Post beyond that subtype.
   procedure Put (J : in out Joined_Text; Piece : String) is
   begin
      if not J.Ok then
         return;
      elsif Piece'Length <= J.Val'Length - J.Len then
         J.Val
           (J.Val'First + J.Len .. J.Val'First + J.Len + Piece'Length - 1) :=
           Piece;
         J.Len := J.Len + Piece'Length;
      else
         J.Ok := False;
      end if;
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

   function Bracket_Label (S : Results.Status) return String is
      Word : constant String := Status_Word (S);
      Pad  : constant String (1 .. 10 - Word'Length) := [others => ' '];
   begin
      return "[   " & Word & Pad & "] ";
   end Bracket_Label;

   ---------------------------------------------------------------------
   --  Header, step and location text.
   ---------------------------------------------------------------------

   function Header_Text (Keyword, Name : String) return String is
      B : Builder;
   begin
      Put (B, Keyword);
      Put (B, ": ");
      Put (B, Name);
      return Text_Of (B);
   end Header_Text;

   function Step_Text (Keyword, Text : String) return String is
      B : Builder;
   begin
      Put (B, Keyword);
      Put (B, ' ');
      Put (B, Text);
      return Text_Of (B);
   end Step_Text;

   function Location_Text (File : String; Line_No : Natural) return String is
      B : Builder;
   begin
      Put (B, "  ");
      Put (B, File);
      Put (B, ':');
      Put (B, Check.Integer_Image (Line_No));
      return Text_Of (B);
   end Location_Text;

   ---------------------------------------------------------------------
   --  Tables.
   ---------------------------------------------------------------------

   --  The two Examples-row handles a resolution needs; both 0 for a
   --  plain scenario's step. Bundled so a helper stays within R5's
   --  five-parameter limit once it also carries a cell or a widths
   --  array.
   type Substitution is record
      Header_Row : Ast.Examples_Row_Handle := 0;
      Data_Row   : Ast.Examples_Row_Handle := 0;
   end record;

   --  Widens Widths by one cell; a stale cell (past the Document's
   --  current pool) counts as width 0, never read.
   procedure Widen_Column
     (Doc    : Ast.Document;
      C      : Ast.Cell_Handle;
      Col    : Positive;
      Sub    : Substitution;
      Widths : in out Column_Widths)
   is
      Len : constant Natural :=
        (if C = 0 or else C > Ast.Cell_Count (Doc)
         then 0
         else
           Expand.Resolved
             (Doc, Ast.Cell (Doc, C), Sub.Header_Row, Sub.Data_Row)
             .Len);
   begin
      if Col <= Limits.Max_Table_Columns then
         Widths (Col) := Natural'Max (Widths (Col), Len);
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
      if Row = 0 or else Row > Ast.Table_Row_Count (Doc) then
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
      Result : Column_Widths := [others => 0];
   begin
      if T = 0 or else T > Ast.Table_Count (Doc) then
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
      Widths : Column_Widths := [others => 0];
   end record;

   procedure Put_Cell
     (Doc : Ast.Document;
      C   : Ast.Cell_Handle;
      Col : Positive;
      Ctx : Cell_Context;
      B   : in out Builder)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
      Text  : constant String :=
        (if C = 0 or else C > Ast.Cell_Count (Doc)
         then ""
         else
           Expand.Value
             (Expand.Resolved
                (Doc,
                 Ast.Cell (Doc, C),
                 Ctx.Sub.Header_Row,
                 Ctx.Sub.Data_Row)));
      Width : constant Natural :=
        (if Col <= Limits.Max_Table_Columns
         then Ctx.Widths (Col)
         else Text'Length);
   begin
      Put (B, " ");
      Put (B, Text);
      for I in Text'Length + 1 .. Width loop
         pragma Loop_Invariant (B.Len <= B.Buf'Length);
         Put (B, " ");
      end loop;
      Put (B, " |");
   end Put_Cell;

   procedure Put_Cells
     (Doc   : Ast.Document;
      Cells : Ast.Cell_Range;
      Ctx   : Cell_Context;
      B     : in out Builder)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
   begin
      for C in Cells.First .. Cells.Last loop
         pragma Loop_Invariant (B.Len <= B.Buf'Length);
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
      Put (B, "  |");
      if Row /= 0 and then Row <= Ast.Table_Row_Count (Doc) then
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
      Data_Row   : Ast.Examples_Row_Handle) return String is
   begin
      if L = 0 or else L > Ast.Doc_Line_Count (Doc) then
         return "";
      end if;
      return
        Expand.Value
          (Expand.Resolved (Doc, Ast.Doc_Line (Doc, L), Header_Row, Data_Row));
   end Doc_Content_Text;

   --  Space-joins D's resolved lines into J; a stale line (past the
   --  Document's current pool) stops the join and refuses it.
   procedure Join_Lines
     (Doc        : Ast.Document;
      Lines      : Ast.Doc_Line_Range;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle;
      J          : in out Joined_Text)
   is
      Seen : Boolean := False;
   begin
      for L in Lines.First .. Lines.Last loop
         if L > Ast.Doc_Line_Count (Doc) then
            J.Ok := False;
            return;
         end if;
         if Seen then
            Put (J, " ");
         end if;
         Put
           (J,
            Expand.Value
              (Expand.Resolved
                 (Doc, Ast.Doc_Line (Doc, L), Header_Row, Data_Row)));
         Seen := True;
      end loop;
   end Join_Lines;

   function Doc_String_Content
     (Doc        : Ast.Document;
      D          : Ast.Doc_Handle;
      Header_Row : Ast.Examples_Row_Handle;
      Data_Row   : Ast.Examples_Row_Handle) return Joined_Text
   is
      Result : Joined_Text := (Ok => False, others => <>);
   begin
      if D = 0 or else D > Ast.Doc_String_Count (Doc) then
         return Result;
      end if;
      Result.Ok := True;
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
            declare
               Stop : constant Natural := I - 1;
            begin
               Put (Result, Raw (Start .. Stop));
            end;
            Put (Result, " ");
            Start := I + 1;
         end if;
      end loop;
      Put (Result, Raw (Start .. Raw'Last));
      return Result;
   end Description_Content;

   ---------------------------------------------------------------------
   --  Count summaries.
   ---------------------------------------------------------------------

   --  A + B, capped at Natural'Last: the same saturating rule
   --  Fabula.Results uses for each counter, so a summary's total can
   --  never overflow even at the shipped saturation point.
   function Sat_Add (A, B : Natural) return Natural
   is (if A > Natural'Last - B then Natural'Last else A + B);

   --  Appends "<n> <label>" to B, with a leading ", " once a prior
   --  category has already printed; Count = 0 prints nothing. Seen
   --  reports forward to the next category in the same summary.
   procedure Put_Category
     (Count : Natural;
      Label : String;
      Seen  : in out Boolean;
      B     : in out Builder)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
   begin
      if Count > 0 then
         if Seen then
            Put (B, ", ");
         end if;
         Put (B, Check.Integer_Image (Count));
         Put (B, " ");
         Put (B, Label);
         Seen := True;
      end if;
   end Put_Category;

   --  The same, for a summary's last category: nothing follows, so
   --  Seen only looks back (whether a comma is needed) and the
   --  procedure has nothing left to report forward.
   procedure Put_Last_Category
     (Count : Natural; Label : String; Seen : Boolean; B : in out Builder)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
   begin
      if Count > 0 then
         if Seen then
            Put (B, ", ");
         end if;
         Put (B, Check.Integer_Image (Count));
         Put (B, " ");
         Put (B, Label);
      end if;
   end Put_Last_Category;

   function Scenarios_Summary (C : Results.Counts) return String is
      Total : constant Natural :=
        Sat_Add
          (Sat_Add (C.Scenarios_Failed, C.Scenarios_Skipped),
           Sat_Add (C.Scenarios_Passed, C.Scenarios_Undefined));
      B     : Builder;
      Seen  : Boolean := False;
   begin
      Put (B, Check.Integer_Image (Total));
      Put (B, (if Total > 1 then " Scenarios (" else " Scenario ("));
      Put_Category (C.Scenarios_Failed, "failed", Seen, B);
      Put_Category (C.Scenarios_Skipped, "skipped", Seen, B);
      Put_Last_Category (C.Scenarios_Passed, "passed", Seen, B);
      Put (B, ")");
      return Text_Of (B);
   end Scenarios_Summary;

   function Steps_Summary (C : Results.Counts) return String is
      Total : constant Natural :=
        Sat_Add
          (Sat_Add (C.Steps_Failed, C.Steps_Undefined),
           Sat_Add (C.Steps_Skipped, C.Steps_Passed));
      B     : Builder;
      Seen  : Boolean := False;
   begin
      Put (B, Check.Integer_Image (Total));
      Put (B, (if Total > 1 then " Steps (" else " Step ("));
      Put_Category (C.Steps_Failed, "failed", Seen, B);
      Put_Category (C.Steps_Undefined, "undefined", Seen, B);
      Put_Category (C.Steps_Skipped, "skipped", Seen, B);
      Put_Last_Category (C.Steps_Passed, "passed", Seen, B);
      Put (B, ")");
      return Text_Of (B);
   end Steps_Summary;

   ---------------------------------------------------------------------
   --  The failed-scenarios store.
   ---------------------------------------------------------------------

   procedure Add_Failed
     (Store : in out Failed_Store; Name, File : String; Line_No : Natural) is
   begin
      if Store.Count = Limits.Max_Failed_Scenarios then
         return;
      end if;
      Store.Count := Store.Count + 1;
      Store.Items (Store.Count).Name (1 .. Name'Length) := Name;
      Store.Items (Store.Count).Name_Len := Name'Length;
      Store.Items (Store.Count).File (1 .. File'Length) := File;
      Store.Items (Store.Count).File_Len := File'Length;
      Store.Items (Store.Count).Line := Line_No;
   end Add_Failed;

   function Failed_Name (Store : Failed_Store; I : Positive) return String
   is (Store.Items (I).Name (1 .. Store.Items (I).Name_Len));

   function Failed_File (Store : Failed_Store; I : Positive) return String
   is (Store.Items (I).File (1 .. Store.Items (I).File_Len));

   function Failed_Line (Store : Failed_Store; I : Positive) return Natural
   is (Store.Items (I).Line);

   ---------------------------------------------------------------------
   --  -v's non-hook lines.
   ---------------------------------------------------------------------

   function Verbose_Scenario_Start
     (Name : String; File : String; Line_No : Natural) return String
   is
      B : Builder;
   begin
      Put (B, "[   VERBOSE   ] Scenario Start '");
      Put (B, Name);
      Put (B, "' - File: ");
      Put (B, File);
      Put (B, ':');
      Put (B, Check.Integer_Image (Line_No));
      return Text_Of (B);
   end Verbose_Scenario_Start;

   function Verbose_Tag_Check
     (Tags : String; Expression : String; Passed : Boolean) return String
   is
      B : Builder;
   begin
      Put (B, "[   VERBOSE   ] Scenario tags '");
      Put (B, Tags);
      Put (B, "'");
      Put (B, ASCII.LF);
      Put (B, "                checked against tag expression '");
      Put (B, Expression);
      Put (B, "' -> ");
      Put
        (B,
         (if Passed
          then "'True', continuing with scenario"
          else "'False', stopping scenario"));
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
      Start : Natural := 0;
   begin
      for I in Text'Range loop
         if Text (I) /= ' ' and then Text (I) /= ASCII.HT then
            Start := I;
            exit;
         end if;
      end loop;
      if Start = 0 then
         return "";
      end if;
      declare
         Last : Natural := Start;
      begin
         for I in Start .. Text'Last loop
            pragma Loop_Invariant (Last in Start .. Text'Last);
            exit when Text (I) = ' ' or else Text (I) = ASCII.HT;
            Last := I;
         end loop;
         return Text (Start .. Last);
      end;
   end First_Token;

   --  One pass, one flag: In_Tag is True while stepping through a "@..."
   --  run already seen to start with '@'. A blank always clears it (a
   --  tag token cannot contain one); the first character that starts
   --  neither a blank run nor a tag is the answer.
   function First_Bad_Tag_Token (Text : String) return String is
      In_Tag : Boolean := False;
   begin
      for I in Text'Range loop
         if Text (I) = ' ' or else Text (I) = ASCII.HT then
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

   function Parse_Error_Text
     (File    : String;
      Line_No : Natural;
      Kind    : Parse.Error_Kind;
      At_End  : Boolean;
      Token   : String) return String
   is
      B : Builder;
   begin
      Put (B, File);
      Put (B, ':');
      Put (B, Check.Integer_Image (Line_No));
      Put (B, ": Error");
      if No_Token_Kind (Kind) then
         Put (B, " : ");
      elsif At_End then
         Put (B, " at end: ");
      elsif Kind = Parse.Tag_Line_Malformed then
         Put (B, " at '");
         Put (B, First_Bad_Tag_Token (Token));
         Put (B, "': ");
      else
         Put (B, " at '");
         Put (B, First_Token (Token));
         Put (B, "': ");
      end if;
      Put (B, Parse_Message (Kind));
      return Text_Of (B);
   end Parse_Error_Text;

   ---------------------------------------------------------------------
   --  JSON.
   ---------------------------------------------------------------------

   function Hex_Digit (N : Natural) return Character
   is (if N < 10
       then Character'Val (Character'Pos ('0') + N)
       else Character'Val (Character'Pos ('a') + N - 10))
   with Pre => N <= 15;

   function Unicode_Escape (Ch : Character) return String with Pre => Ch < ' '
   is
      Code : constant Natural := Character'Pos (Ch);
   begin
      return "\u00" & Hex_Digit (Code / 16) & Hex_Digit (Code mod 16);
   end Unicode_Escape;

   procedure Escape_Char (Ch : Character; B : in out Builder)
   with Pre => B.Len <= B.Buf'Length, Post => B.Len <= B.Buf'Length
   is
   begin
      case Ch is
         when '"'      =>
            Put (B, "\""");

         when '\'      =>
            Put (B, "\\");

         when ASCII.LF =>
            Put (B, "\n");

         when ASCII.CR =>
            Put (B, "\r");

         when ASCII.HT =>
            Put (B, "\t");

         when ASCII.BS =>
            Put (B, "\b");

         when ASCII.FF =>
            Put (B, "\f");

         when others   =>
            if Ch < ' ' then
               Put (B, Unicode_Escape (Ch));
            else
               Put (B, [1 => Ch]);
            end if;
      end case;
   end Escape_Char;

   function Escape_Json (Source : String) return String is
      B : Builder;
   begin
      for I in Source'Range loop
         pragma Loop_Invariant (B.Len <= B.Buf'Length);
         Escape_Char (Source (I), B);
      end loop;
      return Text_Of (B);
   end Escape_Json;

   function Scenario_Id
     (Feature_Name  : String;
      Rule_Name     : String;
      Scenario_Name : String;
      Occurrence    : Natural) return String
   is
      B : Builder;
   begin
      if Occurrence /= 0 then
         Put (B, '(');
         Put (B, Check.Integer_Image (Occurrence));
         Put (B, ") ");
      end if;
      Put (B, Feature_Name);
      Put (B, ';');
      if Rule_Name'Length /= 0 then
         Put (B, Rule_Name);
         Put (B, ';');
      end if;
      Put (B, Scenario_Name);
      return Text_Of (B);
   end Scenario_Id;

   function Indent (Depth : Depth_Value) return String
   is ([1 .. 2 * Depth => ' '])
   with Post => Indent'Result'Length = 2 * Depth;

   function Open_Object (Depth : Depth_Value) return String
   is (Indent (Depth) & "{");

   function Open_Named_Object (Key : String; Depth : Depth_Value) return String
   is (Indent (Depth) & Quote & Key & Quote & ": {");

   function Close_Object (Depth : Depth_Value; More : Boolean) return String
   is (Indent (Depth) & (if More then "}," else "}"));

   function Open_Array (Key : String; Depth : Depth_Value) return String
   is (Indent (Depth) & Quote & Key & Quote & ": [");

   function Close_Array (Depth : Depth_Value; More : Boolean) return String
   is (Indent (Depth) & (if More then "]," else "]"));

   function Empty_Array_Field
     (Key : String; Depth : Depth_Value; More : Boolean) return String
   is (Indent (Depth)
       & Quote
       & Key
       & Quote
       & ": []"
       & (if More then "," else ""));

   function String_Field
     (Key, Escaped_Value : String; Depth : Depth_Value; More : Boolean)
      return String
   is (Indent (Depth)
       & Quote
       & Key
       & Quote
       & ": "
       & Quote
       & Escaped_Value
       & Quote
       & (if More then "," else ""));

   function String_Item
     (Escaped_Value : String; Depth : Depth_Value; More : Boolean)
      return String
   is (Indent (Depth)
       & Quote
       & Escaped_Value
       & Quote
       & (if More then "," else ""));

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
      Put (B, ": ");
      Put (B, Check.Integer_Image (Value));
      if More then
         Put (B, ',');
      end if;
      return Text_Of (B);
   end Number_Field;

end Fabula.Format;
