with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;

with Fabula.Cli;
with Fabula.Format;
with Fabula.Parse;
with Fabula.Results;
with Fabula.Run;
with Fabula.Shell.Console;
with Fabula.Shell.Dispatch;
with Fabula.Shell.Files;
with Fabula.Shell.Program_Console;
with Fabula.Shell.Program_Json;
with Fabula.Tags;

package body Fabula.Shell.Program
  with SPARK_Mode => Off
is

   use type Ada.Directories.File_Kind;
   use type Fabula.Cli.Report_Target;
   use type Fabula.Parse.Error_Kind;

   package Console renames Fabula.Shell.Console;
   package Files renames Fabula.Shell.Files;

   package Runner is new
     Fabula.Run (Reg => Steps, Steps => Step_Defs, Hooks => Hook_Defs);

   use type Steps.Row_Status;

   package Console_Report is new
     Fabula.Shell.Program_Console (Reg => Steps, Runner => Runner);
   package Json_Report is new
     Fabula.Shell.Program_Json (Reg => Steps, Runner => Runner);

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame);

   package Drive is new
     Fabula.Shell.Dispatch
       (Reg       => Steps,
        Runner    => Runner,
        Execute   => Execute,
        Run_Hook  => Run_Hook,
        On_Notice => On_Notice);

   ---------------------------------------------------------------------
   --  Run-wide state.  A binary drives one run per process, so this
   --  lives at library level rather than threaded through every call --
   --  the same choice Fabula.Shell.Files makes for its own Document.
   ---------------------------------------------------------------------

   Cli_Opts : Fabula.Cli.Options_Result;
   Opts     : Runner.Options;
   R        : Runner.Runner;
   Ctx      : Steps.Context;
   All_Ctx  : Steps.Context;
   Doc_Ref  : Fabula.Args.Document_Access;

   Discovered : Files.File_List;
   Kept       : Files.File_List;

   --  The report the run writes, chosen once from the report target.
   type Reporter is (Console_Reporter, Json_Reporter);

   Active : Reporter := Console_Reporter;

   --  A refusal never lets the run exit 0.  Set for every discovery
   --  status but Found and Missing (the oracle's observed exit-0
   --  cases); Too_Long needs no flag of its own -- it counts as a parse
   --  error instead, so Fabula.Results.Run_Failed already covers it.
   Had_File_Error : Boolean := False;

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      case Active is
         when Console_Reporter =>
            Console_Report.On_Notice (N, Info);

         when Json_Reporter    =>
            Json_Report.On_Notice (N, Info);
      end case;
   end On_Notice;

   ---------------------------------------------------------------------
   --  Feature-level output; called from the driving loop directly,
   --  never from a notice (no notice covers a feature).
   ---------------------------------------------------------------------

   procedure Begin_Feature_Output (Path : String) is
   begin
      case Active is
         when Console_Reporter =>
            Console_Report.Begin_Feature (Path);

         when Json_Reporter    =>
            Json_Report.Begin_Feature;
      end case;
   end Begin_Feature_Output;

   procedure End_Feature_Output (Path : String) is
   begin
      case Active is
         when Console_Reporter =>
            null;

         when Json_Reporter    =>
            Json_Report.End_Feature (Path);
      end case;
   end End_Feature_Output;

   ---------------------------------------------------------------------
   --  Parse errors and the other typed, non-fatal file statuses.  Each
   --  is fabula's own rendering to choose: the reference interpreter's
   --  own wording either does not exist or does not survive a check.
   ---------------------------------------------------------------------

   Quote : constant Character := ''';

   function Quoted (Text : String) return String
   is (Quote & Text & Quote);

   --  One line of a file's own error.  The console report prints it;
   --  the JSON report leaves the file out, and its status still counts.
   procedure Put_File_Error (Message : String) is
   begin
      if Active = Console_Reporter then
         Console.Put_Line (Message, Console.Error);
      end if;
   end Put_File_Error;

   procedure Report_Parse_Error (Path : String; Load_Res : Files.Load_Result)
   is
      Raw   : constant String := Files.Line_Text (Load_Res);
      Token : constant String :=
        (if Load_Res.Refusal.Kind = Fabula.Parse.Tag_Line_Malformed
         then Fabula.Format.First_Bad_Tag_Token (Raw)
         else Fabula.Format.First_Token (Raw));
   begin
      Put_File_Error
        (Fabula.Format.Parse_Error_Text
           (Path,
            Load_Res.Line,
            Load_Res.Refusal.Kind,
            Load_Res.At_End,
            Token));
      Put_File_Error (Fabula.Format.Parse_Error_Trailer);
   end Report_Parse_Error;

   --  Every status but Found and Missing fails the run, even when its
   --  own message stays unprinted (-json).
   --  An unreadable directory fails too: silently passing a tree the
   --  walk could not enter would report success with scenarios unrun.
   function Discover_Status_Fails (Status : Files.Search_Status) return Boolean
   is (Status not in Files.Found | Files.Missing);

   Bad_Line_Lead       : constant String := "Bad line number in ";
   Too_Many_Lines_Lead : constant String := "Too many line selections in ";
   Path_Too_Long_Lead  : constant String := "Path too long: ";
   --  The oracle stays silent and exits 0 on a non-feature positional
   --  (probe-confirmed); fabula reports and fails instead, per its
   --  general refusal rule.
   Not_Feature_Lead    : constant String := "Error: Not a feature file ";
   Too_Many_Files_Text : constant String :=
     "Too many feature files discovered";
   Too_Deep_Lead       : constant String := "Directory nested too deep under ";
   --  The reference interpreter aborts on an unreadable directory, so no
   --  wording exists to copy; fabula names the failure and exits 1.
   Unreadable_Lead     : constant String :=
     "Error: Cannot read directory under ";

   --  Each discovery status's message, up to the argument it names; the
   --  whole message for Too_Many_Files, which names none.
   function Discover_Lead (Status : Files.Search_Status) return String
   is (case Status is
         when Files.Found | Files.Missing => "",
         when Files.Bad_Line_Number       => Bad_Line_Lead,
         when Files.Too_Many_Lines        => Too_Many_Lines_Lead,
         when Files.Path_Too_Long         => Path_Too_Long_Lead,
         when Files.Not_Feature           => Not_Feature_Lead,
         when Files.Too_Many_Files        => Too_Many_Files_Text,
         when Files.Too_Deep              => Too_Deep_Lead,
         when Files.Unreadable            => Unreadable_Lead);

   procedure Report_Discover_Status
     (Argument : String; Status : Files.Search_Status) is
   begin
      Had_File_Error := Had_File_Error or else Discover_Status_Fails (Status);
      case Status is
         when Files.Found | Files.Missing =>
            null;

         when Files.Too_Many_Files        =>
            Put_File_Error (Discover_Lead (Status));

         when others                      =>
            Put_File_Error (Discover_Lead (Status) & Quoted (Argument));
      end case;
   end Report_Discover_Status;

   ---------------------------------------------------------------------
   --  Discovery: every positional argument, then --exclude-file's
   --  suffix filter over what was found.
   ---------------------------------------------------------------------

   function Has_Suffix (Path, Suffix : String) return Boolean
   is (Suffix'Length <= Path'Length
       and then Ada.Strings.Fixed.Tail (Path, Suffix'Length) = Suffix);

   function Excluded (Path : String) return Boolean
   is (for some I in 1 .. Fabula.Cli.Excludes_Count (Cli_Opts) =>
         Has_Suffix (Path, Fabula.Cli.Exclude_Text (Cli_Opts, I)));

   procedure Apply_Excludes is
   begin
      Kept.Count := 0;
      for I in 1 .. Discovered.Count loop
         if not Excluded (Fabula.Frames.Value (Discovered.Files (I).Path)) then
            Kept.Count := Kept.Count + 1;
            Kept.Files (Kept.Count) := Discovered.Files (I);
         end if;
      end loop;
      Discovered := Kept;
   end Apply_Excludes;

   procedure Discover_All is
      Status : Files.Search_Status;
   begin
      Discovered.Count := 0;
      for I in 1 .. Fabula.Cli.Positionals_Count (Cli_Opts) loop
         Files.Discover
           (Fabula.Cli.Positional_Text (Cli_Opts, I), Discovered, Status);
         Report_Discover_Status
           (Fabula.Cli.Positional_Text (Cli_Opts, I), Status);
      end loop;
      Apply_Excludes;
   end Discover_All;

   ---------------------------------------------------------------------
   --  One feature file, loaded then driven.
   ---------------------------------------------------------------------

   procedure Run_Loaded_Feature (Path : String; Lines : Files.Line_Numbers) is
   begin
      Doc_Ref := Files.Document;
      Console_Report.Set_Document (Doc_Ref);
      Json_Report.Set_Document (Doc_Ref);
      Begin_Feature_Output (Path);
      Runner.Start_Feature (R, Doc_Ref, Path, Drive.Selection (Lines));
      Drive.Drive (R, Ctx, All_Ctx);
      End_Feature_Output (Path);
   end Run_Loaded_Feature;

   --  Empty and Unreadable print the oracle's own "File not found"
   --  wording (probe-confirmed) and stay exit-0; Too_Long counts as a
   --  parse error, never a silent exit 0.
   Too_Long_Lead  : constant String := "Error: A line is too long in ";
   Not_Found_Lead : constant String := "Error: File not found ";

   procedure Run_One_File (F : Files.Feature_File) is
      Path     : constant String := Fabula.Frames.Value (F.Path);
      Load_Res : Files.Load_Result;
   begin
      Files.Load (Path, Load_Res);
      case Load_Res.Status is
         when Files.Loaded                   =>
            Run_Loaded_Feature (Path, F.Lines);

         when Files.Refused                  =>
            Runner.Note_Parse_Error (R);
            Report_Parse_Error (Path, Load_Res);

         when Files.Too_Long                 =>
            Runner.Note_Parse_Error (R);
            Put_File_Error (Too_Long_Lead & Quoted (Path));

         when Files.Empty | Files.Unreadable =>
            Put_File_Error (Not_Found_Lead & Quoted (Path));
      end case;
   end Run_One_File;

   procedure Run_Discovered is
   begin
      for I in 1 .. Discovered.Count loop
         Run_One_File (Discovered.Files (I));
      end loop;
   end Run_Discovered;

   ---------------------------------------------------------------------
   --  Startup: argv, the modes, the tables and the -t expression.
   ---------------------------------------------------------------------

   --  The shell's own pre-classification of --report-json's value token
   --  (docs/report_wiring.md): the next token is the file unless it
   --  names a directory or contains ".feature".  Folded into one merged
   --  token so Fabula.Cli never needs file-system knowledge at all.
   function Names_Directory (Candidate : String) return Boolean is
   begin
      return
        Ada.Directories.Exists (Candidate)
        and then Ada.Directories.Kind (Candidate) = Ada.Directories.Directory;
   exception
      when others =>
         return False;
   end Names_Directory;

   function Is_Report_Json_Value (Candidate : String) return Boolean
   is (Ada.Strings.Fixed.Index (Candidate, Fabula.Cli.Feature_Suffix)
       not in Candidate'Range
       and then not Names_Directory (Candidate));

   --  Argument I is --report-json, and the argument after it its value.
   function Merges_Value (I : Positive) return Boolean
   is (Ada.Command_Line.Argument (I)
       = Fabula.Cli.Long_Of (Fabula.Cli.Report_Json_Flag)
       and then I < Ada.Command_Line.Argument_Count
       and then Is_Report_Json_Value (Ada.Command_Line.Argument (I + 1)));

   First_Argument : constant Positive := 1;
   No_Tokens      : constant Natural := 0;

   --  argv, each --report-json and its value merged into one token.
   function Build_Args return Fabula.Cli.Arg_List is
      Count       : constant Natural := Ada.Command_Line.Argument_Count;
      Result      : Fabula.Cli.Arg_List (1 .. Count);
      Token_Count : Natural := No_Tokens;
      Next        : Positive := First_Argument;
   begin
      while Next <= Count loop
         Token_Count := Token_Count + 1;
         if Merges_Value (Next) then
            Result (Token_Count) :=
              Fabula.Cli.To_Arg
                (Fabula.Cli.Report_Json_Prefix
                 & Ada.Command_Line.Argument (Next + 1));
            Next := Next + 1;
         else
            Result (Token_Count) :=
              Fabula.Cli.To_Arg (Ada.Command_Line.Argument (Next));
         end if;
         Next := Next + 1;
      end loop;
      return Result (1 .. Token_Count);
   end Build_Args;

   function Reporter_For (Target : Fabula.Cli.Report_Target) return Reporter
   is (if Target = Fabula.Cli.Console
       then Console_Reporter
       else Json_Reporter);

   --  The -t expression compiles into the filter only when it holds
   --  one: a blank expression means no filter.
   procedure Set_Filter (Tag_Expr : String) is
   begin
      if not Fabula.Tags.Blank (Tag_Expr) then
         Opts.Filter := Fabula.Tags.Compile (Tag_Expr);
         Opts.Has_Filter := Fabula.Tags.Valid (Opts.Filter);
      end if;
      Console_Report.Set_Filter (Opts.Has_Filter, Opts.Filter, Tag_Expr);
   end Set_Filter;

   procedure Set_Modes is
   begin
      Active := Reporter_For (Fabula.Cli.Report_Target_Of (Cli_Opts));
      Opts := (others => <>);
      Opts.Dry_Run := Fabula.Cli.Dry_Run (Cli_Opts);
      Opts.Continue_On_Failure := Fabula.Cli.Continue_On_Failure (Cli_Opts);
      Runner.Set_Names (Opts, Fabula.Cli.Names_Text (Cli_Opts));
      Set_Filter (Fabula.Cli.Tag_Expr_Text (Cli_Opts));
      Console_Report.Set_Log_Level (Fabula.Cli.Log_Level_Of (Cli_Opts));
      Console_Report.Set_Dry_Run (Opts.Dry_Run);
   end Set_Modes;

   --  Refused (the pattern or expression itself did not compile) and
   --  Unbound (it compiled, but no ">=" ever bound it to a step/hook
   --  kind) are different mistakes with different fixes; the startup
   --  report now names which one.
   function Bad_Row_Word (Status : Steps.Row_Status) return String
   is (case Status is
         when Steps.Row_Ok  => "",
         when Steps.Refused => "Refused",
         when Steps.Unbound => "Unbound");

   Bad_Tables_Header : constant String := "Bad step or hook definitions:";
   Step_Row_Word     : constant String := " step row";
   Hook_Row_Word     : constant String := " hook row";
   Text_Separator    : constant String := ": ";
   Position_Open     : constant String := " (position";
   Position_Close    : constant String := ")";

   procedure Report_Bad_Steps is
   begin
      for I in Step_Defs'Range loop
         if Steps.Step_Status (Step_Defs, I) /= Steps.Row_Ok then
            Console.Put_Line
              (Bad_Row_Word (Steps.Step_Status (Step_Defs, I))
               & Step_Row_Word
               & I'Image
               & Text_Separator
               & Quoted (Steps.Pattern_Text (Step_Defs, I)),
               Console.Error);
         end if;
      end loop;
   end Report_Bad_Steps;

   --  A tag expression's own compile failure has a position to point
   --  at; an unbound row's expression, if it has one, compiled fine, so
   --  there is nothing to point at.
   procedure Report_Bad_Hook_Row (I : Positive; Status : Steps.Row_Status) is
   begin
      Console.Put
        (Bad_Row_Word (Status)
         & Hook_Row_Word
         & I'Image
         & Text_Separator
         & Quoted (Steps.Tag_Expr_Text (Hook_Defs, I)),
         Console.Error);
      if Status = Steps.Refused then
         Console.Put
           (Position_Open
            & Fabula.Tags.Error (Steps.Tag_Expr (Hook_Defs, I))'Image
            & Position_Close,
            Console.Error);
      end if;
      Console.New_Line;
   end Report_Bad_Hook_Row;

   procedure Report_Bad_Hooks is
   begin
      for I in Hook_Defs'Range loop
         if Steps.Hook_Status (Hook_Defs, I) /= Steps.Row_Ok then
            Report_Bad_Hook_Row (I, Steps.Hook_Status (Hook_Defs, I));
         end if;
      end loop;
   end Report_Bad_Hooks;

   procedure Report_Bad_Tables is
   begin
      Console.Put_Line (Bad_Tables_Header, Console.Error);
      Report_Bad_Steps;
      Report_Bad_Hooks;
   end Report_Bad_Tables;

   Bad_Filter_Lead : constant String := "Bad tag expression at position";

   function Bad_Filter_Text return String
   is (Bad_Filter_Lead
       & Fabula.Tags.Error (Opts.Filter)'Image
       & Text_Separator
       & Quoted (Fabula.Cli.Tag_Expr_Text (Cli_Opts)));

   --  What the run does once argv is read, in the order the checks run:
   --  help wins over everything, then the first refusal.
   type Start_Kind is
     (Help_Asked, Arguments_Refused, Tables_Refused, Filter_Refused, Ready);

   --  Has_Filter says whether the -t expression compiled into a filter.
   function Start_Kind_Of
     (Parsed : Fabula.Cli.Options_Result; Has_Filter : Boolean)
      return Start_Kind
   is (if Fabula.Cli.Help (Parsed)
       then Help_Asked
       elsif Fabula.Cli.Refused (Parsed)
       then Arguments_Refused
       elsif not Runner.Tables_Valid
       then Tables_Refused
       elsif not Fabula.Tags.Blank (Fabula.Cli.Tag_Expr_Text (Parsed))
         and then not Has_Filter
       then Filter_Refused
       else Ready);

   --  A refusal at startup: its message, and a failing exit.
   procedure Refuse_Start (Message : String) is
   begin
      Console.Put_Line (Message, Console.Error);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Refuse_Start;

   ---------------------------------------------------------------------
   --  The whole run.
   ---------------------------------------------------------------------

   procedure Open_Report is
   begin
      case Active is
         when Console_Reporter =>
            null;

         when Json_Reporter    =>
            Json_Report.Open_Target
              (Fabula.Cli.Report_Target_Of (Cli_Opts),
               Fabula.Cli.Report_Json_File_Text (Cli_Opts));
      end case;
   end Open_Report;

   procedure Close_Report is
   begin
      case Active is
         when Console_Reporter =>
            Console_Report.Print_Trailer_And_Summaries (Runner.Counts_Of (R));

         when Json_Reporter    =>
            Json_Report.Close (Fabula.Cli.Report_Target_Of (Cli_Opts));
      end case;
   end Close_Report;

   function Exit_Status_Of return Ada.Command_Line.Exit_Status
   is (if Fabula.Results.Run_Failed (Runner.Counts_Of (R))
         or else Had_File_Error
       then Ada.Command_Line.Failure
       else Ada.Command_Line.Success);

   procedure Run_The_Whole_Thing is
   begin
      Discover_All;
      Open_Report;
      Runner.Start_Run (R, Opts);
      Drive.Drive (R, Ctx, All_Ctx);
      Run_Discovered;
      Runner.Finish_Run (R);
      Drive.Drive (R, Ctx, All_Ctx);
      Close_Report;
      Ada.Command_Line.Set_Exit_Status (Exit_Status_Of);
   end Run_The_Whole_Thing;

   procedure Run is
   begin
      Cli_Opts := Fabula.Cli.Parse (Build_Args);
      Set_Modes;
      case Start_Kind_Of (Cli_Opts, Opts.Has_Filter) is
         when Help_Asked        =>
            Console.Put_Line (Fabula.Cli.Help_Text);
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);

         when Arguments_Refused =>
            Refuse_Start
              (Fabula.Cli.Refusal_Text (Fabula.Cli.Refusal_Of (Cli_Opts)));

         when Tables_Refused    =>
            Report_Bad_Tables;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

         when Filter_Refused    =>
            Refuse_Start (Bad_Filter_Text);

         when Ready             =>
            Run_The_Whole_Thing;
      end case;
   end Run;

end Fabula.Shell.Program;
