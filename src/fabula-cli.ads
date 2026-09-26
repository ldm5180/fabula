--  argv tokens, already split into one bounded string per token, folded
--  into a typed Options_Result: no file-system call, no interpretation
--  of what a path names.  The shell classifies the --report-json value
--  token before this package ever sees it (docs/report_wiring.md);
--  every other flag's value is whatever token follows it, unconditionally.
--  An empty Tag_Expr or Names means "no filter", the caller's own
--  convention (Fabula.Tags, Fabula.Run) -- this package never decides
--  that, only stores what it was given.
with Fabula.Limits;

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

   type Arg_Text is private;

   function Value (A : Arg_Text) return String
   with Post => Value'Result'First = 1;

   procedure Set (A : out Arg_Text; Text : String);  --  truncates

   type Arg_List is array (Positive range <>) of Arg_Text;

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

   subtype Exclude_Count is Natural range 0 .. Limits.Max_Cli_Excludes;
   subtype Positional_Count is Natural range 0 .. Limits.Max_Cli_Positionals;

   type Options_Result is private;

   function Refused (R : Options_Result) return Boolean;
   function Refusal_Of (R : Options_Result) return Refusal
   with Pre => Refused (R);

   function Help (R : Options_Result) return Boolean;
   function Quiet (R : Options_Result) return Boolean;
   function Verbose (R : Options_Result) return Boolean;
   function Dry_Run (R : Options_Result) return Boolean;
   function Continue_On_Failure (R : Options_Result) return Boolean;

   --  "" means no filter (the caller's own convention).
   function Tag_Expr_Text (R : Options_Result) return String;
   function Names_Text (R : Options_Result) return String;

   function Report_Json (R : Options_Result) return Boolean;
   function Report_Json_Has_File (R : Options_Result) return Boolean;
   function Report_Json_File_Text (R : Options_Result) return String;

   function Excludes_Count (R : Options_Result) return Exclude_Count;
   function Exclude_Text (R : Options_Result; I : Positive) return String
   with Pre => I <= Excludes_Count (R);

   function Positionals_Count (R : Options_Result) return Positional_Count;
   function Positional_Text (R : Options_Result; I : Positive) return String
   with Pre => I <= Positionals_Count (R);

   --  Empty Args means Help alone, matching the reference interpreter's
   --  own no-argument run.  Args'First = 1, as the shell always builds
   --  it from argv; Args'Last stays below Positive'Last so every index
   --  this package advances one token at a time never overflows.
   procedure Parse (Args : Arg_List; Result : out Options_Result)
   with
     Pre  => Args'First = 1 and then Args'Last < Positive'Last,
     Post => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None);

   Help_Text : constant String;

