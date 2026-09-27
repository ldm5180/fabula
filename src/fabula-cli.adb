package body Fabula.Cli
  with SPARK_Mode
is

   ---------------------------------------------------------------------
   --  Classifying one token.
   ---------------------------------------------------------------------

   --  What every flag, known or not, starts with.
   Flag_Mark : constant Character := '-';

   function Starts_With (Text, Prefix : String) return Boolean
   is (Text'Length >= Prefix'Length
       and then Text (Text'First .. Text'First - 1 + Prefix'Length) = Prefix)
   with Pre => Text'First = Positive'First;

   --  Token spells F, in its short or its long form.
   function Spells (F : Spelled_Flag; Token : String) return Boolean
   is (Token = Long_Of (F)
       or else (Short_Of (F) /= "" and then Token = Short_Of (F)));

   --  The kind of a token that spells no flag.
   function Unspelled_Kind (Token : String) return Flag_Kind
   is (if Starts_With (Token, Report_Json_Prefix)
       then Report_File_Flag
       elsif Token'Length > 0 and then Token (Token'First) = Flag_Mark
       then Unknown_Flag
       else Not_A_Flag)
   with Pre => Token'First = Positive'First;

   function Classify (Token : String) return Flag_Kind is
   begin
      for F in Spelled_Flag loop
         if Spells (F, Token) then
            return F;
         end if;
      end loop;
      return Unspelled_Kind (Token);
   end Classify;

   ---------------------------------------------------------------------
   --  Refusals.  The first one sticks.
   ---------------------------------------------------------------------

   procedure Refuse
     (Result : in out Options_Result; Kind : Refusal_Kind; Token : String)
   with Pre => Kind /= None, Post => Refused (Result)
   is
   begin
      if Refused (Result) then
         return;
      end if;
      Result.Refusal_Info :=
        (Kind => Kind, Token => Texts.Truncated (Token, Token_Length));
   end Refuse;

   Quote_Mark : constant Character := ''';

   Unknown_Option_Lead       : constant String := "Unknown option: ";
   Missing_Value_Lead        : constant String := "Missing value for ";
   Tag_Expression_Lead       : constant String := "Tag expression too long: ";
   Name_Patterns_Lead        : constant String :=
     Short_Of (Name_Flag) & " patterns too long: ";
   Report_Path_Lead          : constant String :=
     Long_Of (Report_Json_Flag) & " path too long: ";
   Exclude_Path_Lead         : constant String :=
     Long_Of (Exclude_Flag) & " path too long: ";
   Too_Many_Excludes_Text    : constant String :=
     "Too many " & Long_Of (Exclude_Flag) & " flags";
   Too_Many_Positionals_Text : constant String :=
     "Too many file or directory arguments";

   --  Room for the longest lead below.
   Lead_Room : constant := 64;

   --  Each refusal's text up to the token it names; the whole text for
   --  the two count refusals, which name none.
   function Refusal_Lead (Kind : Refusal_Kind) return String
   is (case Kind is
         when None                      => "",
         when Unknown_Option            => Unknown_Option_Lead,
         when Missing_Value             => Missing_Value_Lead,
         when Tag_Expression_Too_Long   => Tag_Expression_Lead,
         when Name_Patterns_Too_Long    => Name_Patterns_Lead,
         when Report_Json_Path_Too_Long => Report_Path_Lead,
         when Exclude_Path_Too_Long     => Exclude_Path_Lead,
         when Too_Many_Excludes         => Too_Many_Excludes_Text,
         when Too_Many_Positionals      => Too_Many_Positionals_Text)
   with Post => Refusal_Lead'Result'Length <= Lead_Room;

   subtype Count_Refusal is
     Refusal_Kind range Too_Many_Excludes .. Too_Many_Positionals;

   function Refusal_Text (R : Refusal) return String is
      Lead  : constant String := Refusal_Lead (Kind_Of (R));
      Token : constant String := Texts.Value (R.Token);
   begin
      pragma Assert (Token'Length <= Token_Length);
      return
        (if Kind_Of (R) in Count_Refusal
         then Lead
         else Lead & Quote_Mark & Token & Quote_Mark);
   end Refusal_Text;

   ---------------------------------------------------------------------
   --  Bounded stores: one flag's value, one exclude suffix, one path.
   ---------------------------------------------------------------------

   procedure Store_Tag_Expr (Result : in out Options_Result; Text : String) is
   begin
      if Text'Length > Limits.Max_Tag_Expr_Length then
         Refuse (Result, Tag_Expression_Too_Long, Text);
      else
         Result.Tag_Expr := Texts.Truncated (Text, Limits.Max_Tag_Expr_Length);
      end if;
   end Store_Tag_Expr;

   procedure Store_Names (Result : in out Options_Result; Text : String) is
   begin
      if Text'Length > Limits.Max_Name_Filter_Length then
         Refuse (Result, Name_Patterns_Too_Long, Text);
      else
         Result.Names := Texts.Truncated (Text, Limits.Max_Name_Filter_Length);
      end if;
   end Store_Names;

   procedure Add_Exclude (Result : in out Options_Result; Text : String) is
   begin
      if Text'Length > Limits.Max_Path_Length then
         Refuse (Result, Exclude_Path_Too_Long, Text);
      elsif Result.Exclude_List_Count = Limits.Max_Cli_Excludes then
         Refuse (Result, Too_Many_Excludes, Text);
      else
         Result.Exclude_List_Count := Result.Exclude_List_Count + 1;
         Result.Exclude_List (Result.Exclude_List_Count) :=
           Texts.Truncated (Text, Limits.Max_Path_Length);
      end if;
   end Add_Exclude;

   procedure Add_Positional (Result : in out Options_Result; Text : String) is
   begin
      if Result.Positional_List_Count = Limits.Max_Cli_Positionals then
         Refuse (Result, Too_Many_Positionals, Text);
      else
         Result.Positional_List_Count := Result.Positional_List_Count + 1;
         Result.Positional_List (Result.Positional_List_Count) :=
           To_Arg (Text);
      end if;
   end Add_Positional;

   procedure Store_Report_File (Result : in out Options_Result; Text : String)
   is
   begin
      Result.Target := Json_File;
      if Text'Length > Limits.Max_Path_Length then
         Refuse (Result, Report_Json_Path_Too_Long, Text);
      else
         Result.Report_Json_File :=
           Texts.Truncated (Text, Limits.Max_Path_Length);
      end if;
   end Store_Report_File;

   ---------------------------------------------------------------------
   --  Value-taking flags: the next argv token is the value, whatever it
   --  looks like -- the frozen matrix takes it unconditionally.  I moves
   --  to the value, or stays on a flag with nothing after it.
   ---------------------------------------------------------------------

   generic
      with procedure Store (Result : in out Options_Result; Text : String);
   procedure Take_Value
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result)
   with
     Pre  => I in Args'Range and then Args'Last < Positive'Last,
     Post => I in I'Old .. Args'Last;

   procedure Take_Value
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result) is
   begin
      if I = Args'Last then
         Refuse (Result, Missing_Value, Texts.Value (Args (I)));
      else
         I := I + 1;
         Store (Result, Texts.Value (Args (I)));
      end if;
   end Take_Value;

   procedure Take_Tag_Expr is new Take_Value (Store_Tag_Expr);
   procedure Take_Names is new Take_Value (Store_Names);
   procedure Take_Exclude is new Take_Value (Add_Exclude);

   ---------------------------------------------------------------------
   --  One token, of any shape, then the whole list.
   ---------------------------------------------------------------------

   procedure Handle_Token
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result)
   with
     Pre  => I in Args'Range and then Args'Last < Positive'Last,
     Post => I > I'Old and then I <= Args'Last + 1
   is
      Token : constant String := Texts.Value (Args (I));
   begin
      case Classify (Token) is
         when Help_Flag        =>
            Result.Is_Help := True;

         when Quiet_Flag       =>
            Result.Log := Log_Level'Max (Result.Log, Quiet);

         when Verbose_Flag     =>
            Result.Log := Verbose;

         when Dry_Run_Flag     =>
            Result.Is_Dry_Run := True;

         when Continue_Flag    =>
            Result.Is_Continue := True;

         when Tags_Flag        =>
            Take_Tag_Expr (Args, I, Result);

         when Name_Flag        =>
            Take_Names (Args, I, Result);

         when Exclude_Flag     =>
            Take_Exclude (Args, I, Result);

         when Report_Json_Flag =>
            Result.Target := Report_Target'Max (Result.Target, Json_Stdout);

         when Report_File_Flag =>
            Store_Report_File
              (Result, Token (Report_Json_Prefix'Length + 1 .. Token'Last));

         when Unknown_Flag     =>
            Refuse (Result, Unknown_Option, Token);

         when Not_A_Flag       =>
            Add_Positional (Result, Token);
      end case;
      I := I + 1;
   end Handle_Token;

   --  Every token in turn, until one refuses.
   function Scanned (Args : Arg_List) return Options_Result
   with Pre => Args'First = Positive'First and then Args'Last < Positive'Last
   is
      Result : Options_Result;
      I      : Positive := Args'First;
   begin
      while I <= Args'Last and then not Refused (Result) loop
         pragma Loop_Invariant (I in Args'Range);
         pragma Loop_Variant (Increases => I);
         Handle_Token (Args, I, Result);
      end loop;
      return Result;
   end Scanned;

   function Help_Requested (Args : Arg_List) return Boolean
   is (for some A of Args => Spells (Help_Flag, Texts.Value (A)));

   Help_Only : constant Options_Result := (Is_Help => True, others => <>);

   function Parse (Args : Arg_List) return Options_Result
   is (if Args'Length = 0 or else Help_Requested (Args)
       then Help_Only
       else Scanned (Args));

   ---------------------------------------------------------------------
   --  The help screen: a title, the usage line, then one line per flag
   --  from its row of the table, and a second one when its description
   --  continues.  A flag's line starts with its lead, padded to
   --  Help_Column, where its description starts.  The screen's capacity
   --  is the room these lines can take at most, so every piece fits:
   --  the proof shows Ok stays True.
   ---------------------------------------------------------------------

   Blank : constant Character := ' ';
   LF    : constant Character := ASCII.LF;

   Title_Line   : constant String := "fabula: a Cucumber/Gherkin test runner";
   Usage_Line   : constant String :=
     "usage: <binary> [<file>"
     & Feature_Suffix
     & " | <file>"
     & Feature_Suffix
     & ":LINE... | <dir>]... [options]";
   Options_Line : constant String := "options:";

   --  The line end each line after the title starts with.
   Line_End_Length : constant := 1;

   --  The most one help line takes: its line end, its lead padded to
   --  Help_Column, and its description.
   Help_Line_Room : constant :=
     Line_End_Length + Help_Column + Longest_Description;

   --  A flag's help line and the line that continues its description.
   Lines_Per_Flag : constant := 2;
   Flag_Room      : constant := Lines_Per_Flag * Help_Line_Room;

   Flag_Count : constant :=
     Spelled_Flag'Pos (Spelled_Flag'Last)
     - Spelled_Flag'Pos (Spelled_Flag'First)
     + 1;

   --  The title, the usage line, an empty line and the options line.
   Head_Length : constant Natural :=
     Title_Line'Length
     + Line_End_Length
     + Usage_Line'Length
     + Line_End_Length
     + Line_End_Length
     + Options_Line'Length;

   Help_Capacity : constant Positive := Head_Length + Flag_Count * Flag_Room;

   subtype Screen_Text is Texts.Bounded_Text (Help_Capacity);

   --  F's lead: its spellings and its value hint.
   function Option_Lead (F : Spelled_Flag) return String
   is (Option_Indent
       & (if Short_Of (F) = "" then "" else Short_Of (F) & Short_Separator)
       & Long_Of (F)
       & Texts.Value (Flags (F).Hint))
   with Post => Option_Lead'Result'Length <= Help_Column;

   --  Starts a new line of Screen with Text; Ok stays True when it fits.
   procedure Add_Text
     (Screen : in out Screen_Text; Ok : in out Boolean; Text : String)
   with
     Pre  => Text'Length <= Help_Capacity,
     Post =>
       Texts.Length (Screen)
       <= Texts.Length (Screen'Old) + Line_End_Length + Text'Length
       and then (if Ok'Old
                   and then Texts.Length (Screen'Old)
                            <= Help_Capacity - Line_End_Length - Text'Length
                 then Ok)
   is
   begin
      Texts.Append (Screen, [LF], Ok);
      Texts.Append (Screen, Text, Ok);
   end Add_Text;

   --  Starts a new line of Screen with Lead, then blanks up to
   --  Help_Column, then Description.
   procedure Add_Help_Line
     (Screen      : in out Screen_Text;
      Ok          : in out Boolean;
      Lead        : String;
      Description : String)
   with
     Pre  =>
       Lead'Length <= Help_Column
       and then Description'Length <= Longest_Description,
     Post =>
       Texts.Length (Screen) <= Texts.Length (Screen'Old) + Help_Line_Room
       and then (if Ok'Old
                   and then Texts.Length (Screen'Old)
                            <= Help_Capacity - Help_Line_Room
                 then Ok)
   is
   begin
      Add_Text (Screen, Ok, Lead);
      Texts.Append (Screen, [1 .. Help_Column - Lead'Length => Blank], Ok);
      Texts.Append (Screen, Description, Ok);
   end Add_Help_Line;

   --  F's help line, and the line that continues its description.
   procedure Add_Flag
     (Screen : in out Screen_Text; Ok : in out Boolean; F : Spelled_Flag)
   with
     Post =>
       Texts.Length (Screen) <= Texts.Length (Screen'Old) + Flag_Room
       and then (if Ok'Old
                   and then Texts.Length (Screen'Old)
                            <= Help_Capacity - Flag_Room
                 then Ok)
   is
      Continued : constant String := Texts.Value (Flags (F).Continued);
   begin
      Add_Help_Line
        (Screen, Ok, Option_Lead (F), Texts.Value (Flags (F).Description));
      if Continued /= "" then
         Add_Help_Line (Screen, Ok, "", Continued);
      end if;
   end Add_Flag;

   function Built_Screen return Screen_Text with Global => null is
      Screen : Screen_Text;
      Ok     : Boolean := True;
   begin
      Texts.Append (Screen, Title_Line, Ok);
      Add_Text (Screen, Ok, Usage_Line);
      Add_Text (Screen, Ok, "");
      Add_Text (Screen, Ok, Options_Line);
      for F in Spelled_Flag loop
         pragma
           Loop_Invariant
             (Ok
                and then Texts.Length (Screen)
                         <= Head_Length
                            + (Spelled_Flag'Pos (F)
                               - Spelled_Flag'Pos (Spelled_Flag'First))
                              * Flag_Room);
         Add_Flag (Screen, Ok, F);
      end loop;
      pragma Assert (Ok);
      return Screen;
   end Built_Screen;

   Help_Screen : constant Screen_Text := Built_Screen;

   function Help_Text return String
   is (Texts.Value (Help_Screen));

end Fabula.Cli;
