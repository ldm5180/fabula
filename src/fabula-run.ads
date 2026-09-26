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
with Fabula.Tags;
private with Fabula.Expand;
private with Sml.Machines;
private with Sml.Request_Block;

generic
   with package Reg is new Fabula.Registry (<>);
   Steps : Reg.Step_Table;
   Hooks : Reg.Hook_Table;
package Fabula.Run with SPARK_Mode is

   use type Args.Document_Access;
   use type Tags.Compiled;

   subtype Name_Filter_Length is
     Natural range 0 .. Limits.Max_Name_Filter_Length;

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
      Names               : String (1 .. Limits.Max_Name_Filter_Length) :=
        [others => ' '];
      Names_Len           : Name_Filter_Length := 0;
   end record;

   function Name_Patterns (Opts : Options) return String
   is (Opts.Names (1 .. Opts.Names_Len));

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
   type Line_List is array (1 .. Limits.Max_Line_Selections) of Positive;

   type Line_Selection is record
      Count : Line_Count := 0;
      Lines : Line_List := [others => 1];
   end record;

   All_Lines : constant Line_Selection := (Count => 0, Lines => [others => 1]);

   procedure Add_Line (Selection : in out Line_Selection; Line : Positive)
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

   ---------------------------------------------------------------------
   --  Notices, one at a time.  Scenario_Opened comes before its
   --  before-hooks, Scenario_Entered after them once the tag filter and
   --  the hooks have kept it.  Step_Closed and Scenario_Closed carry a
   --  final status; a Dropped scenario is ignored and counts nowhere.
   ---------------------------------------------------------------------

   type Notice_Kind is
     (Scenario_Opened, Scenario_Entered, Step_Closed, Scenario_Closed);

   --  Why a step has its status: it ran; it never ran because the
   --  scenario was skipped or failed, or an earlier step did not pass;
   --  no step definition matched it; or its expansion was too long.
   type Step_Cause is (Executed, Not_Run, No_Definition, Too_Long_Expansion);

   --  Outcome is the last failing outcome of the step, or of the
   --  scenario's own failure; it passes otherwise.  The handles name
   --  the scenario, its outline data row (0 for a plain scenario) and
   --  the step in the Document the feature started with.
   type Notice is record
      Kind     : Notice_Kind := Scenario_Opened;
      Status   : Results.Status := Results.Passed;
      Dropped  : Boolean := False;
      Cause    : Step_Cause := Executed;
      Scenario : Ast.Scenario_Handle := 0;
      Data_Row : Ast.Examples_Row_Handle := 0;
      Step     : Ast.Step_Handle := 0;
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

   --  The hook table's row for a hook request; 0 when none is pending.
   function Pending_Hook (R : Runner) return Natural;

   function Pending_Hook_Kind (R : Runner) return Reg.Hook_Kind
   with Pre => Next_Request (R) in C_Before_All | C_After_All | C_Hook;

   --  The step table's matching row for a step request; 0 when none.
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
   --  Finish from the shell's calls; Posted from a step body's outcome.
   type Event_Kind is
     (E_Hook_Due,
      E_Hooks_Done,
      E_Step_Due,
      E_Steps_Done,
      E_Scenario_Due,
      E_Scenarios_Done,
      E_Feature,
      E_Finish,
      E_Posted);

   type Event is record
      Kind : Event_Kind := E_Posted;
   end record;

   type Guard_Kind is
     (Always,
      Dropped,           --  ignored, or left out by the tag filter
      Must_Skip,         --  the scenario skips or failed, or a step before
      --                     this one did not pass and the run stops there
      Unmatched,         --  no step definition matches the text
      Oversized,         --  the expansion does not fit
      Step_Failed,       --  a before-step hook failed the step
      Failing);          --  the scenario itself failed

   --  What a transition asks the core to do.  The Ask_* acts are the
   --  shell's requests; the rest are the core's own bookkeeping.
   type Act is
     (Nothing,
      Ask_Before_All,
      Ask_After_All,
      Ask_Hook,
      Ask_Step,
      Open_Scenario,
      Enter_Scenario,
      Pass_Over,
      Mark_Undefined,
      Refuse_Step,
      Close_Step,
      Close_Scenario,
      Drop_Scenario,
      Close_Feature,
      Close_Opening,
      Close_Run);

   --  The machine context: the request block, the act the last
   --  transition asked for, and every flag the guards read.
   type Work is record
      Requests    : Req.Block;
      Due         : Act := Nothing;
      Continue    : Boolean := False;
      Selected    : Boolean := True;
      Ignored     : Boolean := False;
      Skipped     : Boolean := False;
      Failed      : Boolean := False;
      Last_Passed : Boolean := True;
      Text_Ok     : Boolean := False;
      Found       : Boolean := False;
      Args_Fit    : Boolean := False;
      Step_Failed : Boolean := False;
   end record;

   function Kind_Of (Evt : Event) return Event_Kind
   is (Evt.Kind);

   function Evaluate (G : Guard_Kind; Ctx : Work; Evt : Event) return Boolean;

   --  Records A; an Ask_* act also becomes the pending request.
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

   Rows : constant := 28;
   --  The transition table's length; a Runner embeds a machine of it.

   --  Hook is the row last requested in the current hook phase, 0 at
   --  its start.  Scenario and Example walk the feature; In_Background
   --  and Step walk one scenario's steps.  Tally counts this
   --  scenario's steps until it closes, so a dropped one counts none.
   type Runner is record
      Machine          : SM.Machine (Rows);
      Ctx              : Work;
      Opts             : Options;
      Doc              : Args.Document_Access;
      Lines            : Line_Selection;
      Frame            : Frames.Frame;
      Totals           : Results.Counts;
      Tally            : Results.Counts;
      Opening_Failed   : Boolean := False;
      Closing_Failed   : Boolean := False;
      Before_All_Fail  : Boolean := False;
      Noticed          : Boolean := False;
      Note             : Notice;
      Hook             : Natural := 0;
      Scenario         : Ast.Scenario_Handle := 0;
      Example          : Expand.Example_Ref;
      Tag_Set          : Expand.Tag_Set;
      In_Background    : Boolean := False;
      Step             : Ast.Step_Handle := 0;
      Text             : Expand.Text_Result;
      Match            : Reg.Match_Result;
      Step_Arguments   : Args.List;
      Step_Outcome     : Check.Outcome;
      Scenario_Outcome : Check.Outcome;
   end record;

   function Next_Request (R : Runner) return Command
   is (R.Ctx.Requests.Pending);

   function Has_Notice (R : Runner) return Boolean
   is (R.Noticed);

   function Between_Features (R : Runner) return Boolean
   is (SM.State_Of (R.Machine) = Ready
       and then not R.Noticed
       and then R.Ctx.Requests.Pending = C_None);

   function Run_Finished (R : Runner) return Boolean
   is (SM.State_Of (R.Machine) = Finished);

   function Current_Notice (R : Runner) return Notice
   is (R.Note);

   function Pending_Hook (R : Runner) return Natural
   is (if R.Ctx.Requests.Pending in C_Before_All | C_After_All | C_Hook
       then R.Hook
       else 0);

   function Pending_Step (R : Runner) return Natural
   is (if R.Ctx.Requests.Pending = C_Step then R.Match.Index else 0);

   function Step_Args (R : Runner) return Args.List
   is (R.Step_Arguments);

   function Current_Frame (R : Runner) return Frames.Frame
   is (R.Frame);

   function Counts_Of (R : Runner) return Results.Counts
   is (R.Totals);

end Fabula.Run;
