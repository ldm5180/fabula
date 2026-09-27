--  argv tokens, already split into one bounded string per token, folded
--  into a typed Options_Result: no file-system call, no interpretation
--  of what a path names.  The shell classifies the --report-json value
--  token before this package ever sees it (docs/report_wiring.md);
--  every other flag's value is whatever token follows it, unconditionally.
--  An empty Tag_Expr or Names means "no filter", the caller's own
--  convention (Fabula.Tags, Fabula.Run) -- this package never decides
--  that, only stores what it was given.
with Fabula.Limits;
with Fabula.Texts;

package Fabula.Cli
  with SPARK_Mode
is

   ---------------------------------------------------------------------
   --  One argv token, bounded.  Max_Line_Length is generous above every
   --  field this package bounds more tightly (a path, a tag expression,
   --  the -n patterns), so a real token never needs truncating here; the
   --  shell truncates only a token from an environment with no bound of
   --  its own before handing it over.
   ---------------------------------------------------------------------

   subtype Arg_Text is Texts.Line_Text;

   --  Text's first Max_Line_Length characters.
   function To_Arg (Text : String) return Arg_Text
   is (Texts.Truncated (Text, Limits.Max_Line_Length));

   type Arg_List is array (Positive range <>) of Arg_Text;

   ---------------------------------------------------------------------
   --  The flags.  Each has one row in one table, with its short and its
   --  long spelling; a token is one flag's spelling, the merged
   --  --report-json=FILE form the shell builds, an unknown flag (any
   --  other token that starts with '-'), or not a flag at all.
   ---------------------------------------------------------------------

   type Flag_Kind is
     (Help_Flag,
      Quiet_Flag,
      Verbose_Flag,
      Dry_Run_Flag,
      Continue_Flag,
      Tags_Flag,
      Name_Flag,
      Exclude_Flag,
      Report_Json_Flag,
      Report_File_Flag,
      Unknown_Flag,
      Not_A_Flag);

   --  The flags the table spells.
   subtype Spelled_Flag is Flag_Kind range Help_Flag .. Report_Json_Flag;

   --  The flags whose value is the next token.
   subtype Valued_Flag is Flag_Kind range Tags_Flag .. Exclude_Flag;

   --  "" for a flag with no short spelling.
   function Short_Of (F : Spelled_Flag) return String;
   function Long_Of (F : Spelled_Flag) return String;

   --  "--report-json=": the shell folds --report-json and its file into
   --  one token that starts with this.
   function Report_Json_Prefix return String;

   --  The suffix every feature file's name ends in.
   Feature_Suffix : constant String := ".feature";

   function Classify (Token : String) return Flag_Kind
   with Pre => Token'First = Positive'First;

   ---------------------------------------------------------------------
   --  Refusals.  The first one sticks; scanning stops there.
   ---------------------------------------------------------------------

   type Refusal_Kind is
     (None,
      Unknown_Option,             --  a "-..." token no flag matches
      Missing_Value,               --  a value-taking flag with nothing after
      Tag_Expression_Too_Long,     --  would overrun Fabula.Tags.Compile's Pre
      Name_Patterns_Too_Long,      --  over Limits.Max_Name_Filter_Length
      Report_Json_Path_Too_Long,   --  over Limits.Max_Path_Length
      Exclude_Path_Too_Long,       --  over Limits.Max_Path_Length
      Too_Many_Excludes,           --  over Limits.Max_Cli_Excludes
      Too_Many_Positionals);       --  over Limits.Max_Cli_Positionals

   type Refusal is private;

   function Kind_Of (R : Refusal) return Refusal_Kind;

   --  The token the refusal names: the unknown flag, the flag missing a
   --  value, or the over-long text, as written.
   function Token_Of (R : Refusal) return String;

   --  Fabula's own wording -- the reference interpreter silently ignores
   --  an unknown flag or a missing value, so there is no analogue to
   --  copy for most of these (docs/report_wiring.md).
   function Refusal_Text (R : Refusal) return String
   with Pre => Kind_Of (R) /= None;

   ---------------------------------------------------------------------
   --  The parsed result.
   ---------------------------------------------------------------------

   --  -q and -v set one level.  The reference interpreter sets -q's
   --  level, then overwrites it with -v's when both are given, so
   --  Verbose wins whatever the order.
   type Log_Level is (Normal, Quiet, Verbose);

   --  Where the report goes: the console report, or the JSON report on
   --  standard output (a bare --report-json) or in a file (the merged
   --  --report-json=FILE).  A later bare flag keeps a file target, and
   --  the last file wins.
   type Report_Target is (Console, Json_Stdout, Json_File);

   subtype Exclude_Count is Natural range 0 .. Limits.Max_Cli_Excludes;
   subtype Positional_Count is Natural range 0 .. Limits.Max_Cli_Positionals;

   type Options_Result is private;

   --  A refused result names its refusal; there is no other flag.
   function Refused (R : Options_Result) return Boolean;
   function Refusal_Of (R : Options_Result) return Refusal
   with Pre => Refused (R);

   function Help (R : Options_Result) return Boolean;
   function Log_Level_Of (R : Options_Result) return Log_Level;
   function Dry_Run (R : Options_Result) return Boolean;
   function Continue_On_Failure (R : Options_Result) return Boolean;

   --  "" means no filter (the caller's own convention).
   function Tag_Expr_Text (R : Options_Result) return String;
   function Names_Text (R : Options_Result) return String
   with Post => Names_Text'Result'Length <= Limits.Max_Name_Filter_Length;

   function Report_Target_Of (R : Options_Result) return Report_Target;

   --  The file of the Json_File target; it may be empty.
   function Report_Json_File_Text (R : Options_Result) return String;

   function Excludes_Count (R : Options_Result) return Exclude_Count;
   function Exclude_Text (R : Options_Result; I : Positive) return String
   with Pre => I <= Excludes_Count (R);

   function Positionals_Count (R : Options_Result) return Positional_Count;
   function Positional_Text (R : Options_Result; I : Positive) return String
   with Pre => I <= Positionals_Count (R);

   --  Empty Args means Help alone, matching the reference interpreter's
   --  own no-argument run, and so does a -h or --help anywhere, even as
   --  another flag's value: the reference interpreter checks for it
   --  before it parses anything else.  Args'First = 1, as the shell
   --  always builds it from argv; Args'Last stays below Positive'Last
   --  so every index this package advances one token at a time never
   --  overflows.
   function Parse (Args : Arg_List) return Options_Result
   with Pre => Args'First = Positive'First and then Args'Last < Positive'Last;

   function Help_Text return String;

private

   ---------------------------------------------------------------------
   --  The flag table.
   ---------------------------------------------------------------------

   --  The longest spelling ("--continue-on-failure"), value hint and
   --  help description each column holds.
   Longest_Spelling    : constant := 21;
   Longest_Hint        : constant := 16;
   Longest_Description : constant := 64;

   subtype Spelling is Texts.Bounded_Text (Longest_Spelling);
   subtype Hint_Text is Texts.Bounded_Text (Longest_Hint);
   subtype Description_Text is Texts.Bounded_Text (Longest_Description);

   subtype Spelling_Length is Natural range 0 .. Longest_Spelling;
   subtype Hint_Length is Natural range 0 .. Longest_Hint;

   --  A help line's description starts in Help_Column; before it, the
   --  lead: the indent, the short spelling and its separator when there
   --  is one, the long spelling and the value hint.
   Help_Column     : constant := 31;
   Option_Indent   : constant String := "  ";
   Short_Separator : constant String := ", ";

   function Lead_Width
     (Short, Long : Spelling_Length; Hint : Hint_Length) return Natural
   is (Option_Indent'Length
       + (if Short = Texts.Empty_Length
          then Texts.Empty_Length
          else Short + Short_Separator'Length)
       + Long
       + Hint);

   --  One flag: its short spelling ("" for none) and its long one, the
   --  hint its help line gives for its value, and its help description,
   --  which a second help line may continue.  Its lead always fits
   --  before Help_Column.
   type Flag_Row is record
      Short       : Spelling;
      Long        : Spelling;
      Hint        : Hint_Text;
      Description : Description_Text;
      Continued   : Description_Text;
   end record
   with
     Dynamic_Predicate =>
       Lead_Width
         (Texts.Length (Flag_Row.Short),
          Texts.Length (Flag_Row.Long),
          Texts.Length (Flag_Row.Hint))
       <= Help_Column;

   --  A row whose every text fits its column, so nothing is cut.
   function Row
     (Short, Long, Hint, Description : String; Continued : String := "")
      return Flag_Row
   is ((Short       => Texts.Truncated (Short, Longest_Spelling),
        Long        => Texts.Truncated (Long, Longest_Spelling),
        Hint        => Texts.Truncated (Hint, Longest_Hint),
        Description => Texts.Truncated (Description, Longest_Description),
        Continued   => Texts.Truncated (Continued, Longest_Description)))
   with
     Pre =>
       Short'Length <= Longest_Spelling
       and then Long'Length <= Longest_Spelling
       and then Hint'Length <= Longest_Hint
       and then Description'Length <= Longest_Description
       and then Continued'Length <= Longest_Description
       and then Lead_Width (Short'Length, Long'Length, Hint'Length)
                <= Help_Column;

   --!format off
   Flags : constant array (Spelled_Flag) of Flag_Row :=
     [Help_Flag        => Row ("-h", "--help", "",
                               "print this help and exit"),
      Quiet_Flag       => Row ("-q", "--quiet", "",
                               "print only errors and the summary"),
      Verbose_Flag     => Row ("-v", "--verbose", "",
                               "print extra detail as a scenario runs"),
      Dry_Run_Flag     => Row ("-d", "--dry-run", "",
                               "check steps are defined; run none of them"),
      Continue_Flag    => Row ("-c", "--continue-on-failure", "",
                               "keep running a scenario's steps after one"
                               & " fails"),
      Tags_Flag        => Row ("-t", "--tags", " <EXPRESSION>",
                               "run only scenarios the tag expression"
                               & " selects"),
      Name_Flag        => Row ("-n", "--name", " <PATTERN>",
                               "run only scenarios whose name matches; ':'"
                               & " separates",
                               "several patterns, '*' and '?' wildcard"),
      Exclude_Flag     => Row ("", "--exclude-file", " <SUFFIX>",
                               "skip a discovered file whose path ends in"
                               & " SUFFIX"),
      Report_Json_Flag => Row ("", "--report-json", " [FILE]",
                               "write a JSON report to FILE, or to stdout")];
   --!format on

   function Short_Of (F : Spelled_Flag) return String
   is (Texts.Value (Flags (F).Short));

   function Long_Of (F : Spelled_Flag) return String
   is (Texts.Value (Flags (F).Long));

   --  What joins --report-json to its file in the merged token.
   Value_Mark : constant Character := '=';

   function Report_Json_Prefix return String
   is (Long_Of (Report_Json_Flag) & Value_Mark);

   ---------------------------------------------------------------------
   --  The result.
   ---------------------------------------------------------------------

   Token_Length : constant := Limits.Max_Line_Length;

   type Refusal is record
      Kind  : Refusal_Kind := None;
      Token : Texts.Bounded_Text (Token_Length);
   end record;

   function Kind_Of (R : Refusal) return Refusal_Kind
   is (R.Kind);

   function Token_Of (R : Refusal) return String
   is (Texts.Value (R.Token));

   subtype Path_Text is Texts.Bounded_Text (Limits.Max_Path_Length);

   type Exclude_Array is array (1 .. Limits.Max_Cli_Excludes) of Path_Text;

   type Positional_Array is
     array (1 .. Limits.Max_Cli_Positionals) of Arg_Text;

   No_Excludes    : constant Exclude_Count := 0;
   No_Positionals : constant Positional_Count := 0;

   type Options_Result is record
      Refusal_Info          : Refusal;
      Is_Help               : Boolean := False;
      Log                   : Log_Level := Normal;
      Is_Dry_Run            : Boolean := False;
      Is_Continue           : Boolean := False;
      Tag_Expr              : Texts.Bounded_Text (Limits.Max_Tag_Expr_Length);
      Names                 :
        Texts.Bounded_Text (Limits.Max_Name_Filter_Length);
      Target                : Report_Target := Console;
      Report_Json_File      : Path_Text;
      Exclude_List_Count    : Exclude_Count := No_Excludes;
      Exclude_List          : Exclude_Array;
      Positional_List_Count : Positional_Count := No_Positionals;
      Positional_List       : Positional_Array;
   end record;

   function Refused (R : Options_Result) return Boolean
   is (Kind_Of (R.Refusal_Info) /= None);

   function Refusal_Of (R : Options_Result) return Refusal
   is (R.Refusal_Info);

   function Help (R : Options_Result) return Boolean
   is (R.Is_Help);

   function Log_Level_Of (R : Options_Result) return Log_Level
   is (R.Log);

   function Dry_Run (R : Options_Result) return Boolean
   is (R.Is_Dry_Run);

   function Continue_On_Failure (R : Options_Result) return Boolean
   is (R.Is_Continue);

   function Tag_Expr_Text (R : Options_Result) return String
   is (Texts.Value (R.Tag_Expr));

   function Names_Text (R : Options_Result) return String
   is (Texts.Value (R.Names));

   function Report_Target_Of (R : Options_Result) return Report_Target
   is (R.Target);

   function Report_Json_File_Text (R : Options_Result) return String
   is (Texts.Value (R.Report_Json_File));

   function Excludes_Count (R : Options_Result) return Exclude_Count
   is (R.Exclude_List_Count);

   function Exclude_Text (R : Options_Result; I : Positive) return String
   is (Texts.Value (R.Exclude_List (I)));

   function Positionals_Count (R : Options_Result) return Positional_Count
   is (R.Positional_List_Count);

   function Positional_Text (R : Options_Result; I : Positive) return String
   is (Texts.Value (R.Positional_List (I)));

end Fabula.Cli;
