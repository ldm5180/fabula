--  Console rendering, split out of Fabula.Shell.Program so neither file
--  trips the shape lint's file-size limit.  One instance renders one
--  run: Fabula.Shell.Program owns the instance and feeds it the current
--  Document, the run's modes, and every notice in order.
with Fabula.Args;
with Fabula.Cli;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Results;
with Fabula.Run;
with Fabula.Tags;

generic
   with package Reg is new Fabula.Registry (<>);
   with package Runner is new Fabula.Run (Reg => Reg, others => <>);
package Fabula.Shell.Program_Console with SPARK_Mode => Off is

   procedure Set_Document (Doc : Fabula.Args.Document_Access);

   --  Quiet hides the feature and scenario headers, the step lines and
   --  the blank after each scenario; Verbose adds the -v lines.
   procedure Set_Log_Level (Level : Fabula.Cli.Log_Level);

   --  -d marks every scenario Skipped before Scenario_Entered fires
   --  (Fabula.Run.Enter), so this alone is enough to print the verbose
   --  "Scenario skipped" line for a dry run. A per-scenario Skip called
   --  from a step definition's own before-hook has no such run-wide
   --  flag -- Notice carries no word of it, and there is no accessor
   --  for it on Fabula.Run -- so that trigger stays unprinted, a known,
   --  disclosed gap.
   procedure Set_Dry_Run (Dry_Run : Boolean);

   --  Filter is read only when Has_Filter; a caller that never sets one
   --  before Has_Filter is asked leaves the verbose tag-check silent
   --  about it (docs/report_wiring.md's "No tags given" line, always
   --  the safe default of Set_Modes' own initial state).
   procedure Set_Filter
     (Has_Filter : Boolean; Filter : Fabula.Tags.Compiled; Tag_Expr : String);

   --  The feature header (no notice covers it -- Fabula.Run has none).
   procedure Begin_Feature (Path : String);

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame);

   --  The failed-scenarios trailer and the two summary lines, once per
   --  run, after every feature has driven to the end.
   procedure Print_Trailer_And_Summaries (Counts : Fabula.Results.Counts);

end Fabula.Shell.Program_Console;
