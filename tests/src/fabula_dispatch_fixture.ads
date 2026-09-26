--  The drive loop's test registry: steps and hooks that count in their
--  context, raise on demand, and trace every call they get.  Each
--  notice is traced as the P7 scripted shell traces it, read from the
--  frame the drive loop hands over.
with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Run;
with Fabula.Shell.Dispatch;

with Fabula_Run_Script;

package Fabula_Dispatch_Fixture is

   type Tally_Step is
     (Pass,             --  passes
      Count,            --  adds one to the context and traces the sum
      Raise_Message,    --  raises Constraint_Error with "boom"
      Raise_Bare,       --  raises Bare_Error with an empty message
      Misread,          --  reads a word capture as an Int
      Fail_And_Raise,   --  fails the scenario, then raises
      Count_And_Raise); --  adds one to the context, traces it, then raises

   type Tally_Hook is
     (Run_Open,         --  adds one to the run's context
      Run_Close,        --  traces the run's context
      Run_Raise,        --  raises "run boom"
      Open_Count,       --  adds one to the scenario's context
      Open_Raise);      --  raises "hook boom"

   --  Padded past what the compiler passes by copy, so a body that edits
   --  its context and then raises edits the caller's object in place.
   Pad_Bytes : constant := 512;

   type Tally_Context is record
      Items : Natural := 0;
      Pad   : String (1 .. Pad_Bytes) := [others => ' '];
   end record;

   Bare_Error : exception;

   package Tally is new
     Fabula.Registry
       (Step_Kind => Tally_Step,
        Hook_Kind => Tally_Hook,
        Context   => Tally_Context);
   use Tally;

   Tally_Steps : constant Step_Table :=
     [Step ("a passing step") >= Pass,
      Step ("I count") >= Count,
      Step ("it raises with a message") >= Raise_Message,
      Step ("it raises bare") >= Raise_Bare,
      Step ("I read {word} as a number") >= Misread,
      Step ("it fails the scenario and raises") >= Fail_And_Raise,
      Step ("I count and raise") >= Count_And_Raise];

   Counting_Hooks : constant Hook_Table :=
     [Before_All >= Run_Open, After_All >= Run_Close, Before >= Open_Count];

   Raising_Hooks : constant Hook_Table :=
     [Before_All >= Run_Raise, Before ("@boom") >= Open_Raise];

   package Counting_Run is new
     Fabula.Run (Reg => Tally, Steps => Tally_Steps, Hooks => Counting_Hooks);
   package Raising_Run is new
     Fabula.Run (Reg => Tally, Steps => Tally_Steps, Hooks => Raising_Hooks);

   --  Every call and every notice, in order.
   Log : Fabula_Run_Script.Trace;

   procedure Execute
     (S    : Tally_Step;
      Ctx  : in out Tally_Context;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

   procedure Run_Hook
     (H    : Tally_Hook;
      Ctx  : in out Tally_Context;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

   procedure Counting_Notice
     (N : Counting_Run.Notice; Info : Fabula.Frames.Frame);
   procedure Raising_Notice
     (N : Raising_Run.Notice; Info : Fabula.Frames.Frame);

   package Counting is new
     Fabula.Shell.Dispatch
       (Reg       => Tally,
        Runner    => Counting_Run,
        Execute   => Execute,
        Run_Hook  => Run_Hook,
        On_Notice => Counting_Notice);

   package Raising is new
     Fabula.Shell.Dispatch
       (Reg       => Tally,
        Runner    => Raising_Run,
        Execute   => Execute,
        Run_Hook  => Run_Hook,
        On_Notice => Raising_Notice);

end Fabula_Dispatch_Fixture;
