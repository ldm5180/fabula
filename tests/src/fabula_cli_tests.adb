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
         Set (Result (I - Tokens'First + 1), To_String (Tokens (I)));
      end loop;
      return Result;
   end Args;

   function Parsed (Tokens : Lines) return Options_Result is
      Result : Options_Result;
   begin
      Parse (Args (Tokens), Result);
      return Result;
   end Parsed;

   ---------------------------------------------------------------------
   --  Help triggers.
   ---------------------------------------------------------------------

   procedure Test_No_Args (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty : constant Arg_List (1 .. 0) := [others => <>];
      R     : Options_Result;
   begin
      Parse (Empty, R);
      Assert (Help (R), "no arguments means help");
      Assert (not Refused (R), "not a refusal");
   end Test_No_Args;

   procedure Test_Help_Flags (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Help (Parsed ([+"-h"])), "-h");
      Assert (Help (Parsed ([+"--help"])), "--help");
      Assert (not Help (Parsed ([+"a.feature"])), "a plain run asks no help");
   end Test_Help_Flags;

   ---------------------------------------------------------------------
   --  Every boolean flag, short and long.
   ---------------------------------------------------------------------

   procedure Test_Boolean_Flags (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Quiet (Parsed ([+"-q"])), "-q");
      Assert (Quiet (Parsed ([+"--quiet"])), "--quiet");
      Assert (Verbose (Parsed ([+"-v"])), "-v");
      Assert (Verbose (Parsed ([+"--verbose"])), "--verbose");
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
      Assert (Quiet (R) and then Verbose (R), "quiet and verbose together");
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
      Assert (not Quiet (R), "it never reached the flag dispatch");
   end Test_Value_Takes_Anything;

   ---------------------------------------------------------------------
   --  --report-json: the shell's own pre-classification, folded into
   --  one token (docs/report_wiring.md; state.md's deviation ledger).
   ---------------------------------------------------------------------

   procedure Test_Report_Json_Console
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed ([+"--report-json"]);
   begin
      Assert (Report_Json (R), "the flag fires");
      Assert (not Report_Json_Has_File (R), "no file: stdout");
   end Test_Report_Json_Console;

   procedure Test_Report_Json_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result :=
        Parsed ([+"--report-json=out.json", +"a.feature"]);
   begin
      Assert (Report_Json (R), "the flag fires");
      Assert (Report_Json_Has_File (R), "a merged value is a file");
      Assert (Report_Json_File_Text (R) = "out.json", "its name");
      Assert
        (Positionals_Count (R) = 1
         and then Positional_Text (R, 1) = "a.feature",
         "the merged token consumes no other argument");
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
   ---------------------------------------------------------------------

   procedure Test_Unknown_Option (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Options_Result := Parsed ([+"a.feature", +"--bogus"]);
   begin
      Assert (Refused (R), "an unrecognized '-' token refuses");
      Assert (Kind_Of (Refusal_Of (R)) = Unknown_Option, "as Unknown_Option");
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
      Assert
        (Kind_Of (Refusal_Of (Parsed ([+"-t"]))) = Missing_Value, "-t alone");
      Assert
        (Kind_Of (Refusal_Of (Parsed ([+"-n"]))) = Missing_Value, "-n alone");
      Assert
        (Kind_Of (Refusal_Of (Parsed ([+"--exclude-file"]))) = Missing_Value,
         "--exclude-file alone");
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
      Assert
        (Kind_Of (Refusal_Of (R)) = Tag_Expression_Too_Long,
         "one character more refuses");
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
      Assert
        (Kind_Of (Refusal_Of (R)) = Name_Patterns_Too_Long,
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
      Assert
        (Kind_Of (Refusal_Of (R)) = Report_Json_Path_Too_Long,
         "one character past Max_Path_Length");
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
      Assert
        (Kind_Of (Refusal_Of (R)) = Exclude_Path_Too_Long,
         "one character past Max_Path_Length");
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
      Assert
        (Kind_Of (Refusal_Of (R)) = Too_Many_Excludes,
         "one --exclude-file past Max_Cli_Excludes");
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
      Assert
        (Kind_Of (Refusal_Of (R)) = Too_Many_Positionals,
         "one file argument past Max_Cli_Positionals");
      Assert
        (Refusal_Text (Refusal_Of (R))
         = "Too many file or directory " & "arguments",
         "wording: " & Refusal_Text (Refusal_Of (R)));
   end Test_Too_Many_Positionals;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_No_Args'Access, "no arguments means help");
      Register_Routine (T, Test_Help_Flags'Access, "-h and --help");
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
