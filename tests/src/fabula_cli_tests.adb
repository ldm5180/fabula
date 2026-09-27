with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Cli; use Fabula.Cli;
with Fabula.Limits;

with Fabula_Fixtures; use Fabula_Fixtures;

package body Fabula_Cli_Tests is

   use AUnit.Test_Cases.Registration;

   --  One Arg_List built from a token per element, matching Main's own
   --  argv-to-Arg_List conversion.
   function Args (Tokens : Lines) return Arg_List is
      Result : Arg_List (1 .. Tokens'Length);
   begin
      for I in Tokens'Range loop
         Result (I - Tokens'First + 1) := To_Arg (To_String (Tokens (I)));
      end loop;
      return Result;
   end Args;

   function Parsed (Tokens : Lines) return Options_Result
   is (Parse (Args (Tokens)));

   ---------------------------------------------------------------------
   --  Help triggers.
   ---------------------------------------------------------------------

   procedure Test_No_Args (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty : constant Arg_List (1 .. 0) := [others => <>];
      R     : constant Options_Result := Parse (Empty);
   begin
      Assert (Help (R), "no arguments means help");
      Assert (not Refused (R), "not a refusal");
   end Test_No_Args;

   procedure Test_Help_Flags (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Help (Parsed ([+"-h"])), "-h");
      Assert (Help (Parsed ([+"--help"])), "--help");
      Assert (not Help (Parsed ([+"a.feature"])), "a plain run asks no help");
      Assert
        (Help (Parsed ([+"--bogus", +"-t", +"-h"])),
         "-h anywhere wins, even as a value after a refusal");
   end Test_Help_Flags;

   --  The help screen, byte for byte.
   procedure Test_Help_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      LF   : constant Character := ASCII.LF;
      Want : constant String :=
        "fabula: a Cucumber/Gherkin test runner"
        & LF
        & "usage: <binary> [<file>.feature | <file>.feature:LINE... | <dir>]... "
        & "[options]"
        & LF
        & LF
        & "options:"
        & LF
        & "  -h, --help                   print this help and exit"
        & LF
        & "  -q, --quiet                  print only errors and the summary"
        & LF
        & "  -v, --verbose                print extra detail as a scenario runs"
        & LF
        & "  -d, --dry-run                check steps are defined; run none "
        & "of them"
        & LF
        & "  -c, --continue-on-failure    keep running a scenario's steps "
        & "after one fails"
        & LF
        & "  -t, --tags <EXPRESSION>      run only scenarios the tag "
        & "expression selects"
        & LF
        & "  -n, --name <PATTERN>         run only scenarios whose name "
        & "matches; ':' separates"
        & LF
        & "                               several patterns, '*' and '?' wildcard"
        & LF
        & "  --exclude-file <SUFFIX>      skip a discovered file whose path "
        & "ends in SUFFIX"
        & LF
        & "  --report-json [FILE]         write a JSON report to FILE, or to "
        & "stdout";
   begin
      Assert (Help_Text = Want, "the help screen: " & LF & Help_Text);
   end Test_Help_Text;

   ---------------------------------------------------------------------
   --  The flag table: one spelling per flag, one kind per token.
   ---------------------------------------------------------------------

   procedure Test_Spellings (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Short_Of (Help_Flag) = "-h", "-h");
      Assert (Long_Of (Help_Flag) = "--help", "--help");
      Assert (Short_Of (Name_Flag) = "-n", "-n");
      Assert (Long_Of (Continue_Flag) = "--continue-on-failure", "longest");
      Assert
        (Short_Of (Exclude_Flag) = "", "--exclude-file has no short form");
      Assert (Long_Of (Exclude_Flag) = "--exclude-file", "--exclude-file");
      Assert (Short_Of (Report_Json_Flag) = "", "nor has --report-json");
      Assert (Long_Of (Report_Json_Flag) = "--report-json", "--report-json");
      Assert (Report_Json_Prefix = "--report-json=", "the merged form");
      Assert (Feature_Suffix = ".feature", "a feature file's suffix");
   end Test_Spellings;

   procedure Test_Classify (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for F in Spelled_Flag loop
         Assert (Classify (Long_Of (F)) = F, "long " & F'Image);
         if Short_Of (F) /= "" then
            Assert (Classify (Short_Of (F)) = F, "short " & F'Image);
         end if;
      end loop;
      Assert (Classify ("--report-json=a") = Report_File_Flag, "merged");
      Assert (Classify ("--report-json=") = Report_File_Flag, "merged empty");
      Assert (Classify ("--help=") = Unknown_Flag, "no other merged form");
      Assert (Classify ("-") = Unknown_Flag, "a bare dash");
      Assert (Classify ("-hq") = Unknown_Flag, "no bundled flags");
      Assert (Classify ("a.feature") = Not_A_Flag, "a path");
      Assert (Classify ("") = Not_A_Flag, "an empty token");
   end Test_Classify;

   ---------------------------------------------------------------------
   --  Every boolean flag, short and long.
   ---------------------------------------------------------------------

   procedure Test_Boolean_Flags (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Log_Level_Of (Parsed ([+"a.feature"])) = Normal, "no -q, no -v");
      Assert (Log_Level_Of (Parsed ([+"-q"])) = Quiet, "-q");
      Assert (Log_Level_Of (Parsed ([+"--quiet"])) = Quiet, "--quiet");
      Assert (Log_Level_Of (Parsed ([+"-v"])) = Verbose, "-v");
      Assert (Log_Level_Of (Parsed ([+"--verbose"])) = Verbose, "--verbose");
      Assert (Dry_Run (Parsed ([+"-d"])), "-d");
      Assert (Dry_Run (Parsed ([+"--dry-run"])), "--dry-run");
      Assert (Continue_On_Failure (Parsed ([+"-c"])), "-c");
      Assert
        (Continue_On_Failure (Parsed ([+"--continue-on-failure"])),
         "--continue-on-failure");
   end Test_Boolean_Flags;

   procedure Test_Combined_Flags (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result :=
        Parsed ([+"-q", +"-v", +"-d", +"-c", +"a.feature"]);
   begin
      Assert (Log_Level_Of (R) = Verbose, "-v wins over an earlier -q");
      Assert
        (Log_Level_Of (Parsed ([+"-v", +"-q"])) = Verbose,
         "-v wins over a later -q too");
      Assert (Dry_Run (R) and then Continue_On_Failure (R), "and the rest");
      Assert (Positionals_Count (R) = 1, "the file still lands");
      Assert (Positional_Text (R, 1) = "a.feature", "as itself");
   end Test_Combined_Flags;

   ---------------------------------------------------------------------
   --  Value-taking flags, short and long.
   ---------------------------------------------------------------------

   procedure Test_Tag_Expr (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Tag_Expr_Text (Parsed ([+"-t", +"@a"])) = "@a", "-t");
      Assert
        (Tag_Expr_Text (Parsed ([+"--tags", +"@a or @b"])) = "@a or @b",
         "--tags");
      Assert (Tag_Expr_Text (Parsed ([+"a.feature"])) = "", "no -t at all");
   end Test_Tag_Expr;

   procedure Test_Names (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Names_Text (Parsed ([+"-n", +"a*:b?"])) = "a*:b?", "-n");
      Assert (Names_Text (Parsed ([+"--name", +"a*"])) = "a*", "--name");
   end Test_Names;

   procedure Test_Exclude (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Options_Result :=
        Parsed
          ([+"--exclude-file",
            +"skip.feature",
            +"--exclude-file",
            +"also.feature"]);
   begin
      Assert (Excludes_Count (R) = 2, "two --exclude-file flags accumulate");
      Assert (Exclude_Text (R, 1) = "skip.feature", "the first");
      Assert (Exclude_Text (R, 2) = "also.feature", "the second");
   end Test_Exclude;

   --  Whatever follows a value-taking flag is its value, even a token
   --  that itself looks like a flag -- the frozen matrix takes it
   --  unconditionally.
   procedure Test_Value_Takes_Anything
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed ([+"-t", +"-q"]);
   begin
      Assert (Tag_Expr_Text (R) = "-q", "the next token, whatever it is");
      Assert (Log_Level_Of (R) = Normal, "it never reached the flag dispatch");
   end Test_Value_Takes_Anything;

   ---------------------------------------------------------------------
   --  --report-json: the shell's own pre-classification, folded into
   --  one token (docs/report_wiring.md).
   ---------------------------------------------------------------------

   procedure Test_Report_Json_Console
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed ([+"--report-json"]);
   begin
      Assert (Report_Target_Of (R) = Json_Stdout, "no file: stdout");
      Assert
        (Report_Target_Of (Parsed ([+"a.feature"])) = Console,
         "no flag: the console report");
   end Test_Report_Json_Console;

   procedure Test_Report_Json_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result :=
        Parsed ([+"--report-json=out.json", +"a.feature"]);
   begin
      Assert (Report_Target_Of (R) = Json_File, "a merged value is a file");
      Assert (Report_Json_File_Text (R) = "out.json", "its name");
      Assert
        (Positionals_Count (R) = 1
         and then Positional_Text (R, 1) = "a.feature",
         "the merged token consumes no other argument");
      Assert
        (Report_Target_Of (Parsed ([+"--report-json=a", +"--report-json"]))
         = Json_File,
         "a later bare flag keeps the file");
      Assert
        (Report_Json_File_Text
           (Parsed ([+"--report-json=a", +"--report-json=b"]))
         = "b",
         "the last file wins");
      Assert
        (Report_Target_Of (Parsed ([+"--report-json="])) = Json_File
         and then Report_Json_File_Text (Parsed ([+"--report-json="])) = "",
         "an empty merged value is still the file form");
   end Test_Report_Json_File;

   ---------------------------------------------------------------------
   --  Positionals.
   ---------------------------------------------------------------------

   procedure Test_Positionals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Options_Result :=
        Parsed ([+"a.feature:4", +"dir", +"b.feature"]);
   begin
      Assert (Positionals_Count (R) = 3, "every positional, suffixes kept");
      Assert (Positional_Text (R, 1) = "a.feature:4", "Cli does not split it");
      Assert (Positional_Text (R, 2) = "dir", "a bare directory");
      Assert (Positional_Text (R, 3) = "b.feature", "the last one");
   end Test_Positionals;

   ---------------------------------------------------------------------
   --  Refusals: an unknown flag, a missing value, each naming its token.
   --  Each test asserts Refused itself before it reads the refusal, so
   --  a Refused that misses a kind fails in every build mode, not only
   --  where Refusal_Of's precondition is checked.
   ---------------------------------------------------------------------

   procedure Assert_Refused
     (R : Options_Result; Kind : Refusal_Kind; What : String) is
   begin
      Assert (Refused (R), What & ": refused");
      Assert
        (Kind_Of (Refusal_Of (R)) = Kind,
         What
         & ": as "
         & Kind'Image
         & ", got "
         & Kind_Of (Refusal_Of (R))'Image);
   end Assert_Refused;

   procedure Test_Unknown_Option (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed ([+"a.feature", +"--bogus"]);
   begin
      Assert_Refused (R, Unknown_Option, "an unrecognized '-' token");
      Assert (Token_Of (Refusal_Of (R)) = "--bogus", "naming the token");
      Assert
        (Refusal_Text (Refusal_Of (R)) = "Unknown option: '--bogus'",
         "fabula's own wording, got """
         & Refusal_Text (Refusal_Of (R))
         & """");
   end Test_Unknown_Option;

   procedure Test_Missing_Value (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Refused (Parsed ([+"-t"]), Missing_Value, "-t alone");
      Assert_Refused (Parsed ([+"-n"]), Missing_Value, "-n alone");
      Assert_Refused
        (Parsed ([+"--exclude-file"]), Missing_Value, "--exclude-file alone");
      Assert
        (Refusal_Text (Refusal_Of (Parsed ([+"-t"])))
         = "Missing value for '-t'",
         "names the flag itself");
   end Test_Missing_Value;

   --  The first refusal sticks; scanning stops there.
   procedure Test_First_Refusal_Sticks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result :=
        Parsed ([+"--first-bogus", +"--second-bogus"]);
   begin
      Assert_Refused (R, Unknown_Option, "two unknown flags");
      Assert
        (Token_Of (Refusal_Of (R)) = "--first-bogus", "the earlier token");
   end Test_First_Refusal_Sticks;

   ---------------------------------------------------------------------
   --  Bounds: each refuses before the caller could misuse the value.
   ---------------------------------------------------------------------

   function Filled (N : Positive; Ch : Character := 'x') return String
   is (String'(1 .. N => Ch));

   procedure Test_Tag_Expr_Bound (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Longest : constant String := Filled (Fabula.Limits.Max_Tag_Expr_Length);
      Over    : constant String := Longest & "x";
      R       : constant Options_Result := Parsed ([+"-t", +Over]);
   begin
      Assert (not Refused (Parsed ([+"-t", +Longest])), "the longest fits");
      Assert_Refused (R, Tag_Expression_Too_Long, "one character more");
      Assert (Token_Of (Refusal_Of (R)) = Over, "naming the over-long text");
      Assert
        (Refusal_Text (Refusal_Of (R))
         = "Tag expression too long: '" & Over & "'",
         "wording names the text: " & Refusal_Text (Refusal_Of (R)));
   end Test_Tag_Expr_Bound;

   procedure Test_Names_Bound (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Over : constant String :=
        Filled (Fabula.Limits.Max_Name_Filter_Length + 1);
      R    : constant Options_Result := Parsed ([+"-n", +Over]);
   begin
      Assert_Refused
        (R,
         Name_Patterns_Too_Long,
         "one character past Max_Name_Filter_Length");
      Assert (Token_Of (Refusal_Of (R)) = Over, "naming the over-long text");
      Assert
        (Refusal_Text (Refusal_Of (R))
         = "-n patterns too long: '" & Over & "'",
         "wording names the text: " & Refusal_Text (Refusal_Of (R)));
   end Test_Names_Bound;

   procedure Test_Report_Json_Path_Bound
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Over : constant String := Filled (Fabula.Limits.Max_Path_Length + 1);
      R    : constant Options_Result := Parsed ([+("--report-json=" & Over)]);
   begin
      Assert_Refused
        (R, Report_Json_Path_Too_Long, "one character past Max_Path_Length");
      Assert (Token_Of (Refusal_Of (R)) = Over, "naming the over-long text");
      Assert
        (Refusal_Text (Refusal_Of (R))
         = "--report-json path too long: '" & Over & "'",
         "wording names the text: " & Refusal_Text (Refusal_Of (R)));
   end Test_Report_Json_Path_Bound;

   procedure Test_Exclude_Path_Bound
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Over : constant String := Filled (Fabula.Limits.Max_Path_Length + 1);
      R    : constant Options_Result := Parsed ([+"--exclude-file", +Over]);
   begin
      Assert_Refused
        (R, Exclude_Path_Too_Long, "one character past Max_Path_Length");
      Assert (Token_Of (Refusal_Of (R)) = Over, "naming the over-long text");
      Assert
        (Refusal_Text (Refusal_Of (R))
         = "--exclude-file path too long: '" & Over & "'",
         "wording names the text: " & Refusal_Text (Refusal_Of (R)));
   end Test_Exclude_Path_Bound;

   --  One argv token per exclude, one past the shipped capacity.
   function Too_Many_Exclude_Tokens return Lines is
      Result : Lines (1 .. 2 * (Fabula.Limits.Max_Cli_Excludes + 1));
   begin
      for I in 1 .. Fabula.Limits.Max_Cli_Excludes + 1 loop
         Result (2 * I - 1) := +"--exclude-file";
         Result (2 * I) := +("f" & I'Image & ".feature");
      end loop;
      return Result;
   end Too_Many_Exclude_Tokens;

   procedure Test_Too_Many_Excludes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed (Too_Many_Exclude_Tokens);
   begin
      Assert_Refused
        (R, Too_Many_Excludes, "one --exclude-file past Max_Cli_Excludes");
      Assert
        (Refusal_Text (Refusal_Of (R)) = "Too many --exclude-file flags",
         "wording: " & Refusal_Text (Refusal_Of (R)));
   end Test_Too_Many_Excludes;

   function Too_Many_Positional_Tokens return Lines is
      Result : Lines (1 .. Fabula.Limits.Max_Cli_Positionals + 1);
   begin
      for I in Result'Range loop
         Result (I) := +("f" & I'Image & ".feature");
      end loop;
      return Result;
   end Too_Many_Positional_Tokens;

   procedure Test_Too_Many_Positionals
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed (Too_Many_Positional_Tokens);
   begin
      Assert_Refused
        (R,
         Too_Many_Positionals,
         "one file argument past Max_Cli_Positionals");
      Assert
        (Refusal_Text (Refusal_Of (R))
         = "Too many file or directory " & "arguments",
         "wording: " & Refusal_Text (Refusal_Of (R)));
   end Test_Too_Many_Positionals;

   --  One argv per refusal kind, and one that refuses nothing: Refused
   --  holds exactly when the kind is not None.
   procedure Test_Refused_Is_Kind (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path_Over : constant String :=
        Filled (Fabula.Limits.Max_Path_Length + 1);

      function Argv (Kind : Refusal_Kind) return Options_Result
      is (case Kind is
            when None                      => Parsed ([+"a.feature"]),
            when Unknown_Option            => Parsed ([+"--bogus"]),
            when Missing_Value             => Parsed ([+"-t"]),
            when Tag_Expression_Too_Long   =>
              Parsed
                ([+"-t", +Filled (Fabula.Limits.Max_Tag_Expr_Length + 1)]),
            when Name_Patterns_Too_Long    =>
              Parsed
                ([+"-n", +Filled (Fabula.Limits.Max_Name_Filter_Length + 1)]),
            when Report_Json_Path_Too_Long =>
              Parsed ([+("--report-json=" & Path_Over)]),
            when Exclude_Path_Too_Long     =>
              Parsed ([+"--exclude-file", +Path_Over]),
            when Too_Many_Excludes         => Parsed (Too_Many_Exclude_Tokens),
            when Too_Many_Positionals      =>
              Parsed (Too_Many_Positional_Tokens));
   begin
      for Kind in Refusal_Kind loop
         declare
            R : constant Options_Result := Argv (Kind);
         begin
            Assert (Refused (R) = (Kind /= None), Kind'Image & ": Refused");
            if Kind /= None then
               Assert_Refused (R, Kind, Kind'Image);
            end if;
         end;
      end loop;
   end Test_Refused_Is_Kind;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Refused_Is_Kind'Access, "Refused exactly when a kind is set");
      Register_Routine (T, Test_No_Args'Access, "no arguments means help");
      Register_Routine (T, Test_Help_Flags'Access, "-h and --help");
      Register_Routine (T, Test_Help_Text'Access, "the help screen");
      Register_Routine (T, Test_Spellings'Access, "one spelling per flag");
      Register_Routine (T, Test_Classify'Access, "one kind per token");
      Register_Routine (T, Test_Boolean_Flags'Access, "every boolean flag");
      Register_Routine
        (T, Test_Combined_Flags'Access, "several flags and a file together");
      Register_Routine (T, Test_Tag_Expr'Access, "-t and --tags");
      Register_Routine (T, Test_Names'Access, "-n and --name");
      Register_Routine (T, Test_Exclude'Access, "--exclude-file accumulates");
      Register_Routine
        (T, Test_Value_Takes_Anything'Access, "a value is unconditional");
      Register_Routine
        (T, Test_Report_Json_Console'Access, "--report-json alone");
      Register_Routine
        (T, Test_Report_Json_File'Access, "a merged --report-json=FILE");
      Register_Routine (T, Test_Positionals'Access, "positional arguments");
      Register_Routine
        (T, Test_Unknown_Option'Access, "an unknown flag refuses");
      Register_Routine
        (T,
         Test_Missing_Value'Access,
         "a value-taking flag with nothing after");
      Register_Routine
        (T, Test_First_Refusal_Sticks'Access, "scanning stops at the first");
      Register_Routine (T, Test_Tag_Expr_Bound'Access, "the -t length bound");
      Register_Routine (T, Test_Names_Bound'Access, "the -n length bound");
      Register_Routine
        (T,
         Test_Report_Json_Path_Bound'Access,
         "the --report-json path bound");
      Register_Routine
        (T, Test_Exclude_Path_Bound'Access, "the --exclude-file path bound");
      Register_Routine
        (T, Test_Too_Many_Excludes'Access, "the --exclude-file count bound");
      Register_Routine
        (T, Test_Too_Many_Positionals'Access, "the positional count bound");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Cli"));

end Fabula_Cli_Tests;
