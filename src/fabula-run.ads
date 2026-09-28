--  The runner: each scenario's lifecycle as an sml machine -- its
--  before-hooks, the background steps, its own steps, its after-hooks
--  -- with the run and feature bookkeeping around it.  The core never
--  calls user code.  A hook or step it wants run becomes a request the
--  shell reads, runs and answers with the outcome.  At each moment
--  worth reporting (a scenario opening or entering, a step or scenario
--  closing) it pauses on a notice until the shell resumes it.
with Fabula.Args;
with Fabula.Ast;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Limits;
with Fabula.Registry;
with Fabula.Results;
with Fabula.Searches;
with Fabula.Tags;
with Fabula.Texts;
private with Fabula.Expand;
private with Fabula.Step_Walk;
private with Sml.Machines;
private with Sml.Machines.Bundled;
private with Sml.Request_Block;

generic
   with package Reg is new Fabula.Registry (<>);
   Steps : Reg.Step_Table;
   Hooks : Reg.Hook_Table;
package Fabula.Run with SPARK_Mode is

   use type Args.Document_Access;
   use type Tags.Compiled;

   --  What the command line asks of the whole run.  Names holds the -n
   --  patterns, ':'-separated; an empty list selects every scenario.
   --  Undefined steps always fail a scenario, so Strict_Undefined is
   --  reserved and never read.
   type Options is record
      Dry_Run             : Boolean := False;
      Continue_On_Failure : Boolean := False;
      Strict_Undefined    : Boolean := True;
      Filter              : Tags.Compiled;
      Has_Filter          : Boolean := False;
      Names               : Texts.Bounded_Text (Limits.Max_Name_Filter_Length);
   end record;

   function Name_Patterns (Opts : Options) return String
   is (Texts.Value (Opts.Names));

   --  Sets the -n patterns; the tag filter is left as it was.
   procedure Set_Names (Opts : in out Options; Patterns : String)
   with
     Pre  => Patterns'Length <= Limits.Max_Name_Filter_Length,
     Post =>
       Name_Patterns (Opts) = Patterns
       and then Opts.Has_Filter = Opts'Old.Has_Filter
       and then Opts.Filter = Opts'Old.Filter;

   --  The lines one file:line argument selects.  A scenario is selected
   --  by its header's line, a concrete outline scenario by its data
   --  row's line.  An empty selection selects every scenario.
   subtype Line_Count is Natural range 0 .. Limits.Max_Line_Selections;
   type Line_List is array (1 .. Limits.Max_Line_Selections) of Source_Line;

   --  The count of an empty selection.
   None_Selected : constant Line_Count := 0;

   --  What fills Lines past Count; no reader looks there.
   Unused_Line : constant Source_Line := First_Line;

   type Line_Selection is record
      Count : Line_Count := None_Selected;
      Lines : Line_List := [others => Unused_Line];
   end record;

   All_Lines : constant Line_Selection := (others => <>);

   procedure Add_Line (Selection : in out Line_Selection; Line : Source_Line)
   with
     Pre  => Selection.Count < Limits.Max_Line_Selections,
     Post => Selection.Count = Selection.Count'Old + 1;

   ---------------------------------------------------------------------
   --  Requests.  C_Before_All, C_After_All and C_Hook ask the shell to
   --  run the hook Pending_Hook names; C_Step asks it to run the step
   --  Pending_Step names, with Step_Args.  Current_Frame is the
   --  position either sees.  The shell answers with Post_Hook_Result
   --  or Post_Step_Result.
   ---------------------------------------------------------------------

   type Command is (C_None, C_Before_All, C_After_All, C_Hook, C_Step);

   --  The row Pending_Hook and Pending_Step name when no request of
   --  theirs is pending; table rows are numbered from 1.
   No_Row : constant Natural := Searches.Not_Found;

   ---------------------------------------------------------------------
   --  Notices, one at a time.  Scenario_Opened comes before its
   --  before-hooks, Scenario_Entered after them once the tag filter and
   --  the hooks have kept it.  Step_Closed and Scenario_Closed carry a
   --  final status; a Dropped scenario is ignored and counts nowhere.
   --  Entered says the scenario got past Scenario_Entered: a scenario
   --  dropped by its before-hooks or the tag filter never did, one
   --  dropped by a step or an after-hook always did.
   ---------------------------------------------------------------------

   type Notice_Kind is
     (Scenario_Opened, Scenario_Entered, Step_Closed, Scenario_Closed);

   --  Why a step has its status: it ran; it never ran because the
   --  scenario was skipped or failed, or an earlier step did not pass;
   --  no step definition matched it; or its expansion was too long.
   type Step_Cause is (Executed, Not_Run, No_Definition, Too_Long_Expansion);

   --  Outcome is the last failing outcome of the step, or of the
   --  scenario's own failure; it passes otherwise.  The handles name
   --  the scenario, its outline data row (none for a plain scenario)
   --  and the step in the Document the feature started with.
   type Notice is record
      Kind     : Notice_Kind := Scenario_Opened;
      Status   : Results.Status := Results.Passed;
      Dropped  : Boolean := False;
      Entered  : Boolean := False;
      Cause    : Step_Cause := Executed;
      Scenario : Ast.Scenario_Handle := Ast.No_Scenario;
      Data_Row : Ast.Examples_Row_Handle := Ast.No_Examples_Row;
      Step     : Ast.Step_Handle := Ast.No_Step;
      Outcome  : Check.Outcome;
   end record;

   --  The message of a step refused because its expansion is too long.
   Too_Long_Message : constant String :=
     "The step does not fit the line limit once expanded";

   type Runner is private;

   --  Both tables compiled and bound; the binary refuses to run
   --  otherwise, naming the bad rows.
   function Tables_Valid return Boolean
   is (Reg.Steps_Valid (Steps) and then Reg.Hooks_Valid (Hooks));

   function Next_Request (R : Runner) return Command;
   function Has_Notice (R : Runner) return Boolean;

   --  Idle with no feature open: the run is ready for Start_Feature,
   --  Note_Parse_Error or Finish_Run.
   function Between_Features (R : Runner) return Boolean;

   function Run_Finished (R : Runner) return Boolean;

   --  What the runner waits for from the shell.  Idle means between
   --  features or finished.  Clash (a request and a notice at once) and
   --  Stuck (neither, inside a feature) are core defects the shell
   --  cannot answer.
   type Wait_Kind is
     (Notice_Wait,     --  read the notice, then Resume
      Step_Wait,       --  run the step, then Post_Step_Result
      All_Hook_Wait,   --  run a Before_All or After_All hook
      Hook_Wait,       --  run a scenario or step hook
      Idle,
      Clash,
      Stuck);

   function Waiting_For (R : Runner) return Wait_Kind;

   ---------------------------------------------------------------------
   --  Driving a run.
   ---------------------------------------------------------------------

   --  Readies R for a run; the Before_All hooks are its first requests.
   procedure Start_Run (R : out Runner; Opts : Options)
   with
     Pre =>
       Tables_Valid
       and then (if Opts.Has_Filter then Tags.Valid (Opts.Filter));

   --  Runs one parsed feature file.  Doc must stay unchanged until
   --  Between_Features holds again: no step's Args and no pending
   --  request may outlive a refill of the Document it designates.
   procedure Start_Feature
     (R     : in out Runner;
      Doc   : Args.Document_Access;
      File  : String;
      Lines : Line_Selection)
   with Pre => Between_Features (R) and then Doc /= null;

   --  Counts a feature file that failed to parse.
   procedure Note_Parse_Error (R : in out Runner)
   with Pre => Between_Features (R), Post => Between_Features (R);

   --  Ends the run; the After_All hooks are its last requests.
   procedure Finish_Run (R : in out Runner)
   with Pre => Between_Features (R);

   function Current_Notice (R : Runner) return Notice
   with Pre => Has_Notice (R);

   --  Clears the notice and carries on to the next request or notice.
   procedure Resume (R : in out Runner)
   with Pre => Has_Notice (R);

   ---------------------------------------------------------------------
   --  The pending request.
   ---------------------------------------------------------------------

   --  The hook table's row for a hook request; No_Row when none is
   --  pending.
   function Pending_Hook (R : Runner) return Natural;

   function Pending_Hook_Kind (R : Runner) return Reg.Hook_Kind
   with Pre => Next_Request (R) in C_Before_All | C_After_All | C_Hook;

   --  The step table's matching row for a step request; No_Row when
   --  none is pending.
   function Pending_Step (R : Runner) return Natural;

   function Pending_Step_Kind (R : Runner) return Reg.Step_Kind
   with Pre => Next_Request (R) = C_Step;

   function Step_Args (R : Runner) return Args.List
   with Pre => Next_Request (R) = C_Step;

   function Current_Frame (R : Runner) return Frames.Frame;

   procedure Post_Hook_Result (R : in out Runner; Outcome : Check.Outcome)
   with Pre => Next_Request (R) in C_Before_All | C_After_All | C_Hook;

   procedure Post_Step_Result (R : in out Runner; Outcome : Check.Outcome)
   with Pre => Next_Request (R) = C_Step;

   function Counts_Of (R : Runner) return Results.Counts;

