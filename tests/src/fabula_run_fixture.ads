--  The runner's test registry: one step table, a hook table per
--  concern, a runner instance over each, and a scripted shell for each
--  instance.  Each step and hook kind's outcome is fixed by its name,
--  so a trace reads as the scenario it scripts.
with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Run;

with Fabula_Run_Script;

package Fabula_Run_Fixture is

   type Box_Step is
     (Pass,             --  passes
      Fail_Check,       --  a failed check
      Call_Skip,        --  skips the scenario
      Call_Ignore,      --  ignores the scenario
      Call_Fail,        --  fails the scenario
      Call_Fail_Step,   --  fails the step
      Place,            --  passes; traces its two captures and its lines
      Read_Doc,         --  passes; traces its doc string
      Read_Table);      --  passes; traces its table's cell 1,2

   type Box_Hook is
     (Start_Note,       --  the Note kinds pass
      Start_Fail,       --  a failed check
      End_Note,
      End_Fail,         --  a failed check
      Open_Note,
      Open_Tagged,
      Open_Loud,
      Open_Both,
      Open_Skip,        --  skips the scenario
      Open_Ignore,      --  ignores the scenario
      Open_Fail,        --  fails the scenario
      Open_Check,       --  a failed check
      Close_Note,
      Close_Fail,       --  fails the scenario
      Close_Skip,       --  skips the scenario
      Close_Ignore,     --  ignores the scenario
      Close_Check,      --  a failed check
      Dispatch,
      Step_In,
      Step_Out,
      Step_In_Guard,    --  fails a step whose text holds "guarded"
      Step_Out_Watch,   --  a failed check on a step holding "watched"
      Step_In_Control); --  skips the scenario at a step holding
   --                         "skipping", fails it at one holding "doomed"

   type Box_Context is record
      Items : Natural := 0;
   end record;

   package Box is new
     Fabula.Registry
       (Step_Kind => Box_Step,
        Hook_Kind => Box_Hook,
        Context   => Box_Context);
   use Box;

   Box_Steps : constant Step_Table :=
     [Step ("a passing step") >= Pass,
      Step ("a background step") >= Pass,
      Step ("a guarded passing step") >= Pass,
      Step ("a watched passing step") >= Pass,
      Step ("a skipping passing step") >= Pass,
      Step ("a doomed passing step") >= Pass,
      Step ("a failing step") >= Fail_Check,
      Step ("a step that skips") >= Call_Skip,
      Step ("a step that ignores") >= Call_Ignore,
      Step ("a step that fails the scenario") >= Call_Fail,
      Step ("a step that fails itself") >= Call_Fail_Step,
      Step ("I place {int} x {word}") >= Place,
      Step ("a step reading its doc string") >= Read_Doc,
      Step ("a step reading its table") >= Read_Table];

   --  An unknown parameter key refuses to compile.
   Refused_Steps : constant Step_Table := [Step ("I have {foo}") >= Pass];

   No_Hooks : constant Hook_Table := [];

   Lifecycle_Hooks : constant Hook_Table :=
     [Before_All >= Start_Note,
      After_All >= End_Note,
      Before >= Open_Note,
      After >= Close_Note,
      Before_Step >= Step_In,
      After_Step >= Step_Out];

   --  One hook per phase, each phase's row above the phase before it:
   --  a phase that starts its walk where the last phase stopped finds
   --  no row of its own.
   Reversed_Hooks : constant Hook_Table :=
     [After_All >= End_Note,
      After >= Close_Note,
      After_Step >= Step_Out,
      Before_Step >= Step_In,
      Before >= Open_Note,
      Before_All >= Start_Note];

   --  The reference interpreter's example hooks, and their mirrors.
   Control_Hooks : constant Hook_Table :=
     [Before ("@skip") >= Open_Skip,
      Before ("@ignore") >= Open_Ignore,
      Before ("@fail_before") >= Open_Fail,
      Before ("@check_before") >= Open_Check,
      After ("@fail_after") >= Close_Fail,
      After ("@skip_after") >= Close_Skip,
      After ("@ignore_after") >= Close_Ignore,
      After ("@check_after") >= Close_Check,
      After >= Close_Note];

   Noted_Hooks : constant Hook_Table :=
     [Before >= Open_Note, After >= Close_Note];

   Tagged_Hooks : constant Hook_Table :=
     [Before >= Open_Note,
      Before ("@ship or @important") >= Open_Tagged,
      Before ("not @quiet") >= Open_Loud,
      Before ("@from_feature and @from_examples") >= Open_Both,
      After ("@ship or @important") >= Dispatch];

   Step_Hooks : constant Hook_Table :=
     [Before_Step >= Step_In_Guard,
      After_Step >= Step_Out_Watch,
      After >= Close_Note];

   --  A before-step hook that skips or fails the scenario.
   Step_Control_Hooks : constant Hook_Table :=
     [Before_Step >= Step_In_Control, After >= Close_Note];

   --  Every Before_All runs even after one fails.
   Doomed_Hooks : constant Hook_Table :=
     [Before_All >= Start_Fail,
      Before_All >= Start_Note,
      After_All >= End_Fail,
      Before >= Open_Note,
      After >= Close_Note];

   function Hook_Outcome
     (Kind : Box_Hook; Frame : Fabula.Frames.Frame)
      return Fabula.Check.Outcome;

   function Step_Outcome (Kind : Box_Step) return Fabula.Check.Outcome;

   function Step_Note
     (Kind : Box_Step; A : Fabula.Args.List; F : Fabula.Frames.Frame)
      return String;

   package Bare_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => No_Hooks);
   package Lifecycle_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Lifecycle_Hooks);
   package Reversed_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Reversed_Hooks);
   package Control_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Control_Hooks);
   package Noted_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Noted_Hooks);
   package Labeled_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Tagged_Hooks);
   package Stepped_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Step_Hooks);
   package Step_Control_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Step_Control_Hooks);
   package Doomed_Run is new
     Fabula.Run (Reg => Box, Steps => Box_Steps, Hooks => Doomed_Hooks);
   package Refused_Run is new
     Fabula.Run (Reg => Box, Steps => Refused_Steps, Hooks => No_Hooks);

   package Bare is new
     Fabula_Run_Script.Shell (Bare_Run, Hook_Outcome, Step_Outcome, Step_Note);
   package Lifecycle is new
     Fabula_Run_Script.Shell
       (Lifecycle_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Reversed is new
     Fabula_Run_Script.Shell
       (Reversed_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Control is new
     Fabula_Run_Script.Shell
       (Control_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Noted is new
     Fabula_Run_Script.Shell
       (Noted_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Labeled is new
     Fabula_Run_Script.Shell
       (Labeled_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Stepped is new
     Fabula_Run_Script.Shell
       (Stepped_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Step_Controlled is new
     Fabula_Run_Script.Shell
       (Step_Control_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);
   package Doomed is new
     Fabula_Run_Script.Shell
       (Doomed_Run,
        Hook_Outcome,
        Step_Outcome,
        Step_Note);

end Fabula_Run_Fixture;
