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
with Fabula.Shell.Reports;
with Fabula.Tags;

package body Fabula.Shell.Program
  with SPARK_Mode => Off
is

   use type Fabula.Results.Status;
   use type Ada.Directories.File_Kind;

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

   Discovered : Fabula.Shell.Files.File_List;
   Kept       : Fabula.Shell.Files.File_List;

   Json_Active : Boolean := False;

   --  state.md entry 30: a refusal never lets the run exit 0.  Set
   --  for every discovery status but Found and Missing (the oracle's
   --  observed exit-0 cases); Too_Long needs no flag of its own --
   --  it counts as a parse error instead, so
   --  Fabula.Results.Run_Failed already covers it.
   Had_File_Error : Boolean := False;

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      if Json_Active then
         Json_Report.On_Notice (N, Info);
      else
         Console_Report.On_Notice (N, Info);
      end if;
   end On_Notice;

   function Is_Blank (S : String) return Boolean is
   begin
      for Ch of S loop
         if Ch /= ' '
           and then Ch /= ASCII.HT
           and then Ch /= ASCII.CR
           and then Ch /= ASCII.LF
           and then Ch /= ASCII.VT
           and then Ch /= ASCII.FF
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Blank;

   ---------------------------------------------------------------------
   --  Feature-level output, dispatched by mode; called from the driving
   --  loop directly, never from a notice (no notice covers a feature).
   ---------------------------------------------------------------------

   procedure Begin_Feature_Output (Path : String) is
   begin
      if Json_Active then
         Json_Report.Begin_Feature;
      else
         Console_Report.Begin_Feature (Path);
      end if;
   end Begin_Feature_Output;

   procedure End_Feature_Output (Path : String) is
   begin
      if Json_Active then
         Json_Report.End_Feature (Path);
      end if;
   end End_Feature_Output;

   ---------------------------------------------------------------------
   --  Parse errors and the other typed, non-fatal file statuses.  Each
   --  is fabula's own rendering to choose: the reference interpreter's
   --  own wording either does not exist or does not survive a check.
   ---------------------------------------------------------------------

   procedure Report_Parse_Error
     (Path : String; Load_Res : Fabula.Shell.Files.Load_Result)
   is
      use type Fabula.Parse.Error_Kind;
      Raw   : constant String := Fabula.Shell.Files.Line_Text (Load_Res);
      Token : constant String :=
        (if Load_Res.Refusal.Kind = Fabula.Parse.Tag_Line_Malformed
         then Fabula.Format.First_Bad_Tag_Token (Raw)
         else Fabula.Format.First_Token (Raw));
   begin
      if Json_Active then
         return;   --  a file that failed to parse gets no JSON entry

      end if;
      Fabula.Shell.Console.Put
        (Fabula.Format.Parse_Error_Text
           (Path,
            Load_Res.Line,
            Load_Res.Refusal.Kind,
            Load_Res.At_End,
            Token),
         Fabula.Shell.Console.Error);
      Fabula.Shell.Console.New_Line;
      Fabula.Shell.Console.Put
        (Fabula.Format.Parse_Error_Trailer, Fabula.Shell.Console.Error);
      Fabula.Shell.Console.New_Line;
   end Report_Parse_Error;

   --  state.md entry 30: every status but Found and Missing fails
   --  the run, even when its own message stays unprinted (-json).
   --  An unreadable directory fails too: silently passing a tree the
   --  walk could not enter would report success with scenarios unrun.
   function Discover_Status_Fails
     (Status : Fabula.Shell.Files.Search_Status) return Boolean
   is (Status
       not in Fabula.Shell.Files.Found
            | Fabula.Shell.Files.Missing);

   procedure Report_Discover_Status
     (Argument : String; Status : Fabula.Shell.Files.Search_Status)
   is
      use type Fabula.Shell.Files.Search_Status;
      Message : constant String :=
        (case Status is
           when Fabula.Shell.Files.Found | Fabula.Shell.Files.Missing => "",
           when Fabula.Shell.Files.Bad_Line_Number                    =>
             "Bad line number in '" & Argument & "'",
           when Fabula.Shell.Files.Too_Many_Lines                     =>
             "Too many line selections in '" & Argument & "'",
           when Fabula.Shell.Files.Path_Too_Long                      =>
             "Path too long: '" & Argument & "'",
           --  state.md entry 30: the oracle stays silent and exits 0 on a
           --  non-feature positional (probe-confirmed); fabula reports and
           --  fails instead, per the review's general refusal rule.
           when Fabula.Shell.Files.Not_Feature                        =>
             "Error: Not a feature file '" & Argument & "'",
           when Fabula.Shell.Files.Too_Many_Files                     =>
             "Too many feature files discovered",
           when Fabula.Shell.Files.Too_Deep                           =>
             "Directory nested too deep under '" & Argument & "'",
           --  The reference interpreter aborts on an unreadable
           --  directory, so no wording exists to copy; fabula names
           --  the failure and exits 1 (state.md entry 30).
           when Fabula.Shell.Files.Unreadable                         =>
             "Error: Cannot read directory under '" & Argument & "'");
   begin
      if Discover_Status_Fails (Status) then
         Had_File_Error := True;
      end if;
      if Json_Active
        or else Status in Fabula.Shell.Files.Found | Fabula.Shell.Files.Missing
      then
         return;
      end if;
      Fabula.Shell.Console.Put (Message, Fabula.Shell.Console.Error);
      Fabula.Shell.Console.New_Line;
   end Report_Discover_Status;

   procedure Report_Load_Status
     (Path : String; Status : Fabula.Shell.Files.Load_Status)
   is
      use type Fabula.Shell.Files.Load_Status;
      --  state.md entry 30: Empty and Unreadable print the oracle's own
      --  "File not found" wording (probe-confirmed) and stay exit-0;
      --  Too_Long is a parse error instead (Run_One_File), never here.
      Message : constant String :=
        (case Status is
           when Fabula.Shell.Files.Loaded                                => "",
           when Fabula.Shell.Files.Refused                               => "",
           when Fabula.Shell.Files.Too_Long                              =>
             "Error: A line is too long in '" & Path & "'",
           when Fabula.Shell.Files.Empty | Fabula.Shell.Files.Unreadable =>
             "Error: File not found '" & Path & "'");
   begin
      if Json_Active
        or else Status = Fabula.Shell.Files.Loaded
        or else Status = Fabula.Shell.Files.Refused
      then
         return;
      end if;
      Fabula.Shell.Console.Put (Message, Fabula.Shell.Console.Error);
      Fabula.Shell.Console.New_Line;
   end Report_Load_Status;

   ---------------------------------------------------------------------
   --  Discovery: every positional argument, then --exclude-file's
   --  suffix filter over what was found.
   ---------------------------------------------------------------------

   function Has_Suffix (Path, Suffix : String) return Boolean is
   begin
      if Suffix'Length > Path'Length then
         return False;
      end if;
      return Ada.Strings.Fixed.Tail (Path, Suffix'Length) = Suffix;
   end Has_Suffix;

   function Excluded (Path : String) return Boolean is
   begin
      for I in 1 .. Fabula.Cli.Excludes_Count (Cli_Opts) loop
         if Has_Suffix (Path, Fabula.Cli.Exclude_Text (Cli_Opts, I)) then
            return True;
         end if;
      end loop;
      return False;
   end Excluded;

   procedure Apply_Excludes is
   begin
      if Fabula.Cli.Excludes_Count (Cli_Opts) = 0 then
         return;
      end if;
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
      Status : Fabula.Shell.Files.Search_Status;
   begin
      Discovered.Count := 0;
      for I in 1 .. Fabula.Cli.Positionals_Count (Cli_Opts) loop
         Fabula.Shell.Files.Discover
           (Fabula.Cli.Positional_Text (Cli_Opts, I), Discovered, Status);
         Report_Discover_Status
           (Fabula.Cli.Positional_Text (Cli_Opts, I), Status);
      end loop;
      Apply_Excludes;
   end Discover_All;

   ---------------------------------------------------------------------
   --  One feature file, loaded then driven.
   ---------------------------------------------------------------------

   procedure Run_Loaded_Feature
     (Path : String; Lines : Fabula.Shell.Files.Line_Numbers) is
   begin
      Doc_Ref := Fabula.Shell.Files.Document;
      Console_Report.Set_Document (Doc_Ref);
      Json_Report.Set_Document (Doc_Ref);
      Begin_Feature_Output (Path);
      Runner.Start_Feature (R, Doc_Ref, Path, Drive.Selection (Lines));
      Drive.Drive (R, Ctx, All_Ctx);
      End_Feature_Output (Path);
   end Run_Loaded_Feature;

   procedure Run_One_File (F : Fabula.Shell.Files.Feature_File) is
      use type Fabula.Shell.Files.Load_Status;
      Path     : constant String := Fabula.Frames.Value (F.Path);
      Load_Res : Fabula.Shell.Files.Load_Result;
   begin
      Fabula.Shell.Files.Load (Path, Load_Res);
      if Load_Res.Status = Fabula.Shell.Files.Loaded then
         Run_Loaded_Feature (Path, F.Lines);
      elsif Load_Res.Status = Fabula.Shell.Files.Refused then
         Runner.Note_Parse_Error (R);
         Report_Parse_Error (Path, Load_Res);
      else
         --  state.md entry 30: Too_Long counts as a parse error (never a
         --  silent exit 0); Empty/Unreadable stay exit-0, no count.
         if Load_Res.Status = Fabula.Shell.Files.Too_Long then
            Runner.Note_Parse_Error (R);
         end if;
         Report_Load_Status (Path, Load_Res.Status);
      end if;
   end Run_One_File;

   ---------------------------------------------------------------------
   --  Startup: the tables, the -t expression, argv, and the report
   --  target.
   ---------------------------------------------------------------------

   --  state.md entry 30 (review item 10): Refused (the pattern or
   --  expression itself did not compile) and Unbound (it compiled, but
   --  no ">=" ever bound it to a step/hook kind) are different mistakes
   --  with different fixes; the startup report now names which one.
   function Bad_Row_Word (Status : Steps.Row_Status) return String
   is (case Status is
         when Steps.Row_Ok  => "",
         when Steps.Refused => "Refused",
         when Steps.Unbound => "Unbound");

   procedure Report_Bad_Steps is
   begin
      for I in Step_Defs'Range loop
         if Steps.Step_Status (Step_Defs, I) /= Steps.Row_Ok then
            Fabula.Shell.Console.Put
              (Bad_Row_Word (Steps.Step_Status (Step_Defs, I))
               & " step row"
               & I'Image
               & ": '"
               & Steps.Pattern_Text (Step_Defs, I)
               & "'",
               Fabula.Shell.Console.Error);
            Fabula.Shell.Console.New_Line;
         end if;
      end loop;
   end Report_Bad_Steps;

   --  A tag expression's own compile failure has a position to point
   --  at; an unbound row's expression, if it has one, compiled fine, so
   --  there is nothing to point at.
   procedure Report_Bad_Hook_Row (I : Positive; Status : Steps.Row_Status) is
   begin
      Fabula.Shell.Console.Put
        (Bad_Row_Word (Status)
         & " hook row"
         & I'Image
         & ": '"
         & Steps.Tag_Expr_Text (Hook_Defs, I)
         & "'",
         Fabula.Shell.Console.Error);
      if Status = Steps.Refused then
         Fabula.Shell.Console.Put
           (" (position"
            & Fabula.Tags.Error (Steps.Tag_Expr (Hook_Defs, I))'Image
            & ")",
            Fabula.Shell.Console.Error);
      end if;
      Fabula.Shell.Console.New_Line;
   end Report_Bad_Hook_Row;

   procedure Report_Bad_Hooks is
      Status : Steps.Row_Status;
   begin
      for I in Hook_Defs'Range loop
         Status := Steps.Hook_Status (Hook_Defs, I);
         if Status /= Steps.Row_Ok then
            Report_Bad_Hook_Row (I, Status);
         end if;
      end loop;
   end Report_Bad_Hooks;

   procedure Report_Bad_Tables is
   begin
      Fabula.Shell.Console.Put
        ("Bad step or hook definitions:", Fabula.Shell.Console.Error);
      Fabula.Shell.Console.New_Line;
      Report_Bad_Steps;
      Report_Bad_Hooks;
   end Report_Bad_Tables;

   procedure Compile_Tag_Filter (Ok : out Boolean) is
      Text : constant String := Fabula.Cli.Tag_Expr_Text (Cli_Opts);
   begin
      Ok := True;
      Opts.Has_Filter := False;
      if Is_Blank (Text) then
         return;
      end if;
      Opts.Filter := Fabula.Tags.Compile (Text);
      if Fabula.Tags.Valid (Opts.Filter) then
         Opts.Has_Filter := True;
      else
         Ok := False;
         Fabula.Shell.Console.Put
           ("Bad tag expression at position"
            & Fabula.Tags.Error (Opts.Filter)'Image
            & ": '"
            & Text
            & "'",
            Fabula.Shell.Console.Error);
         Fabula.Shell.Console.New_Line;
      end if;
   end Compile_Tag_Filter;

   procedure Set_Modes is
   begin
      Json_Active := Fabula.Cli.Report_Json (Cli_Opts);
      Opts := (others => <>);
      Opts.Dry_Run := Fabula.Cli.Dry_Run (Cli_Opts);
      Opts.Continue_On_Failure := Fabula.Cli.Continue_On_Failure (Cli_Opts);
      Runner.Set_Names (Opts, Fabula.Cli.Names_Text (Cli_Opts));
      Console_Report.Set_Quiet (Fabula.Cli.Quiet (Cli_Opts));
      Console_Report.Set_Verbose (Fabula.Cli.Verbose (Cli_Opts));
      Console_Report.Set_Dry_Run (Opts.Dry_Run);
   end Set_Modes;

   --  The shell's own pre-classification of --report-json's value token
   --  (docs/report_wiring.md): the next token is the file unless it
   --  names a directory or contains ".feature".  Folded into one merged
   --  token so Fabula.Cli never needs file-system knowledge at all.
   function Is_Report_Json_Value (Candidate : String) return Boolean is
      Is_Dir : Boolean := False;
   begin
      if Ada.Strings.Fixed.Index (Candidate, ".feature") /= 0 then
         return False;
      end if;
      begin
         Is_Dir :=
           Ada.Directories.Exists (Candidate)
           and then Ada.Directories.Kind (Candidate)
                    = Ada.Directories.Directory;
      exception
         when others =>
            Is_Dir := False;
      end;
      return not Is_Dir;
   end Is_Report_Json_Value;

   function Build_Args return Fabula.Cli.Arg_List is
      Count  : constant Natural := Ada.Command_Line.Argument_Count;
      Result : Fabula.Cli.Arg_List (1 .. Count);
      Out_I  : Positive := 1;
      In_I   : Positive := 1;
   begin
      while In_I <= Count loop
         declare
            Token : constant String := Ada.Command_Line.Argument (In_I);
         begin
            if Token = "--report-json"
              and then In_I < Count
              and then Is_Report_Json_Value
                         (Ada.Command_Line.Argument (In_I + 1))
            then
               Fabula.Cli.Set
                 (Result (Out_I),
                  "--report-json=" & Ada.Command_Line.Argument (In_I + 1));
               In_I := In_I + 2;
            else
               Fabula.Cli.Set (Result (Out_I), Token);
               In_I := In_I + 1;
            end if;
         end;
         Out_I := Out_I + 1;
      end loop;
      return Result (1 .. Out_I - 1);
   end Build_Args;

   ---------------------------------------------------------------------
   --  The whole run.
   ---------------------------------------------------------------------

   procedure Run_The_Whole_Thing is
      Status : Fabula.Shell.Reports.Status;
   begin
      Discover_All;
      if Json_Active then
         Json_Report.Open_Target
           (Fabula.Cli.Report_Json_File_Text (Cli_Opts),
            Fabula.Cli.Report_Json_Has_File (Cli_Opts),
            Status);
      end if;
      Runner.Start_Run (R, Opts);
      Drive.Drive (R, Ctx, All_Ctx);
      for I in 1 .. Discovered.Count loop
         Run_One_File (Discovered.Files (I));
      end loop;
      Runner.Finish_Run (R);
      Drive.Drive (R, Ctx, All_Ctx);
      if Json_Active then
         Json_Report.Close (Fabula.Cli.Report_Json_Has_File (Cli_Opts));
      else
         Console_Report.Print_Trailer_And_Summaries (Runner.Counts_Of (R));
      end if;
      Ada.Command_Line.Set_Exit_Status
        ((if Fabula.Results.Run_Failed (Runner.Counts_Of (R))
            or else Had_File_Error
          then Ada.Command_Line.Failure
          else Ada.Command_Line.Success));
   end Run_The_Whole_Thing;

   procedure Run is
      Args_List : constant Fabula.Cli.Arg_List := Build_Args;
      Filter_Ok : Boolean;
   begin
      Fabula.Cli.Parse (Args_List, Cli_Opts);
      if Fabula.Cli.Help (Cli_Opts) then
         Fabula.Shell.Console.Put (Fabula.Cli.Help_Text);
         Fabula.Shell.Console.New_Line;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
         return;
      end if;
      if Fabula.Cli.Refused (Cli_Opts) then
         Fabula.Shell.Console.Put
           (Fabula.Cli.Refusal_Text (Fabula.Cli.Refusal_Of (Cli_Opts)),
            Fabula.Shell.Console.Error);
         Fabula.Shell.Console.New_Line;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Set_Modes;
      if not Runner.Tables_Valid then
         Report_Bad_Tables;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Compile_Tag_Filter (Filter_Ok);
      Console_Report.Set_Filter
        (Opts.Has_Filter, Opts.Filter, Fabula.Cli.Tag_Expr_Text (Cli_Opts));
      if not Filter_Ok then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Run_The_Whole_Thing;
   end Run;

end Fabula.Shell.Program;