private

   package Req is new Sml.Request_Block (Command => Command, None => C_None);

   --  Opening and Closing run the all-hooks; Ready waits between
   --  features and Walking between one feature's scenarios.  A step
   --  passes through Step_Before, Step_Body and Step_After.
   type State is
     (Opening,
      Ready,
      Walking,
      Before,
      Stepping,
      Step_Before,
      Step_Body,
      Step_After,
      After,
      Closing,
      Finished);

   --  The *_Due events come from the core's cursors; Feature and
   --  Finish from the shell's calls; Hook_Posted and Step_Posted from
   --  the shell's answer, once it has written the outcome to Answer.
   type Event_Kind is
     (E_Hook_Due,
      E_Hooks_Done,
      E_Step_Due,
      E_Steps_Done,
      E_Scenario_Due,
      E_Scenarios_Done,
      E_Feature,
      E_Finish,
      E_Hook_Posted,
      E_Step_Posted);

   type Event is record
      Kind : Event_Kind := E_Step_Posted;
   end record;

   --  What the cursor of each state walks, and for a hook state, the
   --  phase of the hook rows it walks.  Only the shell moves the runner
   --  on from the other states.
   type Cursor_Kind is
     (Hook_Cursor, Scenario_Cursor, Step_Cursor, Shell_Moves);

   type State_Fact (Cursor : Cursor_Kind := Shell_Moves) is record
      case Cursor is
         when Hook_Cursor =>
            Phase : Reg.Hook_Phase;

         when others =>
            null;
      end case;
   end record;

   Facts : constant array (State) of State_Fact :=
     [Opening     => (Hook_Cursor, Reg.Run_Start),
      Ready       => (Cursor => Shell_Moves),
      Walking     => (Cursor => Scenario_Cursor),
      Before      => (Hook_Cursor, Reg.Scenario_Start),
      Stepping    => (Cursor => Step_Cursor),
      Step_Before => (Hook_Cursor, Reg.Step_Start),
      Step_Body   => (Cursor => Shell_Moves),
      Step_After  => (Hook_Cursor, Reg.Step_End),
      After       => (Hook_Cursor, Reg.Scenario_End),
      Closing     => (Hook_Cursor, Reg.Run_End),
      Finished    => (Cursor => Shell_Moves)];

   --  How the scenario stands so far.  A skip never undoes a failure,
   --  so a new standing is the greater of the old and the new.
   type Disposition is (Running, Skipped, Failed);

   type Guard_Kind is
     (Always,
      Dropped,             --  ignored, or left out by the tag filter
      Skips_All,           --  a dry run, or a failed Before_All in a run
      --                       that stops on failure: no step runs
      Unmatched,           --  no step definition matches the text
      Must_Skip,           --  the scenario skips or failed, or a step
      --                       before this one did not pass and the run
      --                       stops there
      Oversized,           --  the expansion does not fit
      Step_Failed,         --  a step hook or the body failed the step
      Failing,             --  the scenario itself failed
      Before_All_Failed,   --  a Before_All hook failed
      After_All_Failed);   --  an After_All hook failed

   --  What a transition does.  The Ask_* acts are the shell's requests,
   --  and the Take_* acts apply its answers; the rest are the core's own
   --  bookkeeping.  The acts are declared in groups, so each group below
   --  is a range.
   type Act is
     (Nothing,
      Ask_Before_All,
      Ask_After_All,
      Ask_Hook,
      Ask_Step,
      Take_Run_Start,
      Take_Run_End,
      Take_Scenario_Start,
      Take_Scenario_End,
      Take_Step_Start,
      Take_Step_End,
      Take_Step_Result,
      Open_Scenario,
      Enter_Scenario,
      Enter_Skipped,
      Close_Scenario,
      Drop_Unentered,
      Drop_Entered,
      Mark_Undefined,
      Skip_Step,
      Refuse_Step,
      Fail_Step,
      Pass_Step,
      Close_Feature,
      Count_Hook_Error);

   --  The acts that ask the shell to run a hook or a step.
   subtype Request_Act is Act range Ask_Before_All .. Ask_Step;

   --  The acts that apply the shell's posted outcome: one for each hook
   --  phase, named after it, and one for a step's body.
   subtype Result_Act is Act range Take_Run_Start .. Take_Step_Result;

   --  The acts that open, enter, close or drop a scenario.
   subtype Scenario_Act is Act range Open_Scenario .. Drop_Entered;

   --  The acts that close a step without running it, or after it ran.
   subtype Step_Act is Act range Mark_Undefined .. Pass_Step;

   --  The feature's and the whole run's bookkeeping.
   subtype Feature_Act is Act range Close_Feature .. Count_Hook_Error;

   --  The machine context: every field the guards read and the acts
   --  write.  Hook is the row last requested in the current hook phase,
   --  No_Row at its start.  Scenario and Example walk the feature; Walk
   --  walks one scenario's steps.  Tally counts this scenario's steps
   --  until it closes, so a dropped one counts none.
   type Work is record
      --  The run's options, loaded once by Start_Run.
      Opts : Options;

      --  This feature, and the scenario filter's lines.
      Doc   : Args.Document_Access;
      Lines : Line_Selection;

      --  A hook's or a step's outcome, written by the shell before
      --  E_Hook_Posted or E_Step_Posted.
      Answer : Check.Outcome;

      --  What waits for the shell: one request, or one notice.
      Requests : Req.Block;
      Noticed  : Boolean := False;
      Note     : Notice;

      --  What the shell reads with a request or a notice.
      Frame          : Frames.Frame;
      Hook           : Natural := No_Row;
      Match          : Reg.Match_Result;
      Step_Arguments : Args.List;

      --  The run.
      Totals            : Results.Counts;
      Before_All_Failed : Boolean := False;
      After_All_Failed  : Boolean := False;

      --  The scenario walk: where it stands, and how the scenario stands.
      Scenario         : Ast.Scenario_Handle := Ast.No_Scenario;
      Example          : Expand.Example_Ref;
      Tag_Set          : Expand.Tag_Set;
      Selected         : Boolean := True;
      Ignored          : Boolean := False;
      Standing         : Disposition := Running;
      Scenario_Outcome : Check.Outcome;
      Tally            : Results.Counts;

      --  The step walk: the step, and what resolving it found.
      Walk         : Step_Walk.Walk := Step_Walk.Empty;
      Text         : Expand.Text_Result;
      Args_Fit     : Boolean := False;
      Last_Passed  : Boolean := True;
      Step_Failed  : Boolean := False;
      Step_Outcome : Check.Outcome;
   end record;

   function Kind_Of (Evt : Event) return Event_Kind
   is (Evt.Kind);

   function Evaluate (G : Guard_Kind; Ctx : Work; Evt : Event) return Boolean;

   --  Does A's work on Ctx; an Ask_* act also writes its request.
   procedure Execute (A : Act; Ctx : in out Work; Evt : Event);

   package SM is new
     Sml.Machines
       (State       => State,
        Event_Kind  => Event_Kind,
        Event       => Event,
        Context     => Work,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Act,
        Kind_Of     => Kind_Of,
        Evaluate    => Evaluate,
        Execute     => Execute);

   package Bundle is new SM.Bundled;

   Rows : constant := 38;
   --  The transition table's length; a Runner embeds a machine of it.

   --  The machine and its context, in one object: nothing of the run
   --  is kept beside the machine.
   type Runner is record
      Run : Bundle.Instance (Rows);
   end record;

   function Next_Request (R : Runner) return Command
   is (R.Run.Ctx.Requests.Pending);

   function Has_Notice (R : Runner) return Boolean
   is (R.Run.Ctx.Noticed);

   function Between_Features (R : Runner) return Boolean
   is (Bundle.State_Of (R.Run) = Ready
       and then not R.Run.Ctx.Noticed
       and then R.Run.Ctx.Requests.Pending = C_None);

   function Run_Finished (R : Runner) return Boolean
   is (Bundle.State_Of (R.Run) = Finished);

   function Waiting_For (R : Runner) return Wait_Kind
   is (if R.Run.Ctx.Noticed and then R.Run.Ctx.Requests.Pending /= C_None
       then Clash
       elsif R.Run.Ctx.Noticed
       then Notice_Wait
       else
         (case R.Run.Ctx.Requests.Pending is
            when C_Step                     => Step_Wait,
            when C_Before_All | C_After_All => All_Hook_Wait,
            when C_Hook                     => Hook_Wait,
            when C_None                     =>
              (if Bundle.State_Of (R.Run) in Ready | Finished
               then Idle
               else Stuck)));

   function Current_Notice (R : Runner) return Notice
   is (R.Run.Ctx.Note);

   function Pending_Hook (R : Runner) return Natural
   is (if R.Run.Ctx.Requests.Pending in C_Before_All | C_After_All | C_Hook
       then R.Run.Ctx.Hook
       else No_Row);

   function Pending_Step (R : Runner) return Natural
   is (if R.Run.Ctx.Requests.Pending = C_Step
       then R.Run.Ctx.Match.Index
       else No_Row);

   function Step_Args (R : Runner) return Args.List
   is (R.Run.Ctx.Step_Arguments);

   function Current_Frame (R : Runner) return Frames.Frame
   is (R.Run.Ctx.Frame);

   function Counts_Of (R : Runner) return Results.Counts
   is (R.Run.Ctx.Totals);

end Fabula.Run;
