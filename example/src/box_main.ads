--  The box binary: Fabula.Main instantiated over Box_Steps, exactly
--  the shape the README shows for a user's own binary.
with Box_Steps;
with Fabula.Main;

procedure Box_Main is new
  Fabula.Main
    (Steps     => Box_Steps.Steps,
     Step_Defs => Box_Steps.Step_Defs,
     Hook_Defs => Box_Steps.Hook_Defs,
     Execute   => Box_Steps.Execute,
     Run_Hook  => Box_Steps.Run_Hook);
