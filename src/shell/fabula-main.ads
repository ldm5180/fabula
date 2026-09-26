--  The generic the user instantiates as their binary: argv in, the
--  report out, the exit status set.  A thin wrapper over
--  Fabula.Shell.Program so this body stays a one-line frame, well under
--  the shape lint's limits -- the real wiring lives in that package's
--  many small, non-nested subprograms.
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
procedure Fabula.Main
with SPARK_Mode => Off;