private

   type Arg_Text is record
      Data : String (1 .. Limits.Max_Line_Length) := [others => ' '];
      Len  : Natural range 0 .. Limits.Max_Line_Length := 0;
   end record;

   function Value (A : Arg_Text) return String
   is (A.Data (1 .. A.Len));

   Token_Length : constant := Limits.Max_Line_Length;

   type Refusal is record
      Kind      : Refusal_Kind := None;
      Token     : String (1 .. Token_Length) := [others => ' '];
      Token_Len : Natural range 0 .. Token_Length := 0;
   end record;

   function Kind_Of (R : Refusal) return Refusal_Kind
   is (R.Kind);

   function Token_Of (R : Refusal) return String
   is (R.Token (1 .. R.Token_Len));

   type Exclude_Text_Field is record
      Data : String (1 .. Limits.Max_Path_Length) := [others => ' '];
      Len  : Natural range 0 .. Limits.Max_Path_Length := 0;
   end record;

   type Exclude_Array is
     array (1 .. Limits.Max_Cli_Excludes) of Exclude_Text_Field;

   type Positional_Array is
     array (1 .. Limits.Max_Cli_Positionals) of Arg_Text;

   type Options_Result is record
      Is_Refused            : Boolean := False;
      Refusal_Info          : Refusal;
      Is_Help               : Boolean := False;
      Is_Quiet              : Boolean := False;
      Is_Verbose            : Boolean := False;
      Is_Dry_Run            : Boolean := False;
      Is_Continue           : Boolean := False;
      Tag_Expr              : String (1 .. Limits.Max_Tag_Expr_Length) :=
        [others => ' '];
      Tag_Expr_Len          : Natural range 0 .. Limits.Max_Tag_Expr_Length :=
        0;
      Names                 : String (1 .. Limits.Max_Name_Filter_Length) :=
        [others => ' '];
      Names_Len             :
        Natural range 0 .. Limits.Max_Name_Filter_Length := 0;
      Is_Report_Json        : Boolean := False;
      Report_Json_File_Set  : Boolean := False;
      Report_Json_File      : String (1 .. Limits.Max_Path_Length) :=
        [others => ' '];
      Report_Json_File_Len  : Natural range 0 .. Limits.Max_Path_Length := 0;
      Exclude_List_Count    : Exclude_Count := 0;
      Exclude_List          : Exclude_Array;
      Positional_List_Count : Positional_Count := 0;
      Positional_List       : Positional_Array;
   end record;

   function Refused (R : Options_Result) return Boolean
   is (R.Is_Refused);

   function Refusal_Of (R : Options_Result) return Refusal
   is (R.Refusal_Info);

   function Help (R : Options_Result) return Boolean
   is (R.Is_Help);

   function Quiet (R : Options_Result) return Boolean
   is (R.Is_Quiet);

   function Verbose (R : Options_Result) return Boolean
   is (R.Is_Verbose);

   function Dry_Run (R : Options_Result) return Boolean
   is (R.Is_Dry_Run);

   function Continue_On_Failure (R : Options_Result) return Boolean
   is (R.Is_Continue);

   function Tag_Expr_Text (R : Options_Result) return String
   is (R.Tag_Expr (1 .. R.Tag_Expr_Len));

   function Names_Text (R : Options_Result) return String
   is (R.Names (1 .. R.Names_Len));

   function Report_Json (R : Options_Result) return Boolean
   is (R.Is_Report_Json);

   function Report_Json_Has_File (R : Options_Result) return Boolean
   is (R.Report_Json_File_Set);

   function Report_Json_File_Text (R : Options_Result) return String
   is (R.Report_Json_File (1 .. R.Report_Json_File_Len));

   function Excludes_Count (R : Options_Result) return Exclude_Count
   is (R.Exclude_List_Count);

   function Exclude_Text (R : Options_Result; I : Positive) return String
   is (R.Exclude_List (I).Data (1 .. R.Exclude_List (I).Len));

   function Positionals_Count (R : Options_Result) return Positional_Count
   is (R.Positional_List_Count);

   function Positional_Text (R : Options_Result; I : Positive) return String
   is (Value (R.Positional_List (I)));

   Help_Text : constant String :=
     "fabula: a Cucumber/Gherkin test runner"
     & ASCII.LF
     & "usage: <binary> [<file>.feature | <file>.feature:LINE... | <dir>]... "
     & "[options]"
     & ASCII.LF
     & ASCII.LF
     & "options:"
     & ASCII.LF
     & "  -h, --help                   print this help and exit"
     & ASCII.LF
     & "  -q, --quiet                  print only errors and the summary"
     & ASCII.LF
     & "  -v, --verbose                print extra detail as a scenario runs"
     & ASCII.LF
     & "  -d, --dry-run                check steps are defined; run none "
     & "of them"
     & ASCII.LF
     & "  -c, --continue-on-failure    keep running a scenario's steps "
     & "after one fails"
     & ASCII.LF
     & "  -t, --tags <EXPRESSION>      run only scenarios the tag "
     & "expression selects"
     & ASCII.LF
     & "  -n, --name <PATTERN>         run only scenarios whose name "
     & "matches; ':' separates"
     & ASCII.LF
     & "                               several patterns, '*' and '?' wildcard"
     & ASCII.LF
     & "  --exclude-file <SUFFIX>      skip a discovered file whose path "
     & "ends in SUFFIX"
     & ASCII.LF
     & "  --report-json [FILE]         write a JSON report to FILE, or to "
     & "stdout";

end Fabula.Cli;
