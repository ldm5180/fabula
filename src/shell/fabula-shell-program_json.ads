--  JSON reporting, split out of Fabula.Shell.Program so neither file
--  trips the shape lint's file-size limit.  One instance renders one
--  run's whole report, streamed straight to Fabula.Shell.Reports as
--  each notice arrives -- see the package body for the streaming rule
--  that lets it avoid buffering a scenario or a feature in memory.
with Fabula.Args;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Run;
with Fabula.Shell.Reports;

generic
   with package Reg is new Fabula.Registry (<>);
   with package Runner is new Fabula.Run (Reg => Reg, others => <>);
package Fabula.Shell.Program_Json with SPARK_Mode => Off is

   procedure Set_Document (Doc : Fabula.Args.Document_Access);

   --  Creates the file, or sends chunks to the console, per Has_File.
   procedure Open_Target
     (File     : String;
      Has_File : Boolean;
      Status   : out Fabula.Shell.Reports.Status);

   --  The opening "[" or "," and the feature's own fields up to and
   --  including the open "elements" array; Doc names the feature.
   procedure Begin_Feature;

   --  The closing "]" of "elements" and the feature's remaining fields.
   procedure End_Feature (Path : String);

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame);

   --  The final "]" (or "[]" for an empty run), then, when Has_File is
   --  False, the one trailing newline stdout gets that a file does not.
   procedure Close (Has_File : Boolean);

end Fabula.Shell.Program_Json;
