with Fabula.Searches;

package body Fabula_Closure_Proof
  with SPARK_Mode
is

   --  What a length, a count or a total is before anything adds to it.
   No_Length : constant Natural := 0;

   ---------------------------------------------------------------------
   --  The parser.
   ---------------------------------------------------------------------

   Feature_Text  : constant String := "Feature: x";
   Scenario_Text : constant String := "  Scenario: y";

   Feature_Line  : constant Fabula.Source_Line := Fabula.First_Line;
   Scenario_Line : constant Fabula.Source_Line := 2;

   procedure Closure_Parse
     (P : out Fabula.Parse.Parser; Doc : in out Fabula.Ast.Document) is
   begin
      Fabula.Parse.Start (P, Doc);
      Fabula.Parse.Feed (P, Doc, Feature_Text, Feature_Line);
      Fabula.Parse.Feed (P, Doc, Scenario_Text, Scenario_Line);
      Fabula.Parse.Finish (P, Doc);
   end Closure_Parse;

   ---------------------------------------------------------------------
   --  Checks and numeric reads.
   ---------------------------------------------------------------------

   --  Two values in order, and texts that read as the lesser one and as
   --  no number at all.
   Lesser         : constant Integer := 1;
   Greater        : constant Integer := Lesser + 1;
   Lesser_Text    : constant String := "1";
   Not_A_Number   : constant String := "x";
   Some_Text      : constant String := "a";
   Other_Text     : constant String := "b";
   Failure_Reason : constant String := "closure";

   procedure Closure_Check (R : in out Fabula.Check.Outcome) is
   begin
      Closure_Compare.Equal (R, Lesser, Lesser);
      Closure_Compare.Not_Equal (R, Lesser, Greater);
      Closure_Compare.Greater (R, Greater, Lesser);
      Closure_Compare.Greater_Or_Equal (R, Lesser, Lesser);
      Closure_Compare.Less (R, Lesser, Greater);
      Closure_Compare.Less_Or_Equal (R, Lesser, Lesser);
      Closure_Compare.Equal
        (R, Lesser, Fabula.Numbers.Parse_Integer (Lesser_Text));
      Closure_Compare.Less
        (R, Fabula.Numbers.Parse_Integer (Not_A_Number), Greater);
      Fabula.Check.Is_True (R, True);
      Fabula.Check.Text_Equal (R, Some_Text, Other_Text);
      Fabula.Check.Skip (R);
      Fabula.Check.Fail (R, Failure_Reason);
      Fabula.Check.Fail_Step (R);
   end Closure_Check;

   use type Fabula.Numbers.Integer_Reads.Read;

   --  A total that is no parsed number.
   No_Total : constant Integer := 0;

   --  The one capture Closure_Numbers adds, and the values it adds with
   --  no overflow.
   Number_Capture : constant := 1;

   subtype Digit_Value is Integer range 0 .. 9;

   --  Parsed's value, or No_Total with the step failed: Value is read
   --  only where Ok holds.
   procedure Read_Total
     (Parsed : Fabula.Numbers.Integer_Reads.Read;
      R      : in out Fabula.Check.Outcome;
      Total  : out Integer) is
   begin
      if Parsed.Ok then
         Total := Parsed.Value;
      else
         Total := No_Total;
         Fabula.Check.Fail_Step (R, Fabula.Numbers.Reason (Parsed.Error));
      end if;
   end Read_Total;

   --  Adds A's captured digit to a digit Total, then checks the capture
   --  against the total, a read on one side.
   procedure Add_Captured
     (A     : Fabula.Args.List;
      R     : in out Fabula.Check.Outcome;
      Total : in out Integer) is
   begin
      if Fabula.Args.Count (A) < Number_Capture then
         return;
      end if;
      declare
         Captured : constant Fabula.Numbers.Integer_Reads.Read :=
           Fabula.Args.Int (A, Number_Capture);
      begin
         if Captured.Ok
           and then Captured.Value in Digit_Value
           and then Total in Digit_Value
         then
            Total := Total + Captured.Value;
         end if;
         Closure_Compare.Equal (R, Total, Captured);
      end;
   end Add_Captured;

   procedure Closure_Numbers
     (A     : Fabula.Args.List;
      Text  : String;
      R     : in out Fabula.Check.Outcome;
      Total : out Integer) is
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
      Read_Total (Fabula.Numbers.Parse_Integer (Text), R, Total);
      Add_Captured (A, R, Total);
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

   ---------------------------------------------------------------------
   --  The registry.
   ---------------------------------------------------------------------

   Lookup_Text : constant String := "the count is 5";

   --  The length of the first bad step pattern; No_Length for none.
   function Bad_Pattern_Length return Natural
   is (declare
         Bad : constant Natural := Closure_Registry.First_Bad (Closure_Steps);
       begin
         (if Bad /= Fabula.Searches.Not_Found
          then Closure_Registry.Pattern_Text (Closure_Steps, Bad)'Length
          else No_Length));

   --  One lookup, as the runner will do it once the table is valid.
   procedure Look_Up (Kind : in out Closure_Step; Captures : in out Natural)
   with Pre => Closure_Registry.Steps_Valid (Closure_Steps)
   is
      R : constant Closure_Registry.Match_Result :=
        Closure_Registry.Find (Closure_Steps, Lookup_Text);
   begin
      if R.Found then
         Kind := Closure_Registry.Kind_Of (Closure_Steps, R.Index);
         Captures := R.Captures.Count;
      end if;
   end Look_Up;

   procedure Closure_Lookup (Kind : out Closure_Step; Captures : out Natural)
   is
   begin
      Kind := Count_Step;
      Captures := No_Length;
      if Closure_Registry.Steps_Valid (Closure_Steps) then
         Look_Up (Kind, Captures);
      else
         Captures := Bad_Pattern_Length;
      end if;
   end Closure_Lookup;

   --  The length of the first bad hook's tag expression; No_Length for
   --  none.
   function Bad_Hook_Length return Natural
   is (declare
         Bad : constant Natural :=
           Closure_Registry.First_Bad_Hook (Closure_Hooks);
       begin
         (if Bad /= Fabula.Searches.Not_Found
          then Closure_Registry.Tag_Expr_Text (Closure_Hooks, Bad)'Length
          else No_Length));

   --  The rows of the valid hook table that run Fresh_Hook at a
   --  scenario's start for the instance's tag set.
   function Fresh_Rows return Natural
   with Pre => Closure_Registry.Hooks_Valid (Closure_Hooks)
   is
      Tagged_Rows : Natural := No_Length;
   begin
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
      return Tagged_Rows;
   end Fresh_Rows;

   procedure Closure_Hook_Walk (Tagged_Rows : out Natural) is
   begin
      Tagged_Rows :=
        (if Closure_Registry.Hooks_Valid (Closure_Hooks)
         then Fresh_Rows
         else Bad_Hook_Length);
   end Closure_Hook_Walk;

   ---------------------------------------------------------------------
   --  Outline expansion.
   ---------------------------------------------------------------------

   use type Fabula.Line_Number;
   use type Fabula.Ast.Scenario_Handle;
   use type Fabula.Ast.Step_Handle;
   use type Fabula.Expand.Walk_Status;
   use type Closure_Run.Command;
   use type Closure_Run.Notice_Kind;

   First_Scenario : constant Fabula.Ast.Scenario_Index :=
     Fabula.Ast.Scenario_Index'First;

   --  One concrete step: whether it fits, then its resolved text.
   function Closure_Step_Length
     (Doc  : Fabula.Ast.Document;
      Ref  : Fabula.Expand.Example_Ref;
      Step : Fabula.Ast.Step_Handle) return Natural is
   begin
      if Step not in 1 .. Fabula.Ast.Step_Count (Doc) then
         return No_Length;
      end if;
      declare
         Node : constant Fabula.Ast.Step_Node := Fabula.Ast.Step (Doc, Step);
      begin
         return
           (if Fabula.Expand.Step_Fits
                 (Doc,
                  Node,
                  Fabula.Expand.Header_Row_Of (Ref),
                  Fabula.Expand.Data_Row_Of (Ref))
            then
              Fabula.Expand.Value
                (Fabula.Expand.Resolved
                   (Doc,
                    Node.Text,
                    Fabula.Expand.Header_Row_Of (Ref),
                    Fabula.Expand.Data_Row_Of (Ref)))'Length
            else No_Length);
      end;
   end Closure_Step_Length;

   --  A due row of the first outline: its name, line and tags, and its
   --  first step's expansion when the row is tagged.
   function Row_Length
     (Doc : Fabula.Ast.Document; Ref : Fabula.Expand.Example_Ref)
      return Natural
   with
     Pre =>
       First_Scenario <= Fabula.Ast.Scenario_Count (Doc)
       and then Ref.Status = Fabula.Expand.Row_Due
   is
      Name : constant Fabula.Expand.Text_Result :=
        Fabula.Expand.Concrete_Name
          (Doc, First_Scenario, Ref.Header_Row, Ref.Data_Row);
      Tags : constant Fabula.Expand.Tag_Set :=
        Fabula.Expand.Effective_Tags (Doc, First_Scenario, Ref.Block);
   begin
      return
        (if Fabula.Expand.Contains (Doc, Tags, Closure_Tag)
           and then Fabula.Expand.Concrete_Line (Doc, Ref.Data_Row)
                    /= Fabula.No_Line
         then
           Closure_Step_Length
             (Doc, Ref, Fabula.Ast.Scenario (Doc, First_Scenario).Steps.First)
         else Fabula.Expand.Value (Name)'Length);
   end Row_Length;

   --  The first outline's second concrete scenario, as the runner walks
   --  to it.
   function Second_Row_Length (Doc : Fabula.Ast.Document) return Natural
   with Pre => First_Scenario <= Fabula.Ast.Scenario_Count (Doc)
   is
      Ref : constant Fabula.Expand.Example_Ref :=
        Fabula.Expand.Next_Example
          (Doc,
           First_Scenario,
           Fabula.Expand.First_Example (Doc, First_Scenario));
   begin
      if Ref.Status /= Fabula.Expand.Row_Due then
         return No_Length;
      end if;
      return Row_Length (Doc, Ref);
   end Second_Row_Length;

   procedure Closure_Expand (Doc : Fabula.Ast.Document; Total : out Natural) is
   begin
      Total :=
        (if First_Scenario <= Fabula.Ast.Scenario_Count (Doc)
         then Second_Row_Length (Doc)
         else No_Length);
   end Closure_Expand;

   ---------------------------------------------------------------------
   --  Arguments.
   ---------------------------------------------------------------------

   procedure Closure_Assemble
     (Ref : Fabula.Args.Document_Access; A : out Fabula.Args.List)
   is
      Attached : constant Fabula.Args.Attachments :=
        (Doc        => Ref,
         Doc_String => 1,
         Table      => 1,
         Header_Row => 1,
         Data_Row   => 2);
      R        : Closure_Registry.Match_Result;
   begin
      if Closure_Registry.Steps_Valid (Closure_Steps) then
         R := Closure_Registry.Find (Closure_Steps, Lookup_Text);
      end if;
      A := Fabula.Args.Make (Lookup_Text, R.Captures, Attached);
   end Closure_Assemble;

   --  The capture every capture reader reads.
   Probed_Capture : constant := 1;

   function Closure_Read_Captures (A : Fabula.Args.List) return Natural is
   begin
      if Fabula.Args.Count (A) < Probed_Capture then
         return No_Length;
      end if;
      return
        Natural'Max
          (Fabula.Args.Text (A, Probed_Capture)'Length,
           Fabula.Args.Word (A, Probed_Capture)'Length)
        + Boolean'Pos
            (Fabula.Args.Int (A, Probed_Capture).Ok
             and then Fabula.Args.Long (A, Probed_Capture).Ok
             and then Fabula.Args.Real (A, Probed_Capture).Ok);
   end Closure_Read_Captures;

   First_Doc_Line : constant := 1;

   function Closure_Read_Doc (A : Fabula.Args.List) return Natural is
   begin
      if not Fabula.Args.Has_Doc (A) then
         return No_Length;
      end if;
      return
        Natural'Max
          (Natural'Max
             (Fabula.Args.Doc_String (A)'Length,
              Fabula.Args.Doc_Type (A)'Length),
           (if Fabula.Args.Doc_Line_Count (A) >= First_Doc_Line
            then Fabula.Args.Doc_Line (A, First_Doc_Line)'Length
            else No_Length));
   end Closure_Read_Doc;

   --  The two-by-two table every table reader reads: a header row and a
   --  row of values, a key column and a value column.
   First_Row    : constant := 1;
   Last_Row     : constant := 2;
   First_Column : constant := 1;
   Last_Column  : constant := 2;
   Key          : constant String := "k";
   No_Value     : constant Integer := 0;

   function Is_Square_Table (A : Fabula.Args.List) return Boolean
   is (Fabula.Args.Has_Table (A)
       and then Fabula.Args.Row_Count (A) >= Last_Row
       and then Fabula.Args.Col_Count (A) = Last_Column);

   function Hash_Length (A : Fabula.Args.List) return Natural
   is (if Fabula.Args.Has_Column (A, Key)
       then Fabula.Args.Hash_Value (A, First_Row, Key)'Length
       else No_Length)
   with Pre => Is_Square_Table (A);

   function Pair_Length (A : Fabula.Args.List) return Natural
   is (if Fabula.Args.Has_Pair (A, Key)
       then Fabula.Args.Pair_Value (A, Key)'Length
       else No_Length)
   with Pre => Is_Square_Table (A);

   function Closure_Read_Table (A : Fabula.Args.List) return Natural is
   begin
      if not Is_Square_Table (A) then
         return No_Length;
      end if;
      return
        Natural'Max
          (Fabula.Args.Cell (A, Last_Row, Last_Column)'Length
           + Boolean'Pos
               (Fabula.Numbers.Integer_Reads.Value_Or
                  (Fabula.Args.Cell_Int (A, First_Row, First_Column), No_Value)
                > No_Value),
           Natural'Max (Hash_Length (A), Pair_Length (A)));
   end Closure_Read_Table;

   procedure Closure_Read (A : Fabula.Args.List; Longest : out Natural) is
   begin
      Longest :=
        Natural'Max
          (Closure_Read_Captures (A),
           Natural'Max (Closure_Read_Doc (A), Closure_Read_Table (A)));
   end Closure_Read;

   ---------------------------------------------------------------------
   --  The runner, driven as the shell drives it.
   ---------------------------------------------------------------------

   --  More moves than the closure's one-scenario feature needs.
   Closure_Moves : constant := 64;

   No_Word_Text  : constant String := "no word";
   Name_Patterns : constant String := "a*:b?";
   Feature_File  : constant String := "a.feature";

   --  The line the run selects: the fixture's scenario header.
   Selected_Line : constant Fabula.Source_Line := 4;

   --  A word step with no word fails itself.
   function Closure_Step_Outcome
     (Kind : Closure_Step; A : Fabula.Args.List) return Fabula.Check.Outcome
   is
      Result : Fabula.Check.Outcome;
   begin
      if Kind = Word_Step and then Fabula.Args.Count (A) < Probed_Capture then
         Fabula.Check.Fail_Step (Result, No_Word_Text);
      end if;
      return Result;
   end Closure_Step_Outcome;

   --  The tagged hook skips a scenario it sees no line for.
   function Closure_Hook_Outcome
     (Kind : Closure_Hook; F : Fabula.Frames.Frame) return Fabula.Check.Outcome
   is
      Result : Fabula.Check.Outcome;
   begin
      if Kind = Fresh_Hook and then F.Scenario_Line = Fabula.No_Line then
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

   --  The one feature, when the shell made its Document.
   procedure Serve_Feature
     (Ref    : Fabula.Args.Document_Access;
      Lines  : Closure_Run.Line_Selection;
      R      : in out Closure_Run.Runner;
      Closed : in out Natural)
   is
      use type Fabula.Args.Document_Access;
   begin
      if Ref /= null and then Closure_Run.Between_Features (R) then
         Closure_Run.Start_Feature (R, Ref, Feature_File, Lines);
         Closure_Serve (R, Closed);
      end if;
   end Serve_Feature;

   --  One parse error, then the run's end.
   procedure Serve_Finish
     (R : in out Closure_Run.Runner; Closed : in out Natural) is
   begin
      if Closure_Run.Between_Features (R) then
         Closure_Run.Note_Parse_Error (R);
         Closure_Run.Finish_Run (R);
         Closure_Serve (R, Closed);
      end if;
   end Serve_Finish;

   procedure Drive_Whole_Run
     (Ref    : Fabula.Args.Document_Access;
      Counts : out Fabula.Results.Counts;
      Closed : in out Natural)
   with Pre => Closure_Run.Tables_Valid
   is
      R     : Closure_Run.Runner;
      Opts  : Closure_Run.Options;
      Lines : Closure_Run.Line_Selection := Closure_Run.All_Lines;
   begin
      Closure_Run.Set_Names (Opts, Name_Patterns);
      Closure_Run.Add_Line (Lines, Selected_Line);
      Closure_Run.Start_Run (R, Opts);
      Closure_Serve (R, Closed);
      Serve_Feature (Ref, Lines, R, Closed);
      Serve_Finish (R, Closed);
      Counts := Closure_Run.Counts_Of (R);
   end Drive_Whole_Run;

   procedure Closure_Drive
     (Ref    : Fabula.Args.Document_Access;
      Counts : out Fabula.Results.Counts;
      Closed : out Natural) is
   begin
      Counts := (others => <>);
      Closed := No_Length;
      if Closure_Run.Tables_Valid then
         Drive_Whole_Run (Ref, Counts, Closed);
      end if;
   end Closure_Drive;

   ---------------------------------------------------------------------
   --  The command line.
   ---------------------------------------------------------------------

   --  A well-formed argv: every flag, a merged --report-json=FILE, an
   --  --exclude-file value, one positional.
   Good_Args : constant Fabula.Cli.Arg_List :=
     [Fabula.Cli.To_Arg ("-t"),
      Fabula.Cli.To_Arg ("@a"),
      Fabula.Cli.To_Arg ("--report-json=out.json"),
      Fabula.Cli.To_Arg ("--exclude-file"),
      Fabula.Cli.To_Arg ("skip.feature"),
      Fabula.Cli.To_Arg ("real.feature")];

   Bad_Args : constant Fabula.Cli.Arg_List := [Fabula.Cli.To_Arg ("--bogus")];

   --  The first exclude and the first positional.
   First_Entry : constant := 1;

   --  The longest text the result holds, and at least one when every
   --  flag is set.
   function Cli_Texts_Length (R : Fabula.Cli.Options_Result) return Natural
   is (Natural'Max
         (Natural'Max
            (Fabula.Cli.Tag_Expr_Text (R)'Length,
             Fabula.Cli.Names_Text (R)'Length),
          Natural'Max
            ((if Fabula.Cli."="
                   (Fabula.Cli.Report_Target_Of (R), Fabula.Cli.Json_File)
              then Fabula.Cli.Report_Json_File_Text (R)'Length
              else No_Length),
             Boolean'Pos
               (Fabula.Cli.Help (R)
                and then Fabula.Cli."="
                           (Fabula.Cli.Log_Level_Of (R), Fabula.Cli.Verbose)
                and then Fabula.Cli.Dry_Run (R)
                and then Fabula.Cli.Continue_On_Failure (R)))));

   --  The first exclude's and the first positional's length.
   function Cli_Lists_Length (R : Fabula.Cli.Options_Result) return Natural
   is (Natural'Max
         ((if Fabula.Cli.Excludes_Count (R) >= First_Entry
           then Fabula.Cli.Exclude_Text (R, First_Entry)'Length
           else No_Length),
          (if Fabula.Cli.Positionals_Count (R) >= First_Entry
           then Fabula.Cli.Positional_Text (R, First_Entry)'Length
           else No_Length)));

   --  No_Length if Cli itself refused the good argv.
   function Closure_Cli_Good return Natural
   is (declare
         R : constant Fabula.Cli.Options_Result :=
           Fabula.Cli.Parse (Good_Args);
       begin
         (if Fabula.Cli.Refused (R)
          then No_Length
          else Natural'Max (Cli_Texts_Length (R), Cli_Lists_Length (R))));

   procedure Closure_Cli (Total : out Natural) is
      Bad : constant Fabula.Cli.Options_Result := Fabula.Cli.Parse (Bad_Args);
   begin
      Total :=
        Natural'Max
          (Natural'Max (Closure_Cli_Good, Fabula.Cli.Help_Text'Length),
           (if Fabula.Cli.Refused (Bad)
            then Fabula.Cli.Refusal_Text (Fabula.Cli.Refusal_Of (Bad))'Length
            else No_Length));
   end Closure_Cli;

   ---------------------------------------------------------------------
   --  Frames and bounded text.
   ---------------------------------------------------------------------

   Feature_Name  : constant String := "a feature";
   Scenario_Name : constant String := "a scenario";
   Step_Text     : constant String := "a step";

   procedure Closure_Frame (F : in out Fabula.Frames.Frame) is
   begin
      F.Feature := Fabula.Frames.To_Name (Feature_Name);
      F.Scenario := Fabula.Frames.To_Name (Scenario_Name);
      F.Step := Fabula.Frames.To_Step (Step_Text);
      F.File := Fabula.Frames.To_Path (Feature_File);
      declare
         Step_Len : constant Natural := Fabula.Frames.Value (F.Step)'Length;
         pragma Unreferenced (Step_Len);
      begin
         null;
      end;
   end Closure_Frame;

   procedure Closure_Texts (Kept : out Natural) is
      Room   : constant := 4;
      Long   : constant String := "abcdef";
      First  : constant String := "abcd";
      Start  : constant String := "ab";
      Piece  : constant String := "c";
      Joined : constant String := "abc";
      Rest   : constant String := "xyz";
      Filled : constant String := "abcx";
      T      : Fabula.Texts.Bounded_Text (Room) :=
        Fabula.Texts.Truncated (Long, Room);
      Ok     : Boolean := True;
   begin
      pragma Assert (Fabula.Texts.Value (T) = First);
      T := Fabula.Texts.Truncated (Start, Room);
      Fabula.Texts.Append (T, Piece, Ok);
      pragma Assert (Ok and then Fabula.Texts.Value (T) = Joined);
      Fabula.Texts.Append (T, Rest, Ok);
      pragma Assert (not Ok and then Fabula.Texts.Value (T) = Joined);
      Fabula.Texts.Append_Truncated (T, Rest);
      pragma Assert (Fabula.Texts.Value (T) = Filled);
      Kept := Fabula.Texts.Length (T);
   end Closure_Texts;

end Fabula_Closure_Proof;
