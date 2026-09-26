--  The whole program behind Fabula.Main: argv to exit status.  Wires
--  Fabula.Run/Fabula.Shell.Dispatch/Fabula.Shell.Files/Fabula.Format/
--  Fabula.Shell.Console/Fabula.Shell.Reports together exactly as
--  docs/report_wiring.md sequences them.  Fabula.Main is a thin generic
--  procedure over this package so its own body stays within the shape
--  lint's per-body limits; users instantiate Fabula.Main, never this.
with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;

generic
   with package Steps is new Fabula.Registry (<>);
   Step_Defs : Steps.Step_Table;
   Hook_Defs : Steps.Hook_Table;

   with
     procedure Execute
       (S    : Steps.Step_Kind;
        Ctx  : in out Steps.Context;
        A    : Fabula.Args.List;
        Info : Fabula.Frames.Frame;
        R    : in out Fabula.Check.Outcome);

   with
     procedure Run_Hook
       (H    : Steps.Hook_Kind;
        Ctx  : in out Steps.Context;
        Info : Fabula.Frames.Frame;
        R    : in out Fabula.Check.Outcome);
package Fabula.Shell.Program with SPARK_Mode => Off is

   --  Parses argv (Ada.Command_Line), runs every discovered feature file,
   --  writes the console or JSON report, and sets the process exit
   --  status: 1 when Fabula.Results.Run_Failed, else 0.
   procedure Run;

end Fabula.Shell.Program;
