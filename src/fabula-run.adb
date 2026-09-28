with Fabula.Names;
with Sml.Machines.Operators;

package body Fabula.Run
  with SPARK_Mode
is

   use type Ast.Scenario_Handle;
   use type Ast.Scenario_Kind;
   use type Expand.Walk_Status;
   use type Reg.Hook_Phase;
   use type Results.Status;
   use type Step_Walk.Segment;

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
   Hook_Posted    : constant Ev := (Kind => E_Hook_Posted);
   Step_Posted    : constant Ev := (Kind => E_Step_Posted);

   --  Each row reads:  From + Event (Guard) / Act >= To.  Rows for one
   --  state are tried top to bottom, so a guarded row takes its event
   --  before the rows below it.  A hook phase ends when its cursor finds
   --  no further row; a scenario's steps end the same way.  Each act
   --  does its own work, and an Ask_* act writes its request.  Each
   --  hook state's Hook_Posted row names the act for its phase, so the
   --  row decides where a hook's outcome goes.  The line above each
   --  block names the guard flags its acts write.
   --!format off
   Table : constant SM.Transition_Table (1 .. Rows) :=
     [
      --  The run's Before_All hooks; then features, one at a time.
      --  Writes: Before_All_Failed, Selected, Ignored, Standing,
      --  Last_Passed, Step_Failed.
      Opening + Hook_Due                       / Ask_Before_All   >= Opening,
      Opening + Hook_Posted                    / Take_Run_Start   >= Opening,
      Opening + Hooks_Done (Before_All_Failed) / Count_Hook_Error >= Ready,
      Opening + Hooks_Done                                        >= Ready,
      Ready   + Feature                                           >= Walking,
      Ready   + Finish                                            >= Closing,
      Walking + Scenario_Due                   / Open_Scenario    >= Before,
      Walking + Scenarios_Done                 / Close_Feature    >= Ready,

      --  One scenario: its before-hooks, then its steps.  The tag
      --  filter and an ignore both drop it once the hooks have run.
      --  Writes: Standing, Ignored, Last_Passed.
      Before   + Hook_Due               / Ask_Hook            >= Before,
      Before   + Hook_Posted            / Take_Scenario_Start >= Before,
      Before   + Hooks_Done (Dropped)   / Drop_Unentered      >= Walking,
      Before   + Hooks_Done (Skips_All) / Enter_Skipped       >= Stepping,
      Before   + Hooks_Done             / Enter_Scenario      >= Stepping,
      Stepping + Step_Due (Dropped)     / Drop_Entered        >= Walking,
      Stepping + Step_Due (Unmatched)   / Mark_Undefined      >= Stepping,
      Stepping + Step_Due (Must_Skip)   / Skip_Step           >= Stepping,
      Stepping + Step_Due (Oversized)   / Refuse_Step         >= Stepping,
      Stepping + Step_Due                                     >= Step_Before,
      Stepping + Steps_Done (Dropped)   / Drop_Entered        >= Walking,
      Stepping + Steps_Done (Failing)   / Close_Scenario      >= Walking,
      Stepping + Steps_Done                                   >= After,

      --  One step: its before-step hooks, its body, its after-step
      --  hooks.  A failed before-step hook closes it at once.
      --  Writes: Step_Failed, Standing, Ignored, Last_Passed.
      Step_Before + Hook_Due                 / Ask_Hook         >= Step_Before,
      Step_Before + Hook_Posted              / Take_Step_Start  >= Step_Before,
      Step_Before + Hooks_Done (Step_Failed) / Fail_Step        >= Stepping,
      Step_Before + Hooks_Done               / Ask_Step         >= Step_Body,
      Step_Body   + Step_Posted              / Take_Step_Result >= Step_After,
      Step_After  + Hook_Due                 / Ask_Hook         >= Step_After,
      Step_After  + Hook_Posted              / Take_Step_End    >= Step_After,
      Step_After  + Hooks_Done (Step_Failed) / Fail_Step        >= Stepping,
      Step_After  + Hooks_Done               / Pass_Step        >= Stepping,

      --  The scenario's after-hooks; an ignore there still drops it.
      --  Writes: Standing, Ignored.
      After + Hook_Due             / Ask_Hook          >= After,
      After + Hook_Posted          / Take_Scenario_End >= After,
      After + Hooks_Done (Dropped) / Drop_Entered      >= Walking,
      After + Hooks_Done           / Close_Scenario    >= Walking,

      --  The run's After_All hooks.
      --  Writes: After_All_Failed.
      Closing + Hook_Due                      / Ask_After_All    >= Closing,
      Closing + Hook_Posted                   / Take_Run_End     >= Closing,
      Closing + Hooks_Done (After_All_Failed) / Count_Hook_Error >= Finished,
      Closing + Hooks_Done                                       >= Finished];
   --!format on

   function Started return SM.Machine
   is (SM.Make (Table, Initial => Opening))
   with Post => Started'Result.Count = Rows;

   ---------------------------------------------------------------------
   --  The machine's guards.  A guard reads the context and an act does
   --  its work there; which event arrived is the table's business, so
   --  neither reads Evt.
   ---------------------------------------------------------------------

   function Evaluate (G : Guard_Kind; Ctx : Work; Evt : Event) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      case G is
         when Always            =>
            return True;

         when Dropped           =>
            return Ctx.Ignored or else not Ctx.Selected;

         when Skips_All         =>
            return
              Ctx.Opts.Dry_Run
              or else (Ctx.Before_All_Failed
                       and then not Ctx.Opts.Continue_On_Failure);

         when Unmatched         =>
            return Ctx.Text.Ok and then not Ctx.Match.Found;

         when Must_Skip         =>
            return
              Ctx.Standing /= Running
              or else (not Ctx.Opts.Continue_On_Failure
                       and then not Ctx.Last_Passed);

         when Oversized         =>
            return not Ctx.Text.Ok or else not Ctx.Args_Fit;

         when Step_Failed       =>
            return Ctx.Step_Failed;

         when Failing           =>
            return Ctx.Standing = Failed;

         when Before_All_Failed =>
            return Ctx.Before_All_Failed;

         when After_All_Failed  =>
            return Ctx.After_All_Failed;
      end case;
   end Evaluate;

   ---------------------------------------------------------------------
   --  Options.
   ---------------------------------------------------------------------

   procedure Set_Names (Opts : in out Options; Patterns : String) is
   begin
      Opts.Names := Texts.Truncated (Patterns, Limits.Max_Name_Filter_Length);
   end Set_Names;

   procedure Add_Line (Selection : in out Line_Selection; Line : Source_Line)
   is
   begin
      Selection.Count := Selection.Count + 1;
      Selection.Lines (Selection.Count) := Line;
   end Add_Line;

   ---------------------------------------------------------------------
   --  Hooks: the cursor walks the table in order, one phase at a time.
   ---------------------------------------------------------------------

   function State_Of (R : Runner) return State
   is (Bundle.State_Of (R.Run));

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
   function Hook_Selected (Ctx : Work; I : Positive) return Boolean
   is (not Reg.Has_Tag_Expr (Hooks, I)
       or else (Ctx.Doc /= null
                and then Tags.Valid (Reg.Tag_Expr (Hooks, I))
                and then Selects
                           (Ctx.Doc.all,
                            Ctx.Tag_Set,
                            Reg.Tag_Expr (Hooks, I))))
   with Pre => I in Hooks'Range;

   --  The first row after Ctx.Hook that runs in Phase, or No_Row.
   function Next_Hook (Ctx : Work; Phase : Reg.Hook_Phase) return Natural
   with
     Post => Next_Hook'Result = No_Row or else Next_Hook'Result in Hooks'Range
   is
      function Runs_Next (I : Positive) return Boolean
      is (I in Hooks'Range
          and then I > Ctx.Hook
          and then Reg.Phase_Of (Hooks, I) = Phase
          and then Hook_Selected (Ctx, I));

      function First_Next is new Searches.Find_First (Runs_Next);
   begin
      if Hooks'Length = 0 then
         return No_Row;
      end if;
      return First_Next (Hooks'First, Hooks'Last);
   end Next_Hook;

   function Pending_Hook_Kind (R : Runner) return Reg.Hook_Kind
   is (if R.Run.Ctx.Hook in Hooks'Range
       then Reg.Kind_Of (Hooks, R.Run.Ctx.Hook)
       else Reg.Hook_Kind'First);

   function Pending_Step_Kind (R : Runner) return Reg.Step_Kind
   is (if R.Run.Ctx.Match.Index in Steps'Range
       then Reg.Kind_Of (Steps, R.Run.Ctx.Match.Index)
       else Reg.Step_Kind'First);

   ---------------------------------------------------------------------
   --  Scenarios: every plain scenario, and every data row of every
   --  outline, in file order.
   ---------------------------------------------------------------------

   --  Where the scenario walk stands: the scenario, the outline row due
   --  in it (none for a plain scenario), and whether a position was
   --  found at all.
   type Scenario_Position is record
      Found    : Boolean := False;
      Scenario : Ast.Scenario_Handle := Ast.No_Scenario;
      Example  : Expand.Example_Ref;
   end record;

   --  A position that names a scenario of Doc when it was found.
   function In_Document
     (Doc : Ast.Document; P : Scenario_Position) return Boolean
   is (if P.Found then P.Scenario in 1 .. Ast.Scenario_Count (Doc));

   --  From S and Ex, the outline's next data row, when S is an outline
   --  with a current row; else S and Ex as they are, not found.
   function Next_Row
     (Doc : Ast.Document; S : Ast.Scenario_Handle; Ex : Expand.Example_Ref)
      return Scenario_Position
   is (if Ex.Status = Expand.Row_Due
         and then S in 1 .. Ast.Scenario_Count (Doc)
       then
         (declare
            Next : constant Expand.Example_Ref :=
              Expand.Next_Example (Doc, S, Ex);
          begin
            (Found    => Next.Status = Expand.Row_Due,
             Scenario => S,
             Example  => Next))
       else (Found => False, Scenario => S, Example => Ex))
   with Post => In_Document (Doc, Next_Row'Result);

   --  From S, the next plain scenario or the next outline with a data
   --  row, with that outline's first row.  When no scenario follows S,
   --  From as it is, not found.
   function Next_Scenario
     (Doc : Ast.Document; From : Scenario_Position) return Scenario_Position
   with Post => In_Document (Doc, Next_Scenario'Result)
   is
      Result : Scenario_Position := (From with delta Found => False);
   begin
      while Result.Scenario < Ast.Scenario_Count (Doc) loop
         pragma Loop_Invariant (not Result.Found);
         pragma Loop_Variant (Increases => Result.Scenario);
         Result.Scenario := Result.Scenario + 1;
         Result.Example :=
           (if Ast.Scenario (Doc, Result.Scenario).Kind = Ast.Plain
            then Expand.No_Example
            else Expand.First_Example (Doc, Result.Scenario));
         Result.Found :=
           Ast.Scenario (Doc, Result.Scenario).Kind = Ast.Plain
           or else Result.Example.Status = Expand.Row_Due;
         exit when Result.Found;
      end loop;
      return Result;
   end Next_Scenario;

   --  The next scenario position after S and Ex: the outline's next data
   --  row, else the next scenario.  A plain scenario has no row due.
   function Next_Position
     (Doc : Ast.Document; S : Ast.Scenario_Handle; Ex : Expand.Example_Ref)
      return Scenario_Position
   is (declare
         In_Outline : constant Scenario_Position := Next_Row (Doc, S, Ex);
       begin
         (if In_Outline.Found
          then In_Outline
          else Next_Scenario (Doc, In_Outline)))
   with Post => In_Document (Doc, Next_Position'Result);

   --  The scenario's name as reported: an outline's is substituted from
   --  its data row, or kept as written when that would not fit.
   function Scenario_Name
     (Doc : Ast.Document; S : Ast.Scenario_Index; Ex : Expand.Example_Ref)
      return String
   is (declare
         Name : constant Ast.Slice := Ast.Scenario (Doc, S).Head.Name;
       begin
         Expand.Value_Or
           (Expand.Resolved
              (Doc, Name, Expand.Header_Row_Of (Ex), Expand.Data_Row_Of (Ex)),
            Ast.Text (Doc, Name)))
   with Pre => S <= Ast.Scenario_Count (Doc);

   --  The scenario's line: its header's, or its data row's.
   function Scenario_Line
     (Doc : Ast.Document; S : Ast.Scenario_Index; Ex : Expand.Example_Ref)
      return Line_Number
   is (if Ex.Status = Expand.Row_Due
       then Expand.Concrete_Line (Doc, Ex.Data_Row)
       else Ast.Scenario (Doc, S).Head.Line)
   with Pre => S <= Ast.Scenario_Count (Doc);

   function Line_Selected
     (Lines : Line_Selection; Line : Line_Number) return Boolean
   is (Lines.Count = None_Selected
       or else (for some I in 1 .. Lines.Count => Lines.Lines (I) = Line));

   --  The -n patterns and the file:line selection keep the scenario.
   --  Both are checked before any hook runs.
   function Passes_Filters (Ctx : Work) return Boolean
   is (Line_Selected
         (Ctx.Lines, Scenario_Line (Ctx.Doc.all, Ctx.Scenario, Ctx.Example))
       and then Names.Matches_Any
                  (Scenario_Name (Ctx.Doc.all, Ctx.Scenario, Ctx.Example),
                   Name_Patterns (Ctx.Opts)))
   with
     Pre =>
       Ctx.Doc /= null
       and then Ctx.Scenario in 1 .. Ast.Scenario_Count (Ctx.Doc.all);

   --  Moves to the next scenario position both filters keep.
   procedure Seek_Scenario (Ctx : in out Work; Found : out Boolean) is
      Next : Scenario_Position;
   begin
      Found := Ctx.Doc /= null;
      while Found loop
         pragma Loop_Invariant (Ctx.Doc /= null);
         Next := Next_Position (Ctx.Doc.all, Ctx.Scenario, Ctx.Example);
         Ctx.Scenario := Next.Scenario;
         Ctx.Example := Next.Example;
         Found := Next.Found;
         exit when not Found or else Passes_Filters (Ctx);
      end loop;
   end Seek_Scenario;

   --  The tag filter keeps the scenario; it is applied only after the
   --  scenario's before-hooks have run.  An untagged scenario evaluates
   --  the filter against the empty set.
   function Filter_Selects (Ctx : Work) return Boolean
   is (not Ctx.Opts.Has_Filter
       or else not Tags.Valid (Ctx.Opts.Filter)
       or else Selects (Ctx.Doc.all, Ctx.Tag_Set, Ctx.Opts.Filter))
   with
     Pre =>
       Ctx.Doc /= null
       and then Ctx.Scenario in 1 .. Ast.Scenario_Count (Ctx.Doc.all);

   ---------------------------------------------------------------------
   --  Steps: the background's, then the scenario's own.
   ---------------------------------------------------------------------

   function Background_Steps (Doc : Ast.Document) return Ast.Step_Range
   is (if Ast.Feature (Doc).Has_Background
       then Ast.Background (Doc).Steps
       else (others => <>));

   --  The step the step cursor stands on.
   function Step_Of (Ctx : Work) return Ast.Step_Handle
   is (Step_Walk.Step_Of (Ctx.Walk));

   --  The outline row a scenario step substitutes from; a background
   --  step and a plain scenario's steps substitute nothing.
   function Header_Of (Ctx : Work) return Ast.Examples_Row_Handle
   is (if Step_Walk.State_Of (Ctx.Walk) = Step_Walk.Background
       then Ast.No_Examples_Row
       else Expand.Header_Row_Of (Ctx.Example));

   function Data_Of (Ctx : Work) return Ast.Examples_Row_Handle
   is (if Step_Walk.State_Of (Ctx.Walk) = Step_Walk.Background
       then Ast.No_Examples_Row
       else Expand.Data_Row_Of (Ctx.Example));

   --  Expands the current step, looks up its definition and checks it
   --  fits.  An undefined step reports its text as written.
   procedure Resolve (Ctx : in out Work)
   with
     Pre =>
       Ctx.Doc /= null
       and then Step_Of (Ctx) in 1 .. Ast.Step_Count (Ctx.Doc.all)
   is
      Node : constant Ast.Step_Node := Ast.Step (Ctx.Doc.all, Step_Of (Ctx));
   begin
      Ctx.Text :=
        Expand.Resolved
          (Ctx.Doc.all, Node.Text, Header_Of (Ctx), Data_Of (Ctx));
      Ctx.Match := (others => <>);
      if Ctx.Text.Ok and then Tables_Valid then
         Ctx.Match := Reg.Find (Steps, Expand.Value (Ctx.Text));
      end if;
      Ctx.Args_Fit :=
        Expand.Step_Fits (Ctx.Doc.all, Node, Header_Of (Ctx), Data_Of (Ctx));
      Ctx.Step_Failed := False;
      Ctx.Step_Outcome := (others => <>);
      Ctx.Frame.Step :=
        Frames.To_Step
          (if Ctx.Match.Found
           then Expand.Value (Ctx.Text)
           else Ast.Text (Ctx.Doc.all, Node.Text));
      Ctx.Frame.Step_Line := Node.Line;
   end Resolve;

   --  Moves the step cursor to the scenario's next step; without a
   --  scenario nothing is found.  The walk decides Found.  The range
   --  check after it never changes the answer, as the walk's step count
   --  came from this same document when the scenario opened.  It is
   --  there for the prover, which cannot see that from here.
   procedure Move_Step_Cursor (Ctx : in out Work; Found : out Boolean)
   with
     Post =>
       (if Found
        then
          Ctx.Doc /= null
          and then Step_Of (Ctx) in 1 .. Ast.Step_Count (Ctx.Doc.all))
   is
   begin
      Step_Walk.Next (Ctx.Walk);
      Found :=
        Step_Walk.Found (Ctx.Walk)
        and then Ctx.Doc /= null
        and then Step_Of (Ctx) in 1 .. Ast.Step_Count (Ctx.Doc.all);
   end Move_Step_Cursor;

   --  The frame's step, cleared outside step execution.
   procedure Clear_Step (F : in out Frames.Frame) is
   begin
      F.Step := Frames.To_Step ("");
      F.Step_Line := No_Line;
   end Clear_Step;

   procedure Seek_Step (Ctx : in out Work; Found : out Boolean) is
   begin
      Move_Step_Cursor (Ctx, Found);
      if Found then
         Resolve (Ctx);
      else
         Clear_Step (Ctx.Frame);
      end if;
   end Seek_Step;

   --  Builds the step request's arguments from the resolved step.
   procedure Assemble (Ctx : in out Work) is
   begin
      if Ctx.Doc = null
        or else Step_Of (Ctx) not in 1 .. Ast.Step_Count (Ctx.Doc.all)
      then
         return;
      end if;
      Ctx.Step_Arguments :=
        Args.Make
          (Expand.Value (Ctx.Text),
           Ctx.Match.Captures,
           (Doc        => Ctx.Doc,
            Doc_String => Ast.Step (Ctx.Doc.all, Step_Of (Ctx)).Doc,
            Table      => Ast.Step (Ctx.Doc.all, Step_Of (Ctx)).Table,
            Header_Row => Header_Of (Ctx),
            Data_Row   => Data_Of (Ctx)));
   end Assemble;

   ---------------------------------------------------------------------
   --  The core's acts.
   ---------------------------------------------------------------------

   --  N waits for the shell, which reads it and resumes.
   procedure Notify (Ctx : in out Work; N : Notice) is
   begin
      Ctx.Note := N;
      Ctx.Noticed := True;
   end Notify;

   --  The frame keeps its file and feature; scenario and step go.
   function Feature_Only (F : Frames.Frame) return Frames.Frame
   is ((File         => F.File,
        Feature      => F.Feature,
        Feature_Line => F.Feature_Line,
        others       => <>));

   --  A new scenario's context: selected, running, no step failed or
   --  counted yet, no walk, and a frame with only the feature.
   function Fresh_Scenario (Ctx : Work) return Work
   is ((Ctx
        with delta
          Selected         => True,
          Ignored          => False,
          Standing         => Running,
          Last_Passed      => True,
          Step_Failed      => False,
          Tally            => (others => <>),
          Scenario_Outcome => (others => <>),
          Walk             => Step_Walk.Empty,
          Frame            => Feature_Only (Ctx.Frame)));

   --  The scenario's tags and frame, whether the tag filter keeps it,
   --  and the walk over its steps.
   procedure Load_Scenario (Ctx : in out Work) is
   begin
      if Ctx.Doc /= null
        and then Ctx.Scenario in 1 .. Ast.Scenario_Count (Ctx.Doc.all)
      then
         Ctx.Tag_Set :=
           Expand.Effective_Tags
             (Ctx.Doc.all, Ctx.Scenario, Expand.Block_Of (Ctx.Example));
         Ctx.Frame.Scenario :=
           Frames.To_Name
             (Scenario_Name (Ctx.Doc.all, Ctx.Scenario, Ctx.Example));
         Ctx.Frame.Scenario_Line :=
           Scenario_Line (Ctx.Doc.all, Ctx.Scenario, Ctx.Example);
         Ctx.Selected := Filter_Selects (Ctx);
         Ctx.Walk :=
           Step_Walk.Started
             (Shared     => Background_Steps (Ctx.Doc.all),
              Mine       => Ast.Scenario (Ctx.Doc.all, Ctx.Scenario).Steps,
              Step_Count => Ast.Step_Count (Ctx.Doc.all));
      end if;
   end Load_Scenario;

   procedure Open (Ctx : in out Work) is
   begin
      Ctx := Fresh_Scenario (Ctx);
      Load_Scenario (Ctx);
      Notify
        (Ctx,
         (Kind     => Scenario_Opened,
          Scenario => Ctx.Scenario,
          Data_Row => Expand.Data_Row_Of (Ctx.Example),
          others   => <>));
   end Open;

   --  A skip never undoes a failure.
   procedure Skip (Ctx : in out Work) is
   begin
      Ctx.Standing := Disposition'Max (Ctx.Standing, Skipped);
   end Skip;

   procedure Enter (Ctx : in out Work) is
   begin
      Notify
        (Ctx,
         (Kind     => Scenario_Entered,
          Entered  => True,
          Scenario => Ctx.Scenario,
          Data_Row => Expand.Data_Row_Of (Ctx.Example),
          others   => <>));
   end Enter;

   procedure Close_Step_As
     (Ctx : in out Work; Status : Results.Status; Cause : Step_Cause) is
   begin
      Results.Add_Step (Ctx.Tally, Status);
      Ctx.Last_Passed := Status = Results.Passed;
      Notify
        (Ctx,
         (Kind     => Step_Closed,
          Status   => Status,
          Dropped  => False,
          Entered  => True,
          Cause    => Cause,
          Scenario => Ctx.Scenario,
          Data_Row => Expand.Data_Row_Of (Ctx.Example),
          Step     => Step_Of (Ctx),
          Outcome  => Ctx.Step_Outcome));
   end Close_Step_As;

   procedure Refuse (Ctx : in out Work) is
   begin
      Check.Record_Failure (Ctx.Step_Outcome, Too_Long_Message);
      Close_Step_As (Ctx, Results.Failed, Too_Long_Expansion);
   end Refuse;

   --  A scenario fails on its own failure or on a failed or undefined
   --  step; otherwise a skip leaves it skipped.
   function Scenario_Status (Ctx : Work) return Results.Status
   is (if Ctx.Standing = Failed
         or else Results.Counted (Ctx.Tally.Steps (Results.Failed))
         or else Results.Counted (Ctx.Tally.Steps (Results.Undefined))
       then Results.Failed
       elsif Ctx.Standing = Skipped
       then Results.Skipped
       else Results.Passed);

   procedure Close (Ctx : in out Work) is
      Status : constant Results.Status := Scenario_Status (Ctx);
   begin
      Ctx.Totals.Steps := Results.Sum (Ctx.Totals.Steps, Ctx.Tally.Steps);
      Results.Add_Scenario (Ctx.Totals, Status);
      Notify
        (Ctx,
         (Kind     => Scenario_Closed,
          Status   => Status,
          Entered  => True,
          Scenario => Ctx.Scenario,
          Data_Row => Expand.Data_Row_Of (Ctx.Example),
          Outcome  => Ctx.Scenario_Outcome,
          others   => <>));
   end Close;

   procedure Drop (Ctx : in out Work; Entered : Boolean) is
   begin
      Notify
        (Ctx,
         (Kind     => Scenario_Closed,
          Dropped  => True,
          Entered  => Entered,
          Scenario => Ctx.Scenario,
          Data_Row => Expand.Data_Row_Of (Ctx.Example),
          others   => <>));
   end Drop;

   --  The Document is released: nothing in Ctx designates it any more.
   procedure Release (Ctx : in out Work) is
   begin
      Ctx.Doc := null;
      Ctx.Scenario := Ast.No_Scenario;
      Ctx.Example := Expand.No_Example;
      Ctx.Walk := Step_Walk.Empty;
      Ctx.Step_Arguments := Args.Make ("", (others => <>));
   end Release;

   --  Each request act writes its own command; a step's request also
   --  carries the step's arguments.  No other act writes one: every
   --  event fires with no command pending, since Advance stops at one
   --  and the shell's answer clears it before it fires Hook_Posted or
   --  Step_Posted.
   procedure Ask_Shell (A : Request_Act; Ctx : in out Work) is
   begin
      case A is
         when Ask_Before_All =>
            Ctx.Requests.Pending := C_Before_All;

         when Ask_After_All  =>
            Ctx.Requests.Pending := C_After_All;

         when Ask_Hook       =>
            Ctx.Requests.Pending := C_Hook;

         when Ask_Step       =>
            Assemble (Ctx);
            Ctx.Requests.Pending := C_Step;
      end case;
   end Ask_Shell;

   --  The posted outcome fails the scenario.
   procedure Fail_Scenario (Ctx : in out Work) is
   begin
      Ctx.Standing := Failed;
      Ctx.Scenario_Outcome := Ctx.Answer;
   end Fail_Scenario;

   --  A skip, an ignore or a scenario failure, from any hook or step.
   procedure Take_Order (Ctx : in out Work) is
   begin
      case Ctx.Answer.Order is
         when Check.Continue        =>
            null;

         when Check.Skip_Scenario   =>
            Skip (Ctx);

         when Check.Ignore_Scenario =>
            Ctx.Ignored := True;

         when Check.Fail_Scenario   =>
            Fail_Scenario (Ctx);
      end case;
   end Take_Order;

   --  A step's own outcome, or a step hook's: a failure fails the step.
   procedure Take_Step_Outcome (Ctx : in out Work) is
   begin
      if not Ctx.Answer.Passing then
         Ctx.Step_Failed := True;
         Ctx.Step_Outcome := Ctx.Answer;
      end if;
      Take_Order (Ctx);
   end Take_Step_Outcome;

   --  A scenario hook's outcome: a failure fails the scenario itself.
   procedure Take_Scenario_Outcome (Ctx : in out Work) is
   begin
      if not Ctx.Answer.Passing then
         Fail_Scenario (Ctx);
      end if;
      Take_Order (Ctx);
   end Take_Scenario_Outcome;

   --  Each act applies the posted outcome as its phase requires: an
   --  all-hook phase remembers a failure, a scenario hook's reaches the
   --  scenario, a step hook's and the step body's the step.
   procedure Take_Result (A : Result_Act; Ctx : in out Work) is
   begin
      case A is
         when Take_Run_Start                                     =>
            Ctx.Before_All_Failed :=
              Ctx.Before_All_Failed or else not Ctx.Answer.Passing;

         when Take_Run_End                                       =>
            Ctx.After_All_Failed :=
              Ctx.After_All_Failed or else not Ctx.Answer.Passing;

         when Take_Scenario_Start | Take_Scenario_End            =>
            Take_Scenario_Outcome (Ctx);

         when Take_Step_Start | Take_Step_End | Take_Step_Result =>
            Take_Step_Outcome (Ctx);
      end case;
   end Take_Result;

   procedure Run_Scenario_Act (A : Scenario_Act; Ctx : in out Work) is
   begin
      case A is
         when Open_Scenario  =>
            Open (Ctx);

         when Enter_Scenario =>
            Enter (Ctx);

         when Enter_Skipped  =>
            Skip (Ctx);
            Enter (Ctx);

         when Close_Scenario =>
            Close (Ctx);

         when Drop_Unentered =>
            Drop (Ctx, Entered => False);

         when Drop_Entered   =>
            Drop (Ctx, Entered => True);
      end case;
   end Run_Scenario_Act;

   procedure Run_Step_Act (A : Step_Act; Ctx : in out Work) is
   begin
      case A is
         when Mark_Undefined =>
            Close_Step_As (Ctx, Results.Undefined, No_Definition);

         when Skip_Step      =>
            Close_Step_As (Ctx, Results.Skipped, Not_Run);

         when Refuse_Step    =>
            Refuse (Ctx);

         when Fail_Step      =>
            Close_Step_As (Ctx, Results.Failed, Executed);

         when Pass_Step      =>
            Close_Step_As (Ctx, Results.Passed, Executed);
      end case;
   end Run_Step_Act;

   procedure Run_Feature_Act (A : Feature_Act; Ctx : in out Work) is
   begin
      case A is
         when Close_Feature    =>
            Release (Ctx);

         when Count_Hook_Error =>
            Results.Add_Hook_Error (Ctx.Totals);
      end case;
   end Run_Feature_Act;

   procedure Execute (A : Act; Ctx : in out Work; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      case A is
         when Nothing      =>
            null;

         when Request_Act  =>
            Ask_Shell (A, Ctx);

         when Result_Act   =>
            Take_Result (A, Ctx);

         when Scenario_Act =>
            Run_Scenario_Act (A, Ctx);

         when Step_Act     =>
            Run_Step_Act (A, Ctx);

         when Feature_Act  =>
            Run_Feature_Act (A, Ctx);
      end case;
   end Execute;

   ---------------------------------------------------------------------
   --  The engine loop.
   ---------------------------------------------------------------------

   --  One machine step from the cursor of the current state; Moved is
   --  False where only the shell can move the runner on.
   procedure Move (R : in out Runner; Moved : out Boolean) is
      Fact  : constant State_Fact := Facts (State_Of (R));
      Found : Boolean;
   begin
      Moved := False;
      case Fact.Cursor is
         when Hook_Cursor     =>
            R.Run.Ctx.Hook := Next_Hook (R.Run.Ctx, Fact.Phase);
            Bundle.Process_Event
              (R.Run,
               (Kind =>
                  (if R.Run.Ctx.Hook /= No_Row
                   then E_Hook_Due
                   else E_Hooks_Done)),
               Moved);

         when Scenario_Cursor =>
            Seek_Scenario (R.Run.Ctx, Found);
            Bundle.Process_Event
              (R.Run,
               (Kind => (if Found then E_Scenario_Due else E_Scenarios_Done)),
               Moved);

         when Step_Cursor     =>
            Seek_Step (R.Run.Ctx, Found);
            Bundle.Process_Event
              (R.Run,
               (Kind => (if Found then E_Step_Due else E_Steps_Done)),
               Moved);

         when Shell_Moves     =>
            null;
      end case;
   end Move;

   --  Runs the machine until a request or a notice waits for the shell,
   --  or only the shell can move it on.
   procedure Advance (R : in out Runner) is
      Moved : Boolean := True;
   begin
      while Moved
        and then not R.Run.Ctx.Noticed
        and then R.Run.Ctx.Requests.Pending = C_None
      loop
         Move (R, Moved);
      end loop;
   end Advance;

   --  Fires one of the shell's own events, then advances.
   procedure Trigger (R : in out Runner; Kind : Event_Kind) is
      Handled : Boolean;
   begin
      Bundle.Process_Event (R.Run, (Kind => Kind), Handled);
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
        (Run =>
           (Count => Rows, M => Started, Ctx => (Opts => Opts, others => <>)));
      Advance (R);
   end Start_Run;

   procedure Start_Feature
     (R     : in out Runner;
      Doc   : Args.Document_Access;
      File  : String;
      Lines : Line_Selection) is
   begin
      R.Run.Ctx.Doc := Doc;
      R.Run.Ctx.Lines := Lines;
      R.Run.Ctx.Scenario := Ast.No_Scenario;
      R.Run.Ctx.Example := Expand.No_Example;
      R.Run.Ctx.Frame := (others => <>);
      R.Run.Ctx.Frame.File := Frames.To_Path (File);
      R.Run.Ctx.Frame.Feature :=
        Frames.To_Name (Ast.Text (Doc.all, Ast.Feature (Doc.all).Head.Name));
      R.Run.Ctx.Frame.Feature_Line := Ast.Feature (Doc.all).Head.Line;
      Trigger (R, E_Feature);
   end Start_Feature;

   procedure Note_Parse_Error (R : in out Runner) is
   begin
      Results.Add_Parse_Error (R.Run.Ctx.Totals);
   end Note_Parse_Error;

   procedure Finish_Run (R : in out Runner) is
   begin
      R.Run.Ctx.Frame := (others => <>);
      Trigger (R, E_Finish);
   end Finish_Run;

   --  The shell has read the notice.
   procedure Resume (R : in out Runner) is
   begin
      R.Run.Ctx.Noticed := False;
      Advance (R);
   end Resume;

   --  The shell's answer: it writes only the outcome and fires the
   --  event.  A hook request waits only in a hook state, and each hook
   --  state's Hook_Posted row routes the outcome to its phase's act.
   procedure Post_Hook_Result (R : in out Runner; Outcome : Check.Outcome) is
   begin
      R.Run.Ctx.Requests.Pending := C_None;
      R.Run.Ctx.Answer := Outcome;
      Trigger (R, E_Hook_Posted);
   end Post_Hook_Result;

   procedure Post_Step_Result (R : in out Runner; Outcome : Check.Outcome) is
   begin
      R.Run.Ctx.Requests.Pending := C_None;
      R.Run.Ctx.Answer := Outcome;
      Trigger (R, E_Step_Posted);
   end Post_Step_Result;

end Fabula.Run;
