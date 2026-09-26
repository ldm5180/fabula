with Fabula.Shell.Program;

procedure Fabula.Main is
   package Program is new
     Fabula.Shell.Program
       (Steps     => Steps,
        Step_Defs => Step_Defs,
        Hook_Defs => Hook_Defs,
        Execute   => Execute,
        Run_Hook  => Run_Hook);
begin
   Program.Run;
end Fabula.Main;
