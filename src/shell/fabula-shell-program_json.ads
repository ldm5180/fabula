--  JSON reporting, split out of Fabula.Shell.Program so neither file
--  trips the shape lint's file-size limit.  One instance renders one
--  run's whole report, streamed straight to Fabula.Shell.Reports as
--  each notice arrives -- see the package body for the machine that
--  places every comma and bracket without buffering a scenario or a
--  feature in memory.
with Fabula.Args;
with Fabula.Cli;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Run;

generic
   with package Reg is new Fabula.Registry (<>);
   with package Runner is new Fabula.Run (Reg => Reg, others => <>);
package Fabula.Shell.Program_Json with SPARK_Mode => Off is

   procedure Set_Document (Doc : Fabula.Args.Document_Access);

   --  Creates File for a Json_File target; sends every chunk to the
   --  console for any other target, and for a Json_File target whose
   --  File is empty.
   procedure Open_Target (Target : Fabula.Cli.Report_Target; File : String);

   --  The opening "[" or "," and the feature's own fields up to and
   --  including the open "elements" array; Doc names the feature.
   procedure Begin_Feature;

   --  The closing "]" of "elements" and the feature's remaining fields.
   procedure End_Feature (Path : String);

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame);

   --  The final "]" (or "[]" for an empty run), then, for the
   --  Json_Stdout target only, the one trailing newline standard output
   --  gets.
   procedure Close (Target : Fabula.Cli.Report_Target);

end Fabula.Shell.Program_Json;
