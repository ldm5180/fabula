--  The drive loop: it answers the runner's requests by running the
--  user's steps and hooks, and hands each notice to the caller.  User
--  code may raise; the exception becomes the failed outcome of the step
--  or hook that raised it, and the run goes on.
with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Run;
with Fabula.Shell.Files;

generic
   with package Reg is new Fabula.Registry (<>);
   with package Runner is new Fabula.Run (Reg => Reg, others => <>);

   --  Runs step S's body: A holds its arguments, Info its position.
   with
     procedure Execute
       (S    : Reg.Step_Kind;
        Ctx  : in out Reg.Context;
        A    : Fabula.Args.List;
        Info : Fabula.Frames.Frame;
        R    : in out Fabula.Check.Outcome);

   with
     procedure Run_Hook
       (H    : Reg.Hook_Kind;
        Ctx  : in out Reg.Context;
        Info : Fabula.Frames.Frame;
        R    : in out Fabula.Check.Outcome);

   --  Sees each notice with the runner's frame at that moment: the
   --  scenario's name and line, and at Step_Closed the step's text as
   --  run and its line.  An exception it raises propagates out of Drive.
   with procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame);

package Fabula.Shell.Dispatch with SPARK_Mode => Off
is

   --  Answers requests and passes on notices until the runner is between
   --  features or finished.  A request runs its step or hook once on a
   --  copy of its context, kept only on a normal return; an exception
   --  posts its message (its name if empty) in place of the outcome.
   --  Ctx is the scenario's context, fresh at each Scenario_Opened;
   --  All_Ctx is the run's, for Before_All and After_All.  A runner that
   --  stops elsewhere, never stops, or holds a request and a notice
   --  together is a core defect, and Drive raises Program_Error.
   procedure Drive
     (R       : in out Runner.Runner;
      Ctx     : in out Reg.Context;
      All_Ctx : in out Reg.Context);

   --  The runner's selection for one file's line numbers.
   function Selection
     (Lines : Fabula.Shell.Files.Line_Numbers) return Runner.Line_Selection;

   --  Sets the -n patterns when they fit the runner's bound; Fits says
   --  whether they did, and Opts is unchanged when they do not.  Call it
   --  before Start_Run.
   procedure Set_Names
     (Opts : in out Runner.Options; Patterns : String; Fits : out Boolean);

end Fabula.Shell.Dispatch;
