package body Fabula_Closure_Proof
  with SPARK_Mode
is

   procedure Closure_Parse
     (P : out Fabula.Parse.Parser; Doc : in out Fabula.Ast.Document) is
   begin
      Fabula.Parse.Start (P, Doc);
      Fabula.Parse.Feed (P, Doc, "Feature: x", 1);
      Fabula.Parse.Feed (P, Doc, "  Scenario: y", 2);
      Fabula.Parse.Finish (P, Doc);
   end Closure_Parse;

   procedure Closure_Check (R : in out Fabula.Check.Outcome) is
   begin
      Closure_Compare.Equal (R, 1, 1);
      Closure_Compare.Not_Equal (R, 1, 2);
      Closure_Compare.Greater (R, 2, 1);
      Closure_Compare.Greater_Or_Equal (R, 1, 1);
      Closure_Compare.Less (R, 1, 2);
      Closure_Compare.Less_Or_Equal (R, 1, 1);
      Closure_Compare.Equal (R, 1, Fabula.Numbers.Parse_Integer ("1"));
      Closure_Compare.Less (R, Fabula.Numbers.Parse_Integer ("x"), 2);
      Fabula.Check.Is_True (R, True);
      Fabula.Check.Text_Equal (R, "a", "b");
      Fabula.Check.Skip (R);
      Fabula.Check.Fail (R, "closure");
      Fabula.Check.Fail_Step (R);
   end Closure_Check;

   use type Fabula.Numbers.Integer_Reads.Read;

   procedure Closure_Numbers
     (A     : Fabula.Args.List;
      Text  : String;
      R     : in out Fabula.Check.Outcome;
      Total : out Integer)
   is
      Parsed : constant Fabula.Numbers.Integer_Reads.Read :=
        Fabula.Numbers.Parse_Integer (Text);
   begin
      pragma
        Assert
          (Fabula.Numbers.Parse_Integer ("-007")
             = Fabula.Numbers.Integer_Reads.Success (-7));
      pragma
        Assert
          (Fabula.Numbers.Parse_Integer ("2147483648")
             = Fabula.Numbers.Integer_Reads.Failure
                 (Fabula.Numbers.Out_Of_Range));
      if Parsed.Ok then
         Total := Parsed.Value;
      else
         Total := 0;
         Fabula.Check.Fail_Step (R, Fabula.Numbers.Reason (Parsed.Error));
      end if;
      if Fabula.Args.Count (A) = 0 then
         return;
      end if;
      declare
         Captured : constant Fabula.Numbers.Integer_Reads.Read :=
           Fabula.Args.Int (A, 1);
      begin
         if Captured.Ok
           and then Captured.Value in 0 .. 9
           and then Total in 0 .. 9
         then
            Total := Total + Captured.Value;
         end if;
         Closure_Compare.Equal (R, Total, Captured);
      end;
   end Closure_Numbers;

   procedure Closure_Results (C : in out Fabula.Results.Counts) is
   begin
      Fabula.Results.Add_Scenario (C, Fabula.Results.Passed);
      Fabula.Results.Add_Step (C, Fabula.Results.Undefined);
      Fabula.Results.Add_Parse_Error (C);
      Fabula.Results.Add_Hook_Error (C);
      declare
         Failed : constant Boolean := Fabula.Results.Run_Failed (C);
         pragma Unreferenced (Failed);
      begin
         null;
      end;
   end Closure_Results;

   procedure Closure_Lookup (Kind : out Closure_Step; Captures : out Natural)
   is
   begin
      Kind := Count_Step;
      Captures := 0;
      if not Closure_Registry.Steps_Valid (Closure_Steps) then
         declare
            Bad : constant Natural :=
              Closure_Registry.First_Bad (Closure_Steps);
         begin
            if Bad /= 0 then
               Captures :=
                 Closure_Registry.Pattern_Text (Closure_Steps, Bad)'Length;
            end if;
         end;
         return;
      end if;
      declare
         R : constant Closure_Registry.Match_Result :=
           Closure_Registry.Find (Closure_Steps, "the count is 5");
      begin
         if R.Found then
            Kind := Closure_Registry.Kind_Of (Closure_Steps, R.Index);
            Captures := R.Captures.Count;
         end if;
      end;
   end Closure_Lookup;

   procedure Closure_Hook_Walk (Tagged_Rows : out Natural) is
   begin
      Tagged_Rows := 0;
      if not Closure_Registry.Hooks_Valid (Closure_Hooks) then
         declare
            Bad : constant Natural :=
              Closure_Registry.First_Bad_Hook (Closure_Hooks);
         begin
            if Bad /= 0 then
               Tagged_Rows :=
                 Closure_Registry.Tag_Expr_Text (Closure_Hooks, Bad)'Length;
            end if;
         end;
         return;
      end if;
      for I in Closure_Hooks'Range loop
         pragma Loop_Invariant (Tagged_Rows <= I - Closure_Hooks'First);
         if Closure_Registry.Phase_Of (Closure_Hooks, I)
           = Closure_Registry.Scenario_Start
           and then Closure_Registry.Kind_Of (Closure_Hooks, I) = Fresh_Hook
           and then Closure_Registry.Has_Tag_Expr (Closure_Hooks, I)
           and then Closure_Eval (Closure_Registry.Tag_Expr (Closure_Hooks, I))
         then
            Tagged_Rows := Tagged_Rows + 1;
         end if;
      end loop;
   end Closure_Hook_Walk;

   use type Fabula.Ast.Examples_Handle;
   use type Fabula.Ast.Scenario_Handle;
   use type Fabula.Ast.Step_Handle;
   use type Closure_Run.Command;
   use type Closure_Run.Notice_Kind;

   --  One concrete step: whether it fits, then its resolved text.
   function Closure_Step_Length
     (Doc  : Fabula.Ast.Document;
      Ref  : Fabula.Expand.Example_Ref;
      Step : Fabula.Ast.Step_Handle) return Natural is
   begin
      if Step = 0 or else Step > Fabula.Ast.Step_Count (Doc) then
         return 0;
      end if;
      declare
         Node : constant Fabula.Ast.Step_Node := Fabula.Ast.Step (Doc, Step);
      begin
         if not Fabula.Expand.Step_Fits
                  (Doc, Node, Ref.Header_Row, Ref.Data_Row)
         then
            return 0;
         end if;
         return
           Fabula.Expand.Resolved
             (Doc, Node.Text, Ref.Header_Row, Ref.Data_Row)
             .Len;
      end;
   end Closure_Step_Length;

   procedure Closure_Expand (Doc : Fabula.Ast.Document; Total : out Natural) is
      Ref : Fabula.Expand.Example_Ref;
   begin
      Total := 0;
      if Fabula.Ast.Scenario_Count (Doc) = 0 then
         return;
      end if;
      Ref :=
        Fabula.Expand.Next_Example
          (Doc, 1, Fabula.Expand.First_Example (Doc, 1));
      if Ref.Block = 0 then
         return;
      end if;
      declare
         Name : constant Fabula.Expand.Text_Result :=
           Fabula.Expand.Concrete_Name (Doc, 1, Ref.Header_Row, Ref.Data_Row);
         Tags : constant Fabula.Expand.Tag_Set :=
           Fabula.Expand.Effective_Tags (Doc, 1, Ref.Block);
      begin
         Total := Name.Len;
         if Fabula.Expand.Contains (Doc, Tags, "@a")
           and then Fabula.Expand.Concrete_Line (Doc, Ref.Data_Row) > 0
         then
            Total :=
              Closure_Step_Length
                (Doc, Ref, Fabula.Ast.Scenario (Doc, 1).Steps.First);
         end if;
      end;
   end Closure_Expand;

   procedure Closure_Assemble
     (Ref : Fabula.Args.Document_Access; A : out Fabula.Args.List)
   is
      Text : constant String := "the count is 5";
      R    : Closure_Registry.Match_Result;
   begin
      if Closure_Registry.Steps_Valid (Closure_Steps) then
         R := Closure_Registry.Find (Closure_Steps, Text);
      end if;
      A := Fabula.Args.Make (Text, R.Captures);
      Fabula.Args.Attach (A, Ref, 1, 1);
      Fabula.Args.Set_Example (A, 1, 2);
   end Closure_Assemble;

   function Closure_Read_Captures (A : Fabula.Args.List) return Natural is
      Longest : Natural;
   begin
      if Fabula.Args.Count (A) = 0 then
         return 0;
      end if;
      Longest :=
        Natural'Max
          (Fabula.Args.Text (A, 1)'Length, Fabula.Args.Word (A, 1)'Length);
      if Fabula.Args.Int (A, 1).Ok
        and then Fabula.Args.Long (A, 1).Ok
        and then Fabula.Args.Real (A, 1).Ok
      then
         Longest := Longest + 1;
      end if;
      return Longest;
   end Closure_Read_Captures;

   function Closure_Read_Doc (A : Fabula.Args.List) return Natural is
      Longest : Natural;
   begin
      if not Fabula.Args.Has_Doc (A) then
         return 0;
      end if;
      Longest :=
        Natural'Max
          (Fabula.Args.Doc_String (A)'Length, Fabula.Args.Doc_Type (A)'Length);
      if Fabula.Args.Doc_Line_Count (A) >= 1 then
         Longest := Natural'Max (Longest, Fabula.Args.Doc_Line (A, 1)'Length);
      end if;
      return Longest;
   end Closure_Read_Doc;

   function Closure_Read_Table (A : Fabula.Args.List) return Natural is
      Key     : constant String := "k";
      Longest : Natural;
   begin
      if not Fabula.Args.Has_Table (A)
        or else Fabula.Args.Row_Count (A) < 2
        or else Fabula.Args.Col_Count (A) /= 2
      then
         return 0;
      end if;
      Longest := Fabula.Args.Cell (A, 2, 2)'Length;
      if Fabula.Numbers.Integer_Reads.Value_Or
           (Fabula.Args.Cell_Int (A, 1, 1), 0)
        > 0
      then
         Longest := Longest + 1;
      end if;
      if Fabula.Args.Has_Column (A, Key) then
         Longest :=
           Natural'Max (Longest, Fabula.Args.Hash_Value (A, 1, Key)'Length);
      end if;
      if Fabula.Args.Has_Pair (A, Key) then
         Longest :=
           Natural'Max (Longest, Fabula.Args.Pair_Value (A, Key)'Length);
      end if;
      return Longest;
   end Closure_Read_Table;

   procedure Closure_Read (A : Fabula.Args.List; Longest : out Natural) is
   begin
      Longest :=
        Natural'Max
          (Closure_Read_Captures (A),
           Natural'Max (Closure_Read_Doc (A), Closure_Read_Table (A)));
   end Closure_Read;

   --  More moves than the closure's one-scenario feature needs.
   Closure_Moves : constant := 64;

   --  A word step with no word fails itself.
   function Closure_Step_Outcome
     (Kind : Closure_Step; A : Fabula.Args.List) return Fabula.Check.Outcome
   is
      Result : Fabula.Check.Outcome;
   begin
      if Kind = Word_Step and then Fabula.Args.Count (A) = 0 then
         Fabula.Check.Fail_Step (Result, "no word");
      end if;
      return Result;
   end Closure_Step_Outcome;

   --  The tagged hook skips a scenario it sees no line for.
   function Closure_Hook_Outcome
     (Kind : Closure_Hook; F : Fabula.Frames.Frame) return Fabula.Check.Outcome
   is
      Result : Fabula.Check.Outcome;
   begin
      if Kind = Fresh_Hook and then F.Scenario_Line = 0 then
         Fabula.Check.Skip (Result);
      end if;
      return Result;
   end Closure_Hook_Outcome;

   --  Runs the step or hook the pending request names, as the shell
   --  does, and posts its outcome.
   procedure Closure_Answer (R : in out Closure_Run.Runner)
   with Pre => Closure_Run.Next_Request (R) /= Closure_Run.C_None
   is
   begin
      if Closure_Run.Next_Request (R) = Closure_Run.C_Step then
         Closure_Run.Post_Step_Result
           (R,
            Closure_Step_Outcome
              (Closure_Run.Pending_Step_Kind (R), Closure_Run.Step_Args (R)));
      else
         Closure_Run.Post_Hook_Result
           (R,
            Closure_Hook_Outcome
              (Closure_Run.Pending_Hook_Kind (R),
               Closure_Run.Current_Frame (R)));
      end if;
   end Closure_Answer;

   --  Drains R: every notice read and resumed, every request answered.
   --  Closed counts the scenarios that closed.
   procedure Closure_Serve
     (R : in out Closure_Run.Runner; Closed : in out Natural) is
   begin
      for Move in 1 .. Closure_Moves loop
         if Closure_Run.Has_Notice (R) then
            if Closure_Run.Current_Notice (R).Kind
              = Closure_Run.Scenario_Closed
              and then Closed < Natural'Last
            then
               Closed := Closed + 1;
            end if;
            Closure_Run.Resume (R);
         elsif Closure_Run.Next_Request (R) /= Closure_Run.C_None then
            Closure_Answer (R);
         else
            exit;
         end if;
      end loop;
   end Closure_Serve;

   procedure Closure_Drive
     (Ref    : Fabula.Args.Document_Access;
      Counts : out Fabula.Results.Counts;
      Closed : out Natural)
   is
      use type Fabula.Args.Document_Access;
      R     : Closure_Run.Runner;
      Opts  : Closure_Run.Options;
      Lines : Closure_Run.Line_Selection := Closure_Run.All_Lines;
   begin
      Counts := (others => <>);
      Closed := 0;
      if not Closure_Run.Tables_Valid then
         return;
      end if;
      Closure_Run.Set_Names (Opts, "a*:b?");
      Closure_Run.Add_Line (Lines, 4);
      Closure_Run.Start_Run (R, Opts);
      Closure_Serve (R, Closed);
      if Ref /= null and then Closure_Run.Between_Features (R) then
         Closure_Run.Start_Feature (R, Ref, "a.feature", Lines);
         Closure_Serve (R, Closed);
      end if;
      if Closure_Run.Between_Features (R) then
         Closure_Run.Note_Parse_Error (R);
         Closure_Run.Finish_Run (R);
         Closure_Serve (R, Closed);
      end if;
      Counts := Closure_Run.Counts_Of (R);
   end Closure_Drive;

   --  A well-formed argv: every flag, a merged --report-json=FILE, an
   --  --exclude-file value, one positional.  0 if Cli itself refused it.
   function Closure_Cli_Good return Natural is
      Args : Fabula.Cli.Arg_List (1 .. 6);
      R    : Fabula.Cli.Options_Result;
      Best : Natural;
   begin
      Fabula.Cli.Set (Args (1), "-t");
      Fabula.Cli.Set (Args (2), "@a");
      Fabula.Cli.Set (Args (3), "--report-json=out.json");
      Fabula.Cli.Set (Args (4), "--exclude-file");
      Fabula.Cli.Set (Args (5), "skip.feature");
      Fabula.Cli.Set (Args (6), "real.feature");
      Fabula.Cli.Parse (Args, R);
      if Fabula.Cli.Refused (R) then
         return 0;
      end if;
      Best :=
        Natural'Max
          (Fabula.Cli.Tag_Expr_Text (R)'Length,
           Fabula.Cli.Names_Text (R)'Length);
      if Fabula.Cli.Help (R)
        and then Fabula.Cli.Quiet (R)
        and then Fabula.Cli.Verbose (R)
        and then Fabula.Cli.Dry_Run (R)
        and then Fabula.Cli.Continue_On_Failure (R)
      then
         Best := Natural'Max (Best, 1);   --  every flag reachable

      end if;
      if Fabula.Cli.Report_Json (R)
        and then Fabula.Cli.Report_Json_Has_File (R)
      then
         Best :=
           Natural'Max (Best, Fabula.Cli.Report_Json_File_Text (R)'Length);
      end if;
      if Fabula.Cli.Excludes_Count (R) > 0 then
         Best := Natural'Max (Best, Fabula.Cli.Exclude_Text (R, 1)'Length);
      end if;
      if Fabula.Cli.Positionals_Count (R) > 0 then
         Best := Natural'Max (Best, Fabula.Cli.Positional_Text (R, 1)'Length);
      end if;
      return Best;
   end Closure_Cli_Good;

   procedure Closure_Cli (Total : out Natural) is
      Bad_Args : Fabula.Cli.Arg_List (1 .. 1);
      Bad      : Fabula.Cli.Options_Result;
   begin
      Total := Closure_Cli_Good;
      Fabula.Cli.Set (Bad_Args (1), "--bogus");
      Fabula.Cli.Parse (Bad_Args, Bad);
      if Fabula.Cli.Refused (Bad) then
         Total :=
           Natural'Max
             (Total,
              Fabula.Cli.Refusal_Text (Fabula.Cli.Refusal_Of (Bad))'Length);
      end if;
      Total := Natural'Max (Total, Fabula.Cli.Help_Text'Length);
   end Closure_Cli;

   procedure Closure_Frame (F : in out Fabula.Frames.Frame) is
   begin
      Fabula.Frames.Set (F.Feature, "a feature");
      Fabula.Frames.Set (F.Scenario, "a scenario");
      Fabula.Frames.Set (F.Step, "a step");
      Fabula.Frames.Set (F.File, "a.feature");
      declare
         Step_Len : constant Natural := Fabula.Frames.Value (F.Step)'Length;
         pragma Unreferenced (Step_Len);
      begin
         null;
      end;
   end Closure_Frame;

end Fabula_Closure_Proof;
