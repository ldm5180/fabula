with Fabula.Names;
with Sml.Machines.Operators;

package body Fabula.Run
  with SPARK_Mode
is

   use type Ast.Examples_Handle;
   use type Ast.Examples_Row_Handle;
   use type Ast.Scenario_Handle;
   use type Ast.Scenario_Kind;
   use type Ast.Step_Handle;
   use type Reg.Hook_Phase;
   use type Results.Status;

   package Op is new SM.Operators (Always => Always, Nothing => Nothing);
   use type Op.Ev, Op.Ev_Guard, Op.Ev_Built, Op.Source;

   subtype Ev is Op.Ev;

   Hook_Due       : constant Ev := (Kind => E_Hook_Due);
   Hooks_Done     : constant Ev := (Kind => E_Hooks_Done);
   Step_Due       : constant Ev := (Kind => E_Step_Due);
   Steps_Done     : constant Ev := (Kind => E_Steps_Done);
   Scenario_Due   : constant Ev := (Kind => E_Scenario_Due);
   Scenarios_Done : constant Ev := (Kind => E_Scenarios_Done);
   Feature        : constant Ev := (Kind => E_Feature);
   Finish         : constant Ev := (Kind => E_Finish);
   Posted         : constant Ev := (Kind => E_Posted);

   --  Each row reads:  From + Event (Guard) / Act >= To.  Rows for one
   --  state are tried top to bottom.  A hook phase ends when its cursor
   --  finds no further row; a scenario's steps end the same way.
   --!format off
   Table : constant SM.Transition_Table (1 .. Rows) :=
     [
      --  The run's Before_All hooks; then features, one at a time.
      Opening     + Hook_Due                 / Ask_Before_All >= Opening,
      Opening     + Hooks_Done               / Close_Opening  >= Ready,
      Ready       + Feature                                   >= Walking,
      Ready       + Finish                                    >= Closing,
      Walking     + Scenario_Due             / Open_Scenario  >= Before,
      Walking     + Scenarios_Done           / Close_Feature  >= Ready,

      --  One scenario: its before-hooks, then its steps.  The tag
      --  filter and an ignore both drop it once the hooks have run.
      Before      + Hook_Due                 / Ask_Hook       >= Before,
      Before      + Hooks_Done (Dropped)     / Drop_Scenario  >= Walking,
      Before      + Hooks_Done               / Enter_Scenario >= Stepping,
      Stepping    + Step_Due (Dropped)       / Drop_Scenario  >= Walking,
      Stepping    + Step_Due (Must_Skip)     / Pass_Over      >= Stepping,
      Stepping    + Step_Due (Unmatched)     / Mark_Undefined >= Stepping,
      Stepping    + Step_Due (Oversized)     / Refuse_Step    >= Stepping,
      Stepping    + Step_Due                                  >= Step_Before,
      Stepping    + Steps_Done (Dropped)     / Drop_Scenario  >= Walking,
      Stepping    + Steps_Done (Failing)     / Close_Scenario >= Walking,
      Stepping    + Steps_Done                                >= After,

      --  One step: its before-step hooks, its body, its after-step
      --  hooks.  A failed before-step hook closes it at once.
      Step_Before + Hook_Due                 / Ask_Hook       >= Step_Before,
      Step_Before + Hooks_Done (Step_Failed) / Close_Step     >= Stepping,
      Step_Before + Hooks_Done               / Ask_Step       >= Step_Body,
      Step_Body   + Posted                                    >= Step_After,
      Step_After  + Hook_Due                 / Ask_Hook       >= Step_After,
      Step_After  + Hooks_Done               / Close_Step     >= Stepping,

      --  The scenario's after-hooks; an ignore there still drops it.
      After       + Hook_Due                 / Ask_Hook       >= After,
      After       + Hooks_Done (Dropped)     / Drop_Scenario  >= Walking,
      After       + Hooks_Done               / Close_Scenario >= Walking,

      --  The run's After_All hooks.
      Closing     + Hook_Due                 / Ask_After_All  >= Closing,
      Closing     + Hooks_Done               / Close_Run      >= Finished];
   --!format on

   function Started return SM.Machine
   is (SM.Make (Table, Initial => Opening))
   with Post => Started'Result.Count = Rows;

   ---------------------------------------------------------------------
   --  The machine's guards and acts.
   ---------------------------------------------------------------------

   function Evaluate (G : Guard_Kind; Ctx : Work; Evt : Event) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      case G is
         when Always      =>
            return True;

         when Dropped     =>
            return Ctx.Ignored or else not Ctx.Selected;

         when Must_Skip   =>
            return
              Ctx.Skipped
              or else Ctx.Failed
              or else (not Ctx.Continue and then not Ctx.Last_Passed);

         when Unmatched   =>
            return Ctx.Text_Ok and then not Ctx.Found;

         when Oversized   =>
            return not Ctx.Text_Ok or else not Ctx.Args_Fit;

         when Step_Failed =>
            return Ctx.Step_Failed;

         when Failing     =>
            return Ctx.Failed;
      end case;
   end Evaluate;

   function Request_Of (A : Act) return Command
   is (case A is
         when Ask_Before_All => C_Before_All,
         when Ask_After_All  => C_After_All,
         when Ask_Hook       => C_Hook,
         when Ask_Step       => C_Step,
         when others         => C_None);

   procedure Execute (A : Act; Ctx : in out Work; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      Ctx.Due := A;
      Ctx.Requests.Pending := Request_Of (A);
   end Execute;

   ---------------------------------------------------------------------
   --  Options.
   ---------------------------------------------------------------------

   procedure Set_Names (Opts : in out Options; Patterns : String) is
   begin
      Opts.Names := [others => ' '];
      Opts.Names (1 .. Patterns'Length) := Patterns;
      Opts.Names_Len := Patterns'Length;
   end Set_Names;

   procedure Add_Line (Selection : in out Line_Selection; Line : Positive) is
   begin
      Selection.Count := Selection.Count + 1;
      Selection.Lines (Selection.Count) := Line;
   end Add_Line;

   ---------------------------------------------------------------------
   --  Hooks: the cursor walks the table in order, one phase at a time.
   ---------------------------------------------------------------------

   function State_Of (R : Runner) return State
   is (SM.State_Of (R.Machine));

   function Phase_For (S : State) return Reg.Hook_Phase
   is (case S is
         when Opening     => Reg.Run_Start,
         when Before      => Reg.Scenario_Start,
         when Step_Before => Reg.Step_Start,
         when Step_After  => Reg.Step_End,
         when After       => Reg.Scenario_End,
         when others      => Reg.Run_End);

   --  Whether expression E holds for the tag set Set, whose members
   --  are tags of Doc.
   function Selects
     (Doc : Ast.Document; Set : Expand.Tag_Set; E : Tags.Compiled)
      return Boolean
   with Pre => Tags.Valid (E)
   is
      function Has (Name : String) return Boolean
      is (Expand.Contains (Doc, Set, Name));

      function Eval is new Tags.Eval (Has_Tag => Has);
   begin
      return Eval (E);
   end Selects;

   --  An untagged hook row runs for every scenario; a tagged one when
   --  its expression holds for the scenario's tags.
   function Hook_Selected (R : Runner; I : Positive) return Boolean
   is (not Reg.Has_Tag_Expr (Hooks, I)
       or else (R.Doc /= null
                and then Tags.Valid (Reg.Tag_Expr (Hooks, I))
                and then Selects
                           (R.Doc.all, R.Tag_Set, Reg.Tag_Expr (Hooks, I))))
   with Pre => I in Hooks'Range;

   --  The first row after R.Hook that runs in the current phase, or 0.
   function Next_Hook (R : Runner) return Natural
   with Post => Next_Hook'Result = 0 or else Next_Hook'Result in Hooks'Range
   is
      Phase : constant Reg.Hook_Phase := Phase_For (State_Of (R));
   begin
      for I in Hooks'Range loop
         if I > R.Hook
           and then Reg.Phase_Of (Hooks, I) = Phase
           and then Hook_Selected (R, I)
         then
            return I;
         end if;
      end loop;
      return 0;
   end Next_Hook;

   function Pending_Hook_Kind (R : Runner) return Reg.Hook_Kind
   is (if R.Hook in Hooks'Range
       then Reg.Kind_Of (Hooks, R.Hook)
       else Reg.Hook_Kind'First);

   function Pending_Step_Kind (R : Runner) return Reg.Step_Kind
   is (if R.Match.Index in Steps'Range
       then Reg.Kind_Of (Steps, R.Match.Index)
       else Reg.Step_Kind'First);

   ---------------------------------------------------------------------
   --  Scenarios: every plain scenario, and every data row of every
   --  outline, in file order.
   ---------------------------------------------------------------------

   --  Moves S and Ex to the next scenario position.  Ex is an outline's
   --  current data row; its Block is 0 for a plain scenario.
   procedure Next_Position
     (Doc   : Ast.Document;
      S     : in out Ast.Scenario_Handle;
      Ex    : in out Expand.Example_Ref;
      Found : out Boolean)
   with Post => (if Found then S in 1 .. Ast.Scenario_Count (Doc))
   is
   begin
      Found := False;
      if Ex.Block /= 0 and then S in 1 .. Ast.Scenario_Count (Doc) then
         Ex := Expand.Next_Example (Doc, S, Ex);
         if Ex.Block /= 0 then
            Found := True;
            return;
         end if;
      end if;
      while S < Ast.Scenario_Count (Doc) loop
         pragma Loop_Variant (Increases => S);
         S := S + 1;
         if Ast.Scenario (Doc, S).Kind = Ast.Plain then
            Ex := (others => <>);
         else
            Ex := Expand.First_Example (Doc, S);
         end if;
         Found := Ast.Scenario (Doc, S).Kind = Ast.Plain or else Ex.Block /= 0;
         exit when Found;
      end loop;
   end Next_Position;

   --  The scenario's name as reported: an outline's is substituted from
   --  its data row, or kept as written when that would not fit.
   function Scenario_Name
     (Doc : Ast.Document; S : Ast.Scenario_Index; Ex : Expand.Example_Ref)
      return String
   is (declare
         Name : constant Ast.Slice := Ast.Scenario (Doc, S).Head.Name;
         Done : constant Expand.Text_Result :=
           Expand.Resolved (Doc, Name, Ex.Header_Row, Ex.Data_Row);
       begin
         (if Done.Ok then Expand.Value (Done) else Ast.Text (Doc, Name)))
   with Pre => S <= Ast.Scenario_Count (Doc);

   --  The scenario's line: its header's, or its data row's.
   function Scenario_Line
     (Doc : Ast.Document; S : Ast.Scenario_Index; Ex : Expand.Example_Ref)
      return Natural
   is (if Ex.Data_Row /= 0
       then Expand.Concrete_Line (Doc, Ex.Data_Row)
       else Ast.Scenario (Doc, S).Head.Line)
   with Pre => S <= Ast.Scenario_Count (Doc);

   function Line_Selected
     (Lines : Line_Selection; Line : Natural) return Boolean
   is (Lines.Count = 0
       or else (for some I in 1 .. Lines.Count => Lines.Lines (I) = Line));

   --  The -n patterns and the file:line selection keep the scenario.
   --  Both are checked before any hook runs.
   function Passes_Filters (R : Runner) return Boolean
   is (Line_Selected
         (R.Lines, Scenario_Line (R.Doc.all, R.Scenario, R.Example))
       and then Names.Matches_Any
                  (Scenario_Name (R.Doc.all, R.Scenario, R.Example),
                   Name_Patterns (R.Opts)))
   with
     Pre =>
       R.Doc /= null
       and then R.Scenario in 1 .. Ast.Scenario_Count (R.Doc.all);

   procedure Seek_Scenario (R : in out Runner; Found : out Boolean) is
      S  : Ast.Scenario_Handle := R.Scenario;
      Ex : Expand.Example_Ref := R.Example;
   begin
      Found := False;
      if R.Doc = null then
         return;
      end if;
      loop
         Next_Position (R.Doc.all, S, Ex, Found);
         R.Scenario := S;
         R.Example := Ex;
         exit when not Found or else Passes_Filters (R);
      end loop;
   end Seek_Scenario;

   --  The tag filter keeps the scenario; it is applied only after the
   --  scenario's before-hooks have run.  An untagged scenario evaluates
   --  the filter against the empty set.
   function Filter_Selects (R : Runner) return Boolean
   is (not R.Opts.Has_Filter
       or else not Tags.Valid (R.Opts.Filter)
       or else Selects (R.Doc.all, R.Tag_Set, R.Opts.Filter))
   with
     Pre =>
       R.Doc /= null
       and then R.Scenario in 1 .. Ast.Scenario_Count (R.Doc.all);

   ---------------------------------------------------------------------
   --  Steps: the background's, then the scenario's own.
   ---------------------------------------------------------------------

   function Background_Steps (Doc : Ast.Document) return Ast.Step_Range
   is (if Ast.Feature (Doc).Has_Background
       then Ast.Background (Doc).Steps
       else (First => 1, Last => 0));

   --  Moves In_Bg and Step to the scenario's next step; Step 0 means
   --  none has run yet.
   procedure Next_Step_Position
     (Doc   : Ast.Document;
      S     : Ast.Scenario_Index;
      In_Bg : in out Boolean;
      Step  : in out Ast.Step_Handle;
      Found : out Boolean)
   with
     Pre  => S <= Ast.Scenario_Count (Doc),
     Post => (if Found then Step in 1 .. Ast.Step_Count (Doc))
   is
      Bg  : constant Ast.Step_Range := Background_Steps (Doc);
      Own : constant Ast.Step_Range := Ast.Scenario (Doc, S).Steps;
   begin
      Found := False;
      if Step /= 0 and then Step < (if In_Bg then Bg.Last else Own.Last) then
         Step := Step + 1;
      elsif Step = 0 and then Bg.First <= Bg.Last then
         In_Bg := True;
         Step := Bg.First;
      elsif (Step = 0 or else In_Bg) and then Own.First <= Own.Last then
         In_Bg := False;
         Step := Own.First;
      else
         return;
      end if;
      Found := Step in 1 .. Ast.Step_Count (Doc);
   end Next_Step_Position;

   --  The outline row a scenario step substitutes from; a background
   --  step and a plain scenario's steps substitute nothing.
   function Header_Of (R : Runner) return Ast.Examples_Row_Handle
   is (if R.In_Background then 0 else R.Example.Header_Row);

   function Data_Of (R : Runner) return Ast.Examples_Row_Handle
   is (if R.In_Background then 0 else R.Example.Data_Row);

   --  Expands the current step, looks up its definition and checks it
   --  fits.  An undefined step reports its text as written.
   procedure Resolve (R : in out Runner)
   with Pre => R.Doc /= null and then R.Step in 1 .. Ast.Step_Count (R.Doc.all)
   is
      Node : constant Ast.Step_Node := Ast.Step (R.Doc.all, R.Step);
   begin
      R.Text :=
        Expand.Resolved (R.Doc.all, Node.Text, Header_Of (R), Data_Of (R));
      R.Match := (others => <>);
      if R.Text.Ok and then Tables_Valid then
         R.Match := Reg.Find (Steps, Expand.Value (R.Text));
      end if;
      R.Ctx.Text_Ok := R.Text.Ok;
      R.Ctx.Found := R.Match.Found;
      R.Ctx.Args_Fit :=
        Expand.Step_Fits (R.Doc.all, Node, Header_Of (R), Data_Of (R));
      R.Ctx.Step_Failed := False;
      R.Step_Outcome := (others => <>);
      Frames.Set
        (R.Frame.Step,
         (if R.Match.Found
          then Expand.Value (R.Text)
          else Ast.Text (R.Doc.all, Node.Text)));
      R.Frame.Step_Line := Node.Line;
   end Resolve;

   procedure Seek_Step (R : in out Runner; Found : out Boolean) is
      In_Bg : Boolean := R.In_Background;
      Step  : Ast.Step_Handle := R.Step;
   begin
      Found := False;
      if R.Doc /= null
        and then R.Scenario in 1 .. Ast.Scenario_Count (R.Doc.all)
      then
         Next_Step_Position (R.Doc.all, R.Scenario, In_Bg, Step, Found);
         R.In_Background := In_Bg;
         R.Step := Step;
      end if;
      if Found then
         Resolve (R);
      else
         R.Frame.Step := (others => <>);
         R.Frame.Step_Line := 0;
      end if;
   end Seek_Step;

   --  Builds the step request's arguments from the resolved step.
   procedure Assemble (R : in out Runner) is
   begin
      if R.Doc = null or else R.Step not in 1 .. Ast.Step_Count (R.Doc.all)
      then
         return;
      end if;
      R.Step_Arguments := Args.Make (Expand.Value (R.Text), R.Match.Captures);
      Args.Attach
        (R.Step_Arguments,
         R.Doc,
         Ast.Step (R.Doc.all, R.Step).Doc,
         Ast.Step (R.Doc.all, R.Step).Table);
      if Header_Of (R) /= 0 and then Data_Of (R) /= 0 then
         Args.Set_Example (R.Step_Arguments, Header_Of (R), Data_Of (R));
      end if;
   end Assemble;

   ---------------------------------------------------------------------
   --  The core's acts.
   ---------------------------------------------------------------------

   procedure Notify (R : in out Runner; N : Notice) is
   begin
      R.Note := N;
      R.Noticed := True;
   end Notify;

   procedure Open (R : in out Runner) is
   begin
      R.Ctx.Selected := True;
      R.Ctx.Ignored := False;
      R.Ctx.Skipped := False;
      R.Ctx.Failed := False;
      R.Ctx.Last_Passed := True;
      R.Ctx.Step_Failed := False;
      R.Tally := (others => 0);
      R.Scenario_Outcome := (others => <>);
      R.In_Background := False;
      R.Step := 0;
      R.Frame.Scenario := (others => <>);
      R.Frame.Scenario_Line := 0;
      R.Frame.Step := (others => <>);
      R.Frame.Step_Line := 0;
      if R.Doc /= null
        and then R.Scenario in 1 .. Ast.Scenario_Count (R.Doc.all)
      then
         R.Tag_Set :=
           Expand.Effective_Tags (R.Doc.all, R.Scenario, R.Example.Block);
         Frames.Set
           (R.Frame.Scenario,
            Scenario_Name (R.Doc.all, R.Scenario, R.Example));
         R.Frame.Scenario_Line :=
           Scenario_Line (R.Doc.all, R.Scenario, R.Example);
         R.Ctx.Selected := Filter_Selects (R);
      end if;
      Notify
        (R,
         (Kind     => Scenario_Opened,
          Scenario => R.Scenario,
          Data_Row => R.Example.Data_Row,
          others   => <>));
   end Open;

   --  A dry run, or a failed Before_All in a run that stops on failure,
   --  skips every step; the scenario's hooks still run.
   procedure Enter (R : in out Runner) is
   begin
      if R.Opts.Dry_Run or else (R.Before_All_Fail and then not R.Ctx.Continue)
      then
         R.Ctx.Skipped := True;
      end if;
      Notify
        (R,
         (Kind     => Scenario_Entered,
          Scenario => R.Scenario,
          Data_Row => R.Example.Data_Row,
          others   => <>));
   end Enter;

   procedure Close_Step_As
     (R : in out Runner; Status : Results.Status; Cause : Step_Cause) is
   begin
      Results.Add_Step (R.Tally, Status);
      R.Ctx.Last_Passed := Status = Results.Passed;
      Notify
        (R,
         (Kind     => Step_Closed,
          Status   => Status,
          Dropped  => False,
          Cause    => Cause,
          Scenario => R.Scenario,
          Data_Row => R.Example.Data_Row,
          Step     => R.Step,
          Outcome  => R.Step_Outcome));
   end Close_Step_As;

   --  A step that is not run: undefined when no definition matched its
   --  text, skipped otherwise.
   procedure Pass_Over_Step (R : in out Runner) is
   begin
      if R.Ctx.Text_Ok and then not R.Ctx.Found then
         Close_Step_As (R, Results.Undefined, No_Definition);
      else
         Close_Step_As (R, Results.Skipped, Not_Run);
      end if;
   end Pass_Over_Step;

   procedure Refuse (R : in out Runner) is
   begin
      Check.Record_Failure (R.Step_Outcome, Too_Long_Message);
      Close_Step_As (R, Results.Failed, Too_Long_Expansion);
   end Refuse;

   function Plus (A, B : Natural) return Natural
   is (if A > Natural'Last - B then Natural'Last else A + B);

   --  Adds one scenario's step counts to the run's.
   procedure Commit (Totals : in out Results.Counts; Tally : Results.Counts) is
   begin
      Totals.Steps_Passed := Plus (Totals.Steps_Passed, Tally.Steps_Passed);
      Totals.Steps_Failed := Plus (Totals.Steps_Failed, Tally.Steps_Failed);
      Totals.Steps_Skipped := Plus (Totals.Steps_Skipped, Tally.Steps_Skipped);
      Totals.Steps_Undefined :=
        Plus (Totals.Steps_Undefined, Tally.Steps_Undefined);
   end Commit;

   --  A scenario fails on its own failure or on a failed or undefined
   --  step; otherwise a skip leaves it skipped.
   function Scenario_Status (R : Runner) return Results.Status
   is (if R.Ctx.Failed
         or else R.Tally.Steps_Failed > 0
         or else R.Tally.Steps_Undefined > 0
       then Results.Failed
       elsif R.Ctx.Skipped
       then Results.Skipped
       else Results.Passed);

   procedure Close (R : in out Runner) is
      Status : constant Results.Status := Scenario_Status (R);
   begin
      Commit (R.Totals, R.Tally);
      Results.Add_Scenario (R.Totals, Status);
      Notify
        (R,
         (Kind     => Scenario_Closed,
          Status   => Status,
          Scenario => R.Scenario,
          Data_Row => R.Example.Data_Row,
          Outcome  => R.Scenario_Outcome,
          others   => <>));
   end Close;

   procedure Drop (R : in out Runner) is
   begin
      Notify
        (R,
         (Kind     => Scenario_Closed,
          Dropped  => True,
          Scenario => R.Scenario,
          Data_Row => R.Example.Data_Row,
          others   => <>));
   end Drop;

   --  The Document is released: nothing in R designates it any more.
   procedure Release (R : in out Runner) is
   begin
      R.Doc := null;
      R.Scenario := 0;
      R.Example := (others => <>);
      R.Step := 0;
      R.Step_Arguments := Args.Make ("", (others => <>));
   end Release;

   --  Counts one hook error for an all-hook phase that failed.
   procedure Close_Phase (R : in out Runner; Failed : Boolean) is
   begin
      if Failed then
         Results.Add_Hook_Error (R.Totals);
      end if;
   end Close_Phase;

   procedure Perform (R : in out Runner) is
   begin
      case R.Ctx.Due is
         when Nothing | Ask_Before_All | Ask_After_All | Ask_Hook =>
            null;

         when Ask_Step                                            =>
            Assemble (R);

         when Open_Scenario                                       =>
            Open (R);

         when Enter_Scenario                                      =>
            Enter (R);

         when Pass_Over                                           =>
            Pass_Over_Step (R);

         when Mark_Undefined                                      =>
            Close_Step_As (R, Results.Undefined, No_Definition);

         when Refuse_Step                                         =>
            Refuse (R);

         when Close_Step                                          =>
            Close_Step_As
              (R,
               (if R.Ctx.Step_Failed then Results.Failed else Results.Passed),
               Executed);

         when Close_Scenario                                      =>
            Close (R);

         when Drop_Scenario                                       =>
            Drop (R);

         when Close_Feature                                       =>
            Release (R);

         when Close_Opening                                       =>
            R.Before_All_Fail := R.Opening_Failed;
            Close_Phase (R, R.Opening_Failed);

         when Close_Run                                           =>
            Close_Phase (R, R.Closing_Failed);
      end case;
   end Perform;

   ---------------------------------------------------------------------
   --  The engine loop.
   ---------------------------------------------------------------------

   procedure Fire (R : in out Runner; Kind : Event_Kind; Handled : out Boolean)
   is
   begin
      R.Ctx.Due := Nothing;
      SM.Process_Event (R.Machine, R.Ctx, (Kind => Kind), Handled);
      if Handled then
         Perform (R);
      end if;
   end Fire;

   --  One machine step from the cursor of the current state; Moved is
   --  False where only the shell can move the runner on.
   procedure Move (R : in out Runner; Moved : out Boolean) is
      Found : Boolean;
   begin
      Moved := False;
      case State_Of (R) is
         when Opening | Before | Step_Before | Step_After | After | Closing =>
            R.Hook := Next_Hook (R);
            Fire
              (R, (if R.Hook /= 0 then E_Hook_Due else E_Hooks_Done), Moved);

         when Walking                                                       =>
            Seek_Scenario (R, Found);
            Fire
              (R, (if Found then E_Scenario_Due else E_Scenarios_Done), Moved);

         when Stepping                                                      =>
            Seek_Step (R, Found);
            Fire (R, (if Found then E_Step_Due else E_Steps_Done), Moved);

         when Ready | Step_Body | Finished                                  =>
            null;
      end case;
   end Move;

   --  Runs the machine until a request or a notice waits for the shell,
   --  or only the shell can move it on.
   procedure Advance (R : in out Runner) is
      Moved : Boolean := True;
   begin
      while Moved
        and then not R.Noticed
        and then R.Ctx.Requests.Pending = C_None
      loop
         Move (R, Moved);
      end loop;
   end Advance;

   --  Fires one of the shell's own events, then advances.
   procedure Trigger (R : in out Runner; Kind : Event_Kind) is
      Handled : Boolean;
   begin
      Fire (R, Kind, Handled);
      if Handled then
         Advance (R);
      end if;
   end Trigger;

   ---------------------------------------------------------------------
   --  The driver surface.
   ---------------------------------------------------------------------

   procedure Start_Run (R : out Runner; Opts : Options) is
   begin
      R :=
        (Machine => Started,
         Ctx     => (Continue => Opts.Continue_On_Failure, others => <>),
         Opts    => Opts,
         Doc     => null,
         Lines   => All_Lines,
         others  => <>);
      Advance (R);
   end Start_Run;

   procedure Start_Feature
     (R     : in out Runner;
      Doc   : Args.Document_Access;
      File  : String;
      Lines : Line_Selection) is
   begin
      R.Doc := Doc;
      R.Lines := Lines;
      R.Scenario := 0;
      R.Example := (others => <>);
      R.Frame := (others => <>);
      Frames.Set (R.Frame.File, File);
      Frames.Set
        (R.Frame.Feature, Ast.Text (Doc.all, Ast.Feature (Doc.all).Head.Name));
      R.Frame.Feature_Line := Ast.Feature (Doc.all).Head.Line;
      Trigger (R, E_Feature);
   end Start_Feature;

   procedure Note_Parse_Error (R : in out Runner) is
   begin
      Results.Add_Parse_Error (R.Totals);
   end Note_Parse_Error;

   procedure Finish_Run (R : in out Runner) is
   begin
      R.Frame := (others => <>);
      Trigger (R, E_Finish);
   end Finish_Run;

   procedure Resume (R : in out Runner) is
   begin
      R.Noticed := False;
      Advance (R);
   end Resume;

   procedure Fail_Scenario (R : in out Runner; Outcome : Check.Outcome) is
   begin
      R.Ctx.Failed := True;
      R.Scenario_Outcome := Outcome;
   end Fail_Scenario;

   --  A skip, an ignore or a scenario failure, from any hook or step.
   procedure Take_Order (R : in out Runner; Outcome : Check.Outcome) is
   begin
      case Outcome.Order is
         when Check.Continue        =>
            null;

         when Check.Skip_Scenario   =>
            R.Ctx.Skipped := True;

         when Check.Ignore_Scenario =>
            R.Ctx.Ignored := True;

         when Check.Fail_Scenario   =>
            Fail_Scenario (R, Outcome);
      end case;
   end Take_Order;

   --  A step's own outcome, or a step hook's: a failure fails the step.
   procedure Take_Step_Outcome (R : in out Runner; Outcome : Check.Outcome) is
   begin
      if not Outcome.Passing then
         R.Ctx.Step_Failed := True;
         R.Step_Outcome := Outcome;
      end if;
      Take_Order (R, Outcome);
   end Take_Step_Outcome;

   --  A scenario hook's outcome: a failure fails the scenario itself.
   procedure Take_Scenario_Outcome (R : in out Runner; Outcome : Check.Outcome)
   is
   begin
      if not Outcome.Passing then
         Fail_Scenario (R, Outcome);
      end if;
      Take_Order (R, Outcome);
   end Take_Scenario_Outcome;

   procedure Post_Hook_Result (R : in out Runner; Outcome : Check.Outcome) is
   begin
      R.Ctx.Requests.Pending := C_None;
      case State_Of (R) is
         when Opening        =>
            R.Opening_Failed := R.Opening_Failed or else not Outcome.Passing;

         when Closing        =>
            R.Closing_Failed := R.Closing_Failed or else not Outcome.Passing;

         when Before | After =>
            Take_Scenario_Outcome (R, Outcome);

         when others         =>
            Take_Step_Outcome (R, Outcome);
      end case;
      Advance (R);
   end Post_Hook_Result;

   procedure Post_Step_Result (R : in out Runner; Outcome : Check.Outcome) is
   begin
      R.Ctx.Requests.Pending := C_None;
      Take_Step_Outcome (R, Outcome);
      Trigger (R, E_Posted);
   end Post_Step_Result;

end Fabula.Run;
